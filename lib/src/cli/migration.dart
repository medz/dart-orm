import 'dart:async';
import 'dart:io';

import '../../generate.dart';
import '../../migrate.dart';
import '../../runtime.dart';
import 'output.dart';

/// Opens a runtime owned and closed by one migration CLI invocation.
///
/// The factory must honor [readOnly] when requested and connect to the engine
/// declared by the migration history. Do not return a shared application runtime.
typedef MigrationConnection = FutureOr<SqlDatabase<Backend>> Function({
  required bool readOnly,
});

/// Runs commands against a project's statically imported migration [history].
///
/// Offline commands never call [connect]. Database commands close the returned
/// runtime when finished. [json] selects machine-readable reports; saved schema
/// and migration files remain Dart source. Errors are written to stderr and set
/// the process exit code: 64 for usage errors, 2 for drift, or 1 for failure.
Future<void> runMigrationCli(
  List<String> arguments, {
  required MigrationHistory history,
  required String directory,
  SchemaSnapshot? schema,
  MigrationConnection? connect,
  SchemaRenames renames = const SchemaRenames(),
  Map<String, Map<String, String>> using = const {},
  bool json = true,
}) async {
  exitCode = await runMigrationCommand(
    arguments,
    history: history,
    directory: directory,
    schema: schema,
    connect: connect,
    renames: renames,
    using: using,
    json: json,
  );
}

