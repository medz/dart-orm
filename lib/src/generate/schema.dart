import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dart_style/dart_style.dart';
import 'package:path/path.dart' as p;

import '../../migrate.dart';
import 'emitter.dart';
import 'exception.dart';
import 'schema/layout.dart';
import 'schema/reader.dart';
import 'schema/sources.dart';
import 'source.dart';
import 'types.dart';

/// A generated typed client and the physical schema derived from its models.
///
/// Generation does not open a database or apply a migration. Review schema
/// changes through the migration workflow before applying them.
final class GeneratedSchema {
  /// Formatted Dart source for the generated query client.
  final String dart;

  /// Physical tables, keys and constraints captured from the declaration.
  final SchemaSnapshot snapshot;

  /// Combines generated [dart] source with its physical [snapshot].
  const GeneratedSchema(this.dart, this.snapshot);

  /// Standalone Dart source for [snapshot], independent of current model types.
  String get snapshotDart => formatMigration(schemaSource(snapshot));
}

/// Analyzes one file or a definition directory without writing files.
///
/// [dialect] selects the directory layout and physical namespace rules. PostgreSQL
/// uses `{root}/{schema}/*.dart`; other engines use `{root}/*.dart`. A sibling
/// `{root}.dart` contributes to the default namespace. Discovery is not recursive.
/// PostgreSQL generation records `public` explicitly for default models.
/// Single-file generation without a dialect retains engine-neutral metadata.
///
/// [outputPath] determines relative imports and defaults to the source basename
/// with an `.orm.dart` extension. Invalid declarations or output collisions throw
/// [GenerationException]. Application default factories are never executed.
Future<GeneratedSchema> generateSchema(
  String sourcePath, {
  String? outputPath,
  SqlDialect? dialect,
}) async {
  final input = p.normalize(p.absolute(sourcePath));
  final root = SchemaLayout.stem(input);
  final layout = SchemaLayout(
    input,
    dialect: dialect,
    directory: await Directory(root).exists(),
  );
  final output = p.normalize(p.absolute(outputPath ?? layout.output));
  final sources = <String>[];
  if (await File(layout.file).exists()) sources.add(layout.file);
  if (layout.directory) {
    await for (final entry in Directory(root).list(followLinks: false)) {
      if (entry is File && SchemaLayout.declaration(entry.path)) {
        if (dialect == SqlDialect.postgres) {
          throw GenerationException(
            'Put PostgreSQL declarations in $root/{schema}/*.dart: ${entry.path}',
          );
        }
        sources.add(entry.path);
      } else if (entry is Directory && dialect == SqlDialect.postgres) {
        await for (final file in entry.list(followLinks: false)) {
          if (file is File && SchemaLayout.declaration(file.path)) {
            sources.add(file.path);
          }
        }
      }
    }
    sources.sort();
  }
  if (sources.isEmpty) {
    throw GenerationException('No schema files found for $sourcePath.');
  }
  if (p.extension(output) != '.dart' ||
      sources.contains(output) ||
      sources.contains(_schemaSnapshotPath(output))) {
    throw const GenerationException(
      'Client and snapshot outputs must be separate Dart files from the source.',
    );
  }
  final contexts = AnalysisContextCollection(includedPaths: [p.dirname(root)]);
  try {
    Future<ResolvedUnitResult> resolvePath(String path) async {
      final result = await contexts
          .contextFor(path)
          .currentSession
          .getResolvedUnit(path);
      if (result is! ResolvedUnitResult) {
        throw GenerationException('Cannot analyze $path.');
      }
      final errors = result.diagnostics.where(
        (e) => e.severity.name.toLowerCase() == 'error',
      );
      if (errors.isNotEmpty) throw GenerationException(errors.join('\n'));
      return result;
    }

    final roots = <ResolvedUnitResult>[];
    for (final path in sources) {
      roots.add(await resolvePath(path));
    }
    String importPath(Uri uri) => uri.scheme == 'file'
        ? p
              .relative(uri.toFilePath(), from: p.dirname(output))
              .replaceAll(r'\', '/')
        : uri.toString();
    final resolved = roots.first;
    return await generateResolvedSchema(
      resolved.unit,
      resolved.libraryElement,
      importPath(Uri.file(sources.first)),
      importPath,
      resolve: (library) async =>
          (await resolvePath(library.firstFragment.source.fullName)).unit,
      additionalRoots: [for (final result in roots.skip(1)) result.unit],
      namespaceOf: (variable) => layout.namespace(
        variable
            .declaredFragment!
            .element
            .library!
            .firstFragment
            .source
            .fullName,
      ),
      stableOrder: layout.directory || dialect != null,
      dialect: dialect,
    );
  } finally {
    await contexts.dispose();
  }
}

Future<GeneratedSchema> generateResolvedSchema(
  CompilationUnit unit,
  LibraryElement library,
  String sourceImport,
  String Function(Uri) importUri, {
  required Future<CompilationUnit> Function(LibraryElement) resolve,
  List<CompilationUnit> additionalRoots = const [],
  String? Function(VariableDeclaration)? namespaceOf,
  bool stableOrder = false,
  SqlDialect? dialect,
}) async {
  final names = DartNames(library.uri, importUri);
  final schema = SchemaReader(
    unit,
    library.typeSystem,
    names,
    await schemaSources(
      unit,
      library,
      resolve,
      additionalRoots: additionalRoots,
    ),
    namespaceOf: namespaceOf,
    additionalRoots: additionalRoots,
    stableOrder: stableOrder,
  ).read();
  final snapshot = SchemaSnapshot([
    for (final table in schema) table.snapshot(),
  ]);
  return GeneratedSchema(
    DartFormatter(languageVersion: library.languageVersion.effective)
        .format(emitSchema(schema, sourceImport, names)),
    dialect == null ? snapshot : snapshot.forDialect(dialect),
  );
}

/// Writes a typed client and Dart schema snapshot after validating [source].
///
/// [output] defaults to the source basename with an `.orm.dart` extension.
/// The snapshot uses the corresponding `.snapshot.dart` basename. Both are
/// derived files and are replaced when generation succeeds.
Future<void> writeGeneratedSchema(
  String source, {
  String? output,
  SqlDialect? dialect,
}) async {
  output ??= '${SchemaLayout.stem(source)}.orm.dart';
  final result = await generateSchema(
    source,
    outputPath: output,
    dialect: dialect,
  );
  final file = File(output);
  await file.parent.create(recursive: true);
  final snapshot = result.snapshotDart;
  await file.writeAsString(result.dart);
  await File(_schemaSnapshotPath(output)).writeAsString(snapshot);
}

String _schemaSnapshotPath(String output) => output.endsWith('.orm.dart')
    ? '${output.substring(0, output.length - '.orm.dart'.length)}.snapshot.dart'
    : p.setExtension(output, '.snapshot.dart');
