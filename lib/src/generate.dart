/// Source analysis and deterministic client generation.
library;

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart' show Keyword;
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_system.dart';
import 'package:build/build.dart' as builder;
import 'package:dart_style/dart_style.dart';
import 'package:path/path.dart' as p;

import '../migrate.dart';
import '../orm.dart';

part 'generate/model.dart';
part 'generate/reader.dart';
part 'generate/types.dart';
part 'generate/emitter.dart';
part 'generate/build.dart';
part 'generate/import.dart';
part 'generate/queries.dart';
part 'generate/migrations.dart';

final class GenerationException implements Exception {
  final String message;
  const GenerationException(this.message);
  @override
  String toString() => 'GenerationException: $message';
}

final class GeneratedSchema {
  final String dart;
  final SchemaSnapshot snapshot;
  const GeneratedSchema(this.dart, this.snapshot);
  String get snapshotDart => _formatMigration(schemaSource(snapshot));
}

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
    return _generate(
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

GeneratedSchema _generate(
  CompilationUnit unit,
  LibraryElement library,
  String sourceImport,
  String Function(Uri) importUri,
) {
  final names = _DartNames(library.uri, importUri);
  final schema = _SchemaReader(unit, library.typeSystem, names).read();
  return GeneratedSchema(
    DartFormatter(languageVersion: library.languageVersion.effective)
        .format(_emit(schema, sourceImport, names)),
    SchemaSnapshot([for (final table in schema) table.snapshot()]),
  );
}

/// Writes generated output only after source analysis and schema validation.
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
