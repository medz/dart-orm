// Research probe: Dart history objects, with no schema/migration JSON files.
// This uses today's API; it is not the proposed generation/CLI implementation.
import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';

final _v1 = SchemaSnapshot([
  TableSchema(
    'people',
    columns: [Column('id', Codecs.integer), Column('name', Codecs.text)],
    primaryKey: ['id'],
  ),
]);
final _v2 = SchemaSnapshot([
  TableSchema(
    'people',
    columns: [
      Column('id', Codecs.integer),
      Column('name', Codecs.text),
      Column('nickname', Codecs.text.nullable(), nullable: true),
    ],
    primaryKey: ['id'],
  ),
]);

// SQL is frozen here, instead of re-running Migration.diff/create at startup.
final _initial = Migration.steps('0001_people', {
  .sqlite: [
    ExecuteSql(
      'CREATE TABLE "people" ("id" INTEGER NOT NULL PRIMARY KEY, "name" TEXT NOT NULL)',
    ),
  ],
  .postgres: [
    ExecuteSql(
      'CREATE TABLE "people" ("id" BIGINT NOT NULL PRIMARY KEY, "name" TEXT NOT NULL)',
    ),
  ],
}, snapshot: _v1);

final _names = Migration.steps(
  '0002_nicknames',
  {
    for (final dialect in SqlDialect.values)
      dialect: [
        ExecuteSql('ALTER TABLE "people" ADD COLUMN "nickname" TEXT'),
        Backfill(
          _v2.tables.single,
          set: {'nickname': 'upper(name)'},
          where: 'nickname IS NULL',
          doneWhen:
              'SELECT NOT EXISTS(SELECT 1 FROM people WHERE nickname IS NULL)',
          batchSize: 1,
        ),
      ],
  },
  snapshot: _v2,
  // Fixed at migration creation time; never recompute this from a changed file.
  previous: 'e791fda7ae221bfaa8db941e250e44b59ca68822e64eb9ba84c8f70de9794373',
);
final _history = [_initial, _names];

Future<void> _exercise(Future<Database<Backend>> Function() connect) async {
  var db = await connect();
  var checks = 0;
  void check(bool value, String label) {
    if (!value) throw StateError(label);
    checks++;
    stdout.writeln('${db.dialect.name}: $label');
  }

  try {
    await Migrator(db).apply([_initial]);
    check((await verifySchema(db, _v1)).matches, 'Initial historical schema');
    await db.execute(
      SqlCommand("INSERT INTO people(id, name) VALUES (1, 'ada'), (2, 'lin')"),
    );
    check(
      (await Migrator(db).plan(_history)).single.id == _names.id,
      'Upgrade plan',
    );
    await Migrator(db).apply(_history, maxBackfillBatches: 1);
    check(
      (await Migrator(db).plan(_history)).single.id == _names.id,
      'Bounded backfill remains pending',
    );
    await db.close();
    db = await connect();
    await Migrator(db).apply(_history);
    final rows = (await db.execute(
      SqlCommand('SELECT id, nickname FROM people ORDER BY id'),
    )).rows;
    check(
      rows.length == 2 && rows[0][1] == 'ADA' && rows[1][1] == 'LIN',
      'Reopened migration resumes and preserves data',
    );
    check((await verifySchema(db, _v2)).matches, 'Final historical schema');
    check(
      (await Migrator(db).requireVersion(_history)).id == _names.id,
      'Application version',
    );
    check(
      (await Migrator(db).apply(_history)).isEmpty,
      'Completed history is not replayed',
    );
    final changed = Migration.steps(
      _names.id,
      {
        for (final entry in _names.steps.entries)
          entry.key: [...entry.value, ExecuteSql('SELECT 1')],
      },
      snapshot: _v2,
      previous: _names.previous,
    );
    var rejected = false;
    try {
      await Migrator(db).plan([_initial, changed]);
    } on OrmException catch (error) {
      rejected = error.code == 'MIGRATION.CHECKSUM';
    }
    check(rejected, 'Changed applied Dart plan is rejected');
    stdout.writeln('${db.dialect.name}: $checks checks passed');
  } finally {
    await db.close();
  }
}

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == '--fingerprint') {
    stdout.writeln(_initial.checksum);
    return;
  }
  if (arguments.isNotEmpty) {
    throw ArgumentError('Use no arguments or --fingerprint.');
  }
  final directory = await Directory.systemTemp.createTemp(
    'orm_dart_migrations_',
  );
  try {
    await _exercise(
      () => sqlite(SqliteOptions.file('${directory.path}/database.sqlite')),
    );
  } finally {
    await directory.delete(recursive: true);
  }

  final url = Platform.environment['ORM_TEST_POSTGRES'];
  if (url == null) return;
  final schema =
      'orm_dart_probe_${pid}_${DateTime.now().microsecondsSinceEpoch}';
  final admin = postgres(PostgresOptions(url: Uri.parse(url), tls: .disable));
  var created = false;
  try {
    await admin.execute(SqlCommand('CREATE SCHEMA "$schema"'));
    created = true;
    await _exercise(
      () async => postgres(
        PostgresOptions(url: Uri.parse(url), tls: .disable, schema: schema),
      ),
    );
  } finally {
    try {
      if (created) {
        await admin.execute(SqlCommand('DROP SCHEMA "$schema" CASCADE'));
      }
    } finally {
      await admin.close();
    }
  }
}
