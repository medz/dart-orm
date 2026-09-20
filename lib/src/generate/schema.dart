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
import 'reader.dart';
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

/// Analyzes [sourcePath] and generates a client without writing files.
///
/// [outputPath] determines relative imports and defaults to the source basename
/// with an `.orm.dart` extension. Invalid declarations or output collisions throw
/// [GenerationException]. Application default factories are never executed.
Future<GeneratedSchema> generateSchema(
  String sourcePath, {
  String? outputPath,
}) async {
  final source = p.normalize(p.absolute(sourcePath));
  final output = p.normalize(
    p.absolute(outputPath ?? p.setExtension(source, '.orm.dart')),
  );
  if (p.extension(output) != '.dart' ||
      source == output ||
      source == _schemaSnapshotPath(output)) {
    throw const GenerationException(
      'Client and snapshot outputs must be separate Dart files from the source.',
    );
  }
  final contexts = AnalysisContextCollection(includedPaths: [source]);
  try {
    final resolved = await contexts
        .contextFor(source)
        .currentSession
        .getResolvedUnit(source);
    if (resolved is! ResolvedUnitResult) {
      throw GenerationException('Cannot analyze $source.');
    }
    final errors = resolved.diagnostics.where(
      (e) => e.severity.name.toLowerCase() == 'error',
    );
    if (errors.isNotEmpty) {
      throw GenerationException(errors.map((e) => e.toString()).join('\n'));
    }
    final import = p
        .relative(source, from: p.dirname(output))
        .replaceAll(r'\', '/');
    return generateResolvedSchema(
      resolved.unit,
      resolved.libraryElement,
      import,
      (uri) => uri.scheme == 'file'
          ? p
                .relative(uri.toFilePath(), from: p.dirname(output))
                .replaceAll(r'\', '/')
          : uri.toString(),
    );
  } finally {
    await contexts.dispose();
  }
}

GeneratedSchema generateResolvedSchema(
  CompilationUnit unit,
  LibraryElement library,
  String sourceImport,
  String Function(Uri) importUri,
) {
  final names = DartNames(library.uri, importUri);
  final schema = SchemaReader(unit, library.typeSystem, names).read();
  return GeneratedSchema(
    DartFormatter(languageVersion: library.languageVersion.effective)
        .format(emitSchema(schema, sourceImport, names)),
    SchemaSnapshot([for (final table in schema) table.snapshot()]),
  );
}

/// Writes a typed client and Dart schema snapshot after validating [source].
///
/// [output] defaults to the source basename with an `.orm.dart` extension.
/// The snapshot uses the corresponding `.snapshot.dart` basename. Both are
/// derived files and are replaced when generation succeeds.
Future<void> writeGeneratedSchema(String source, {String? output}) async {
  output ??= p.setExtension(source, '.orm.dart');
  final result = await generateSchema(source, outputPath: output);
  final file = File(output);
  await file.parent.create(recursive: true);
  final snapshot = result.snapshotDart;
  await file.writeAsString(result.dart);
  await File(_schemaSnapshotPath(output)).writeAsString(snapshot);
}

String _schemaSnapshotPath(String output) => output.endsWith('.orm.dart')
    ? '${output.substring(0, output.length - '.orm.dart'.length)}.snapshot.dart'
    : p.setExtension(output, '.snapshot.dart');
