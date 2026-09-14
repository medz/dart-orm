/// Source analysis and deterministic client generation.
library;

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_system.dart';
import 'package:path/path.dart' as p;

part 'src/generate/model.dart';
part 'src/generate/reader.dart';
part 'src/generate/types.dart';
part 'src/generate/emitter.dart';

final class GenerationException implements Exception {
  final String message;
  const GenerationException(this.message);
  @override
  String toString() => 'GenerationException: $message';
}

final class GeneratedSchema {
  final String dart;
  final Map<String, Object?> snapshot;
  const GeneratedSchema(this.dart, this.snapshot);
}

Future<GeneratedSchema> generateSchema(
  String sourcePath, {
  String? outputPath,
}) async {
  final source = p.normalize(p.absolute(sourcePath));
  final output = p.normalize(
    p.absolute(outputPath ?? p.setExtension(source, '.orm.dart')),
  );
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
    final names = _DartNames(resolved.libraryElement.uri, output);
    final schema = _SchemaReader(
      resolved.unit,
      resolved.typeSystem,
      names,
    ).read();
    final import = p
        .relative(source, from: p.dirname(output))
        .replaceAll(r'\', '/');
    return GeneratedSchema(_emit(schema, import, names), {
      'format': 1,
      'tables': [for (final table in schema) table.snapshot()],
    });
  } finally {
    await contexts.dispose();
  }
}

/// Writes generated output only after source analysis and schema validation.
Future<void> writeGeneratedSchema(String source, {String? output}) async {
  output ??= p.setExtension(source, '.orm.dart');
  final result = await generateSchema(source, outputPath: output);
  final file = File(output);
  await file.parent.create(recursive: true);
  await file.writeAsString(result.dart);
  final formatted = await Process.run(Platform.resolvedExecutable, [
    'format',
    output,
  ]);
  if (formatted.exitCode != 0) {
    throw GenerationException(
      'Generated source failed formatting: ${formatted.stderr}',
    );
  }
  await File(p.setExtension(output, '.json')).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(result.snapshot)}\n',
  );
}
