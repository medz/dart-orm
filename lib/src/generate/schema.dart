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
import 'schema/annotations.dart';
import 'schema/layout.dart';
import 'schema/diagnostics.dart';
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
/// Directories are discovered recursively and their names never determine
/// physical namespaces. An annotation's explicit namespace overrides
/// [defaultNamespace], then PostgreSQL defaults to `public`. Other engines reject
/// explicit namespaces. A model source must not import generated clients.
/// Selected roots and libraries owning models found through exports or relations
/// must have neither `part` nor `part of` directives, matching build_runner.
/// A sibling `{root}.dart` can contribute models or exports. Single-file
/// generation without a dialect retains engine-neutral metadata.
///
/// [outputPath] determines relative imports and defaults to the source basename
/// with an `.orm.dart` extension. Invalid declarations or output collisions throw
/// [GenerationException]. Directory outputs must not be discovered as schema
/// inputs on later runs. Application default factories are never executed.
Future<GeneratedSchema> generateSchema(
  String sourcePath, {
  String? outputPath,
  SqlDialect? dialect,
  String? defaultNamespace,
}) async {
  final input = p.normalize(p.absolute(sourcePath));
  final root = SchemaLayout.stem(input);
  final layout = SchemaLayout(input, directory: await Directory(root).exists());
  final output = p.normalize(p.absolute(outputPath ?? layout.output));
  if (layout.directory &&
      SchemaLayout.declaration(output) &&
      (layout.includes(output) || p.dirname(output) == root)) {
    throw const GenerationException(
      'Generated outputs must not become schema inputs. '
      'Choose a path outside the schema layout or use an .orm.dart filename.',
    );
  }
  final sources = <String>[];
  if (await File(layout.file).exists()) sources.add(layout.file);
  if (layout.directory) {
    await for (final entry in Directory(
      root,
    ).list(followLinks: false, recursive: true)) {
      if (entry is File && SchemaLayout.declaration(entry.path)) {
        sources.add(entry.path);
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
      validateModelLibrary(result.unit, source: Uri.file(path));
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
      importPath,
      resolve: (library) async =>
          (await resolvePath(library.firstFragment.source.fullName)).unit,
      additionalRoots: [for (final result in roots.skip(1)) result.unit],
      dialect: dialect,
      defaultNamespace: defaultNamespace,
    );
  } finally {
    await contexts.dispose();
  }
}

Future<GeneratedSchema> generateResolvedSchema(
  CompilationUnit unit,
  LibraryElement library,
  String Function(Uri) importUri, {
  required Future<CompilationUnit> Function(LibraryElement) resolve,
  List<CompilationUnit> additionalRoots = const [],
  SqlDialect? dialect,
  String? defaultNamespace,
}) async {
  final names = DartNames(library.uri, importUri);
  final classes = await annotatedSources([unit, ...additionalRoots], resolve);
  if (classes.isEmpty) {
    throw const GenerationException('No @Model class declarations found.');
  }
  for (final declaration in classes) {
    final visited = <LibraryElement>{};
    void checkDependencies(LibraryElement owner) {
      if (!visited.add(owner)) return;
      for (final dependency in [
        ...owner.exportedLibraries,
        for (final fragment in owner.fragments) ...fragment.importedLibraries,
      ]) {
        final path = dependency.firstFragment.source.fullName;
        if (path.endsWith('.orm.dart') || path.endsWith('.snapshot.dart')) {
          failAt(
            declaration,
            'DEPENDENCY',
            'Model sources must not depend on generated clients or snapshots: ${dependency.uri}.',
          );
        }
        checkDependencies(dependency);
      }
    }

    checkDependencies(declaration.declaredFragment!.element.library);
  }
  final schema = AnnotationReader(
    classes,
    names,
    dialect: dialect,
    defaultNamespace: defaultNamespace,
  ).read();
  final snapshot = SchemaSnapshot([
    for (final table in schema) table.snapshot(),
  ]);
  return GeneratedSchema(
    DartFormatter(languageVersion: library.languageVersion.effective)
        .format(emitSchema(schema, names)),
    dialect == null ? snapshot : snapshot.forDialect(dialect),
  );
}

/// Writes a typed client and Dart schema snapshot after validating [source].
///
/// [output] defaults to the source basename with an `.orm.dart` extension.
/// The snapshot uses the corresponding `.snapshot.dart` basename. Both are
/// derived files and are replaced when generation succeeds. [defaultNamespace]
/// follows [generateSchema]'s namespace resolution rules.
Future<void> writeGeneratedSchema(
  String source, {
  String? output,
  SqlDialect? dialect,
  String? defaultNamespace,
}) async {
  output ??= '${SchemaLayout.stem(source)}.orm.dart';
  final result = await generateSchema(
    source,
    outputPath: output,
    dialect: dialect,
    defaultNamespace: defaultNamespace,
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
