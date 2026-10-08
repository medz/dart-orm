import 'dart:io';

import 'package:dart_style/dart_style.dart';
import 'package:orm/database.dart' show Engine;
import 'package:path/path.dart' as p;

import 'emit.dart';
import 'model.dart';
import 'read_schema.dart';

/// Complete deterministic Dart outputs. The snapshot imports no application models.
final class GeneratedSources {
  const GeneratedSources._({
    required this.database,
    required this.snapshot,
    required this._schemaPath,
    required this._outputPath,
  });
  final String database;
  final String snapshot;
  final String _schemaPath;
  final String _outputPath;
}

/// Resolves one annotated Dart library and emits its typed client and frozen schema.
///
/// Values, constructor fields and selections are validated before any file write.
/// [schemaPath] and [outputPath] may be relative to the current directory.
Future<GeneratedSources> generateSchema({
  required String schemaPath,
  required String outputPath,
  String databaseName = 'AppDatabase',
  required Engine engine,
}) async {
  if (!RegExp(r'^[A-Z][a-zA-Z0-9_]*$').hasMatch(databaseName)) {
    throw const FormatException(
      'Database name must be a public Dart class identifier.',
    );
  }
  final input = p.normalize(p.absolute(schemaPath));
  final output = p.normalize(p.absolute(outputPath));
  await _validateOutputPaths(input, output);
  final model = await readSchema(input);
  _validateGeneratedNames(model, databaseName);
  final formatter = DartFormatter(
    languageVersion: DartFormatter.latestLanguageVersion,
  );
  final import = p
      .relative(input, from: p.dirname(output))
      .split(p.separator)
      .join('/');
  return GeneratedSources._(
    database: formatter.format(
      emitDatabase(model, modelImport: import, databaseName: databaseName),
    ),
    snapshot: formatter.format(emitSnapshot(model, engine: engine)),
    schemaPath: input,
    outputPath: output,
  );
}

void _validateGeneratedNames(SchemaModel model, String databaseName) {
  // Every unqualified symbol used by emitted code shares this namespace.
  final names = {
    'Future',
    'List',
    'Map',
    'Object',
    'String',
    'int',
    'double',
    'bool',
    'DateTime',
    'Stream',
    'ArgumentError',
    'models',
    'identical',
    'openDatabase',
    'decodeValue',
    'Database',
    'Session',
    'Driver',
    'DatabaseObserver',
    'Isolation',
    'Engine',
    'Capabilities',
    'QueryResult',
    'TableQuery',
    'Filter',
    'Direction',
    'ScalarType',
    'TableDefinition',
    'ColumnDefinition',
    'ForeignKey',
    'Uint8List',
    '_absent',
  };
  final sessionName =
      '${databaseName.endsWith('Database') ? databaseName.substring(0, databaseName.length - 8) : databaseName}Session';
  final generated = [databaseName, sessionName];
  for (final table in model.tables) {
    generated.addAll([table.definitionName, '_decode${table.dartName}']);
    final suffixes = [
      'Table',
      'Create',
      'Update',
      if (table.uniqueFields.isNotEmpty) ...['Unique', 'CreateIfAbsent'],
      if (table.numericFields.isNotEmpty) ...['Increment', 'Decrement'],
    ];
    for (final suffix in suffixes) {
      final name = '${table.dartName}$suffix';
      generated.add(name);
      if (suffix != 'Table' && suffix != 'Unique') generated.add('_$name');
    }
  }
  for (final name in generated) {
    if (!names.add(name)) {
      throw FormatException(
        'Generated symbol $name conflicts with another generated or runtime declaration.',
      );
    }
  }
}

/// The independent frozen Dart file associated with a generated client.
String snapshotPath(String databasePath) {
  if (databasePath.endsWith('.db.dart')) {
    return '${databasePath.substring(0, databasePath.length - 8)}.snapshot.dart';
  }
  return '${p.withoutExtension(databasePath)}.snapshot.dart';
}

/// Writes both outputs, or checks exact source equality without writing.
///
/// Returns false for missing or changed files when [check] is true. Schema
/// validation and formatter failures propagate without changing either file.
/// Output paths must match those used for generation so relative model imports
/// remain valid. Symbolic links and aliases of the input or sibling output are
/// rejected. Both contents are staged before replacing either destination;
/// replacement of each file is atomic, not a transaction across both files.
Future<bool> writeGeneratedSources({
  required GeneratedSources sources,
  required String outputPath,
  bool check = false,
}) async {
  final output = p.normalize(p.absolute(outputPath));
  if (output != sources._outputPath) {
    throw const FormatException(
      'Write to the output path used for generation.',
    );
  }
  await _validateOutputPaths(sources._schemaPath, output);
  final files = {
    output: sources.database,
    snapshotPath(output): sources.snapshot,
  };
  if (check) {
    for (final entry in files.entries) {
      final file = File(entry.key);
      if (!await file.exists() || await file.readAsString() != entry.value) {
        return false;
      }
    }
    return true;
  }
  final staged = <({File file, String target, Directory directory})>[];
  try {
    for (final entry in files.entries) {
      final parent = Directory(p.dirname(entry.key));
      await parent.create(recursive: true);
      final directory = await parent.createTemp('.orm-generate-');
      final file = File(p.join(directory.path, p.basename(entry.key)));
      staged.add((file: file, target: entry.key, directory: directory));
      await file.writeAsString(entry.value, flush: true);
    }
    await _validateOutputPaths(sources._schemaPath, output);
    for (final entry in staged) {
      await entry.file.rename(entry.target);
    }
  } finally {
    for (final entry in staged) {
      await entry.directory.delete(recursive: true);
    }
  }
  return true;
}

Future<void> _validateOutputPaths(String input, String output) async {
  final outputs = [output, snapshotPath(output)];
  for (final path in outputs) {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw FormatException(
        'Generated output must be a regular file, not a directory or symbolic link: $path',
      );
    }
    if (await _pathsAlias(input, path)) {
      throw const FormatException(
        'Generated output cannot overwrite the schema input.',
      );
    }
  }
  if (await _pathsAlias(outputs[0], outputs[1])) {
    throw const FormatException(
      'Generated database and snapshot must be distinct files.',
    );
  }
}

Future<bool> _pathsAlias(String left, String right) async {
  if (p.equals(await _resolvedPath(left), await _resolvedPath(right))) {
    return true;
  }
  // Resolving symbolic links does not detect hard links to the same inode.
  return await File(left).exists() &&
      await File(right).exists() &&
      await FileSystemEntity.identical(left, right);
}

Future<String> _resolvedPath(String path) async {
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    return p.normalize(await File(path).resolveSymbolicLinks());
  }
  return p.join(await _resolvedPath(p.dirname(path)), p.basename(path));
}
