import 'dart:io';

import 'package:dart_style/dart_style.dart';
import 'package:orm/database.dart' show Engine;
import 'package:path/path.dart' as p;

import 'emit.dart';
import 'read_schema.dart';

/// Complete deterministic Dart outputs. The snapshot imports no application models.
final class GeneratedSources {
  const GeneratedSources({required this.database, required this.snapshot});
  final String database;
  final String snapshot;
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
  if (input == output || input == snapshotPath(output)) {
    throw const FormatException(
      'Generated output cannot overwrite the schema input.',
    );
  }
  final model = await readSchema(input);
  final sessionName =
      '${databaseName.endsWith('Database') ? databaseName.substring(0, databaseName.length - 8) : databaseName}Session';
  final generatedNames = {
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
    for (final table in model.tables)
      for (final suffix in [
        'Table',
        'Create',
        'Update',
        'Increment',
        'Decrement',
      ])
        '${table.dartName}$suffix',
  };
  if (databaseName == sessionName ||
      generatedNames.contains(databaseName) ||
      generatedNames.contains(sessionName)) {
    throw const FormatException(
      'Database name conflicts with a generated or runtime type.',
    );
  }
  final formatter = DartFormatter(
    languageVersion: DartFormatter.latestLanguageVersion,
  );
  final import = p
      .relative(input, from: p.dirname(output))
      .split(p.separator)
      .join('/');
  return GeneratedSources(
    database: formatter.format(
      emitDatabase(model, modelImport: import, databaseName: databaseName),
    ),
    snapshot: formatter.format(emitSnapshot(model, engine: engine)),
  );
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
Future<bool> writeGeneratedSources({
  required GeneratedSources sources,
  required String outputPath,
  bool check = false,
}) async {
  final output = p.normalize(p.absolute(outputPath));
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
  for (final entry in files.entries) {
    final file = File(entry.key);
    await file.parent.create(recursive: true);
    await file.writeAsString(entry.value);
  }
  return true;
}