Future<int> runMigrationCommand(
  List<String> arguments, {
  required MigrationHistory history,
  required String directory,
  SchemaSnapshot? schema,
  MigrationConnection? connect,
  SchemaRenames renames = const SchemaRenames(),
  Map<String, Map<String, String>> using = const {},
  bool json = true,
}) async {
  final output = CliOutput(json);
  final report = output.report;

  try {
    if (arguments.isEmpty || arguments.singleOrNull == '--help') {
      stdout.writeln('''Migration commands:
  create <id> [--allow-destructive]
  record <id>                     Record a reviewed, unpublished edit
  check
  plan
  apply [--max-backfill-batches <count>]
  status
  verify
  baseline
  inspect <table>
Connection, target schema, renames and conversions belong in the Dart entrypoint.
Rebuild static imports with: dart run orm migration registry <directory>''');
      return 0;
    }
    final command = arguments.first;
    final rest = arguments.skip(1).toList();
    final expected =
        command == 'create' || command == 'record' || command == 'inspect'
        ? 1
        : 0;
    var destructive = false;
    int? batches;
    if (command == 'create' && rest.lastOrNull == '--allow-destructive') {
      destructive = true;
      rest.removeLast();
    }
    if (command == 'apply' &&
        rest.length == 2 &&
        rest.first == '--max-backfill-batches') {
      batches = int.tryParse(rest.last);
      if (batches == null || batches < 1) {
        throw const FormatException('Use a positive batch count.');
      }
      rest.clear();
    }
    if (!{
          'create',
          'record',
          'check',
          'plan',
          'apply',
          'status',
          'verify',
          'baseline',
          'inspect',
        }.contains(command) ||
        rest.length != expected ||
        rest.any((value) => value.startsWith('--'))) {
      throw const FormatException('Invalid migration command. Use --help.');
    }
    if (command == 'record') {
      final checksum = await recordMigration(
        rest.single,
        directory: directory,
        history: history,
      );
      report({'recorded': rest.single, 'checksum': checksum});
      return 0;
    }
    final migrations = history.checked;
    if (command == 'check') {
      report({
        'valid': true,
        'dialect': history.dialect.name,
        'migrations': migrations.map((m) => m.id).toList(),
      });
      return 0;
    }
    if (command == 'create') {
      if (schema == null) {
        throw const FormatException(
          'Provide the target schema in the Dart entrypoint.',
        );
      }
      final previous = migrations.lastOrNull;
      if (previous != null && previous.snapshot == null) {
        throw const FormatException(
          'The previous migration needs a historical schema.',
        );
      }
      final change = Migration.diff(
        rest.single,
        dialect: history.dialect,
        from: previous?.snapshot ?? SchemaSnapshot([]),
        to: schema,
        previous: previous?.checksum,
        renames: renames,
        using: using,
        allowDestructive: destructive,
      );
      if (change.steps.isEmpty) {
        report({'created': null, 'reason': 'Schema is unchanged.'});
      } else {
        final path = await writeMigration(
          change,
          directory: directory,
          history: history,
        );
        report({'created': path, 'checksum': change.checksum});
      }
      return 0;
    }
    if (command == 'verify' && schema == null) {
      throw const FormatException(
        'Provide the expected schema in the Dart entrypoint.',
      );
    }
    if (command == 'baseline' &&
        (migrations.isEmpty || migrations.last.snapshot == null)) {
      throw const FormatException(
        'Baseline requires a final historical schema.',
      );
    }
    if (connect == null) {
      throw const FormatException('Provide a database connection factory.');
    }
    final db = await connect(
      readOnly: !{'apply', 'baseline'}.contains(command),
    );
    try {
      if (db.dialect != history.dialect) {
        throw OrmException(
          'MIGRATION.TARGET',
          'History targets ${history.dialect.name}, connection is ${db.dialect.name}.',
        );
      }
      final migrator = Migrator(db);
      switch (command) {
        case 'plan':
          final pending = await migrator.plan(migrations);
          report({
            'atomic': !pending.any(
              (m) => m.steps.any(
                (s) => s is CheckedSql || s is CheckedTableSql || s is Backfill,
              ),
            ),
            'pending': [
              for (final m in pending)
                {
                  'id': m.id,
                  'checksum': m.checksum,
                  'steps': m.steps.map((s) => s.toJson()).toList(),
                },
            ],
            'progress': (await migrator.progress())
                .map((p) => p.toJson())
                .toList(),
          });
        case 'apply':
          final applied = await migrator.apply(
            migrations,
            maxBackfillBatches: batches,
          );
          report({
            'applied': applied,
            if (batches != null)
              'complete': (await migrator.plan(migrations)).isEmpty,
          });
        case 'status':
          report({
            'applied': [
              for (final m in await migrator.history())
                {'id': m.id, 'checksum': m.checksum},
            ],
            'progress': (await migrator.progress())
                .map((p) => p.toJson())
                .toList(),
          });
        case 'baseline' || 'verify':
          final result = command == 'baseline'
              ? await migrator.baseline(
                  migrations,
                  expected: migrations.last.snapshot!,
                )
              : await verifySchema(db, schema!);
          report({
            'matches': result.matches,
            'differences': result.differences,
            'unmanaged': [
              for (final o in result.unmanaged)
                {'kind': o.kind, 'name': o.name, 'definition': o.definition},
            ],
          });
          if (!result.matches) output.exitCode = 2;
        case 'inspect':
          final table = await inspectTable(db, rest.single);
          report({
            'table': table.name,
            'columns': [
              for (final c in table.columns)
                {
                  'name': c.name,
                  'storageType': c.storageType,
                  'nullable': c.nullable,
                  'default': c.defaultSql,
                  'generated': c.generated,
                  if (c.computed case final computed?)
                    'computed': {
                      'expression': computed.expression(db.dialect),
                      'storage': computed.storage.name,
                    },
                  if (c.integerBits != null) 'integerBits': c.integerBits,
                  if (c.decimalPrecision != null)
                    'decimalPrecision': c.decimalPrecision,
                  if (c.decimalPrecision != null)
                    'decimalScale': c.decimalScale ?? 0,
                  if (c.temporalPrecision != null)
                    'temporalPrecision': c.temporalPrecision,
                  if (c.collation != null) 'collation': c.collation,
                },
            ],
            'primaryKey': table.primaryKey,
            'uniqueKeys': table.uniqueKeys,
            'foreignKeys': [
              for (final k in table.foreignKeys)
                {
                  'columns': k.columns,
                  'target': k.target,
                  'targetColumns': k.targetColumns,
                  'onDelete': k.onDelete,
                },
            ],
            'indexes': [
              for (final i in table.indexes)
                {'name': i.name, 'columns': i.columns, 'unique': i.unique},
            ],
            'checks': [
              for (final check in table.checks)
                {'name': check.name, 'expression': check.expression},
            ],
            'unmanaged': [
              for (final o in table.unmanaged)
                {'kind': o.kind, 'name': o.name, 'definition': o.definition},
            ],
          });
      }
    } finally {
      await db.close();
    }
  } on FormatException catch (error) {
    output.error(error.message, 64);
  } on ArgumentError catch (_) {
    output.error('Invalid migration argument. Use --help.', 64);
  } catch (error) {
    output.error(error.toString(), 1);
  }
  return output.exitCode;
}
