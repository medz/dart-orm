import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:dart_style/dart_style.dart';
import 'package:orm/database.dart' show Engine;
import 'package:orm/migration.dart';
import 'package:orm/schema.dart';
import 'package:path/path.dart' as p;

import 'emit.dart';

/// Saves a conservative schema change as a standalone Dart migration draft.
///
/// Review the saved SQL and fingerprint, then register it with a static import.
/// [before] must be the previous saved schema, never a reconstructed live model.
/// Omit it for the initial migration. Existing files are never overwritten.
/// Destructive or unsupported changes fail before any output is created.
/// Drafts support literal string, integer, real and boolean defaults.
Future<void> draftMigration({
  SchemaSnapshot? before,
  required SchemaSnapshot after,
  required int version,
  required String name,
  required String outputPath,
}) async {
  if (!outputPath.endsWith('.dart')) {
    throw const FormatException('Migration output must be a Dart file.');
  }
  final plan = planSchemaChange(
    before ?? SchemaSnapshot(engine: after.engine, tables: const []),
    after,
  );
  if (plan.steps.isEmpty) {
    throw StateError('The schema has no storage changes to draft.');
  }
  for (final table in plan.snapshot.tables) {
    for (final column in table.columns) {
      final value = column.defaultValue;
      if (value != null &&
          value is! String &&
          value is! num &&
          value is! bool) {
        throw FormatException(
          '${table.name}.${column.name}: draft defaults must be scalar literals.',
        );
      }
    }
  }
  final fingerprint = migrationFingerprint(
    version: version,
    name: name,
    engine: plan.engine,
    steps: plan.steps,
    snapshot: plan.snapshot,
  );
  // Use the same validation as a saved definition before creating its file.
  Migration(
    version: version,
    name: name,
    engine: plan.engine,
    steps: plan.steps,
    snapshot: plan.snapshot,
    reviewedFingerprint: fingerprint,
  );
  final source =
      DartFormatter(languageVersion: DartFormatter.latestLanguageVersion)
          .format('''
// Migration draft: review every SQL statement before committing this file.
// After application, preserve this history and add a new migration for changes.
import 'package:orm/database.dart';
import 'package:orm/migration.dart';
import 'package:orm/schema.dart';

const frozenSchema = SchemaSnapshot(
  engine: Engine.${plan.engine.name},
  tables: [${plan.snapshot.tables.map(emitTableDefinition).join(',')}],
);

final migration = Migration(
  version: $version,
  name: ${dartLiteral(name)},
  engine: Engine.${plan.engine.name},
  steps: [${plan.steps.map(dartLiteral).join(',')}],
  snapshot: frozenSchema,
  reviewedFingerprint: ${dartLiteral(fingerprint)},
);
''');
  final output = File(p.normalize(p.absolute(outputPath)));
  await output.parent.create(recursive: true);
  await output.create(exclusive: true);
  try {
    await output.writeAsString(source, flush: true);
  } catch (_) {
    await output.delete();
    rethrow;
  }
}

/// Reads a constant frozen schema without executing the Dart input file.
///
/// Accepts the generated `frozenSchema` or one unambiguous top-level constant
/// [SchemaSnapshot], including a private constant in a historical migration.
/// The file must be an independent library. Only literal scalar defaults are
/// supported, matching the model generator; application code is never loaded.
Future<SchemaSnapshot> readSnapshot(String sourcePath) async {
  final file = p.normalize(p.absolute(sourcePath));
  final collection = AnalysisContextCollection(
    includedPaths: [file],
    sdkPath: p.dirname(p.dirname(Platform.resolvedExecutable)),
  );
  try {
    final result = await collection
        .contextFor(file)
        .currentSession
        .getResolvedLibrary(file);
    if (result is! ResolvedLibraryResult || result.units.length != 1) {
      throw FormatException('$file: expected one independent Dart library.');
    }
    final errors = result.units.single.diagnostics.where(
      (error) => error.severity.name == 'error',
    );
    if (errors.isNotEmpty) {
      throw FormatException('$file: ${errors.join('\n')}');
    }
    final snapshots = result.element.topLevelVariables
        .where((variable) => variable.isConst)
        .map((variable) => variable.computeConstantValue())
        .whereType<DartObject>()
        .where((value) => _isSchemaType(value, 'SchemaSnapshot'))
        .toList();
    final preferred = snapshots.where(
      (value) => value.variable?.name == 'frozenSchema',
    );
    final snapshot = preferred.singleOrNull ?? snapshots.singleOrNull;
    if (snapshot == null) {
      throw FormatException(
        '$file: declare const frozenSchema, or exactly one const SchemaSnapshot.',
      );
    }
    final schema = SchemaSnapshot(
      engine: Engine.values[_enumIndex(_field(snapshot, 'engine'))],
      tables: [
        for (final table in _field(snapshot, 'tables').toListValue()!)
          TableDefinition(_field(table, 'name').toStringValue()!, [
            for (final column in _field(table, 'columns').toListValue()!)
              ColumnDefinition(
                name: _field(column, 'name').toStringValue()!,
                field: _field(column, 'field').toStringValue()!,
                type: ScalarType.values[_enumIndex(_field(column, 'type'))],
                nullable: _field(column, 'nullable').toBoolValue()!,
                primaryKey: _field(column, 'primaryKey').toBoolValue()!,
                identity: _field(column, 'identity').toBoolValue()!,
                unique: _field(column, 'unique').toBoolValue()!,
                defaultValue: _literalDefault(_field(column, 'defaultValue')),
                references: _reference(_field(column, 'references')),
              ),
          ]),
      ],
    );
    // Validates cross-table constraints and freezes the analyzed collections.
    return MigrationPlan(
      engine: schema.engine,
      steps: const [],
      snapshot: schema,
    ).snapshot;
  } finally {
    await collection.dispose();
  }
}

bool _isSchemaType(DartObject value, String name) =>
    value.type?.element?.name == name &&
    value.type?.element?.library?.uri.toString() ==
        'package:orm/src/schema/definition.dart';

// Constant aliases change variable names, while retaining the actual enum value.
int _enumIndex(DartObject value) => _field(value, 'index').toIntValue()!;

DartObject _field(DartObject value, String name) {
  final field = value.getField(name);
  if (field == null || !field.hasKnownValue) {
    throw FormatException(
      'Snapshot field $name must have a known constant value.',
    );
  }
  return field;
}

Object? _literalDefault(DartObject value) {
  if (value.isNull) return null;
  final literal =
      value.toStringValue() ??
      value.toIntValue() ??
      value.toDoubleValue() ??
      value.toBoolValue();
  if (literal == null) {
    throw const FormatException('Snapshot defaults must be scalar literals.');
  }
  return literal;
}

ForeignKey? _reference(DartObject value) => value.isNull
    ? null
    : ForeignKey(
        _field(value, 'table').toStringValue()!,
        _field(value, 'column').toStringValue()!,
        onDelete: _field(value, 'onDelete').toStringValue()!,
      );
