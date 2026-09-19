import 'dart:io';

import 'package:orm/generate.dart';
import 'package:orm/migrate.dart';
import 'package:orm/migrate_cli.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

Matcher code(String value) =>
    isA<OrmException>().having((e) => e.code, 'code', value);

TableSchema scores({
  String other = 'id * 3',
  bool indexed = false,
  ComputedStorage storage = ComputedStorage.virtual,
  bool computed = true,
}) => TableSchema(
  'scores',
  columns: [
    Column('id', Codecs.integer),
    Column(
      'value',
      Codecs.integer,
      computed: computed
          ? ComputedColumn.forDialects(
              sqlite: 'id * 2',
              postgres: other,
              storage: storage,
            )
          : null,
    ),
  ],
  primaryKey: ['id'],
  indexes: indexed
      ? [
          const IndexSchema('value_index', ['value']),
        ]
      : [],
  checks: [
    CheckSchema.forDialects('positive', sqlite: 'id > 0', postgres: other),
  ],
);

void main() {
  test(
    'history requires a single engine even when empty or SQL is portable',
    () {
      final sqlite = Migration('0001_start', ['SELECT 1'], dialect: .sqlite);
      final postgres = Migration('0001_start', [
        'SELECT 1',
      ], dialect: .postgres);
      expect(sqlite.checksum, isNot(postgres.checksum));
      expect(
        MigrationHistory([], dialect: .postgres).dialect,
        SqlDialect.postgres,
      );
      expect(
        () => MigrationHistory([
          (sqlite, sqlite.checksum),
        ], dialect: .postgres).checked,
        throwsA(code('MIGRATION.TARGET')),
      );
      final next = Migration(
        '0002_next',
        ['SELECT 2'],
        dialect: .postgres,
        previous: sqlite.checksum,
      );
      expect(
        () => validateMigrations([sqlite, next], dialect: .sqlite),
        throwsA(code('MIGRATION.TARGET')),
      );
      expect(
        () => validateMigrations([
          Migration.steps('0001_rebuild', [
            RebuildTable(scores(), scores(), copy: {'id': 'id'}),
          ], dialect: .postgres),
        ], dialect: .postgres),
        throwsA(code('MIGRATION.TARGET')),
      );
      expect(
        () => validateMigrations([
          Migration.steps('0001_index', [
            CheckedSql(
              'CREATE INDEX CONCURRENTLY i ON scores(id)',
              readyWhen: 'SELECT true',
              doneWhen: 'SELECT false',
            ),
          ], dialect: .sqlite),
        ], dialect: .sqlite),
        throwsA(code('MIGRATION.TARGET')),
      );
    },
  );

  test('unselected expressions cannot change a saved plan, hash or source', () {
    final before = SchemaSnapshot([scores(other: 'postgres_only_a')]);
    final after = SchemaSnapshot([scores(other: 'postgres_only_b')]);
    final initial = Migration.create(
      '0001_start',
      before.tables,
      dialect: .sqlite,
    );
    final same = Migration.create('0001_start', after.tables, dialect: .sqlite);
    expect(initial.checksum, same.checksum);
    expect(
      Migration.create('0001_start', [
        scores(other: ''),
      ], dialect: .sqlite).checksum,
      initial.checksum,
    );
    final change = Migration.diff(
      '0002_change',
      from: initial.snapshot!,
      to: after,
      previous: initial.checksum,
      dialect: .sqlite,
    );
    expect(change.steps, isEmpty);
    final source = migrationSource(initial);
    expect(source, contains('dialect: SqlDialect.sqlite'));
    expect(source, isNot(contains('postgres')));
    expect(source, isNot(contains('forDialects')));
    Migration fill(TableSchema table) => Migration.steps('0002_fill', [
      Backfill(table, set: {'value': 'id'}, doneWhen: 'SELECT true'),
    ], dialect: .sqlite);
    final a = scores(other: 'unused_a', computed: false);
    final b = scores(other: 'unused_b', computed: false);
    expect(fill(a).checksum, fill(b).checksum);
    expect(migrationSource(fill(a)), isNot(contains('unused_a')));
  });

  test(
    'SQLite virtual indexes and computed mode changes ignore PostgreSQL limits',
    () async {
      final db = await sqlite(const SqliteOptions.memory());
      try {
        final start = Migration.create('0001_start', [
          scores(indexed: true),
        ], dialect: .sqlite);
        expect(
          () => Migration.create('0001_start', [
            scores(indexed: true),
          ], dialect: .postgres),
          throwsA(code('SCHEMA.COMPUTED')),
        );
        await Migrator(db.sql).apply([start]);
        await db.execute(SqlCommand('INSERT INTO scores(id) VALUES (7)'));
        final stored = SchemaSnapshot([
          scores(storage: .stored, indexed: true),
        ]);
        final change = Migration.diff(
          '0002_stored',
          from: start.snapshot!,
          to: stored,
          previous: start.checksum,
          dialect: .sqlite,
        );
        expect(change.steps.single, isA<RebuildTable>());
        await Migrator(db.sql).apply([start, change]);
        final plain = SchemaSnapshot([scores(computed: false, indexed: true)]);
        final materialize = Migration.diff(
          '0003_plain',
          from: change.snapshot!,
          to: plain,
          previous: change.checksum,
          dialect: .sqlite,
        );
        await Migrator(db.sql).apply([start, change, materialize]);
        expect(
          (await db.execute(SqlCommand('SELECT id, value FROM scores')))
              .rows
              .single,
          [7, 14],
        );
        expect((await verifySchema(db.sql, plain)).matches, true);
      } finally {
        await db.close();
      }
    },
  );

  test(
    'replacing stored values with computed values requires explicit review',
    () {
      final from = SchemaSnapshot([scores(computed: false)]);
      final to = SchemaSnapshot([scores(storage: .stored)]);
      expect(
        () => Migration.diff(
          '0002_compute',
          from: from,
          to: to,
          dialect: .sqlite,
        ),
        throwsA(code('MIGRATION.DESTRUCTIVE')),
      );
      expect(
        Migration.diff(
          '0002_compute',
          from: from,
          to: to,
          dialect: .sqlite,
          allowDestructive: true,
        ).steps.single,
        isA<RebuildTable>(),
      );
    },
  );

  test(
    'older PostgreSQL is rejected before locks, journals or partial execution',
    () async {
      final driver = _VersionDriver();
      final db = Database(driver);
      final history = [
        Migration('0001_start', [
          'CREATE TABLE proof(id int)',
        ], dialect: .postgres),
      ];
      for (final operation in [
        () => Migrator(db.sql).apply(history),
        () => Migrator(db.sql).plan(history),
      ]) {
        driver.statements.clear();
        await expectLater(operation(), throwsA(code('CAPABILITY.VERSION')));
        expect(driver.statements, ['SHOW server_version_num']);
      }
    },
  );

  test(
    'registry fixes its engine at initialization and refuses retargeting',
    () async {
      final directory = await Directory.systemTemp.createTemp('orm-target-');
      try {
        await expectLater(
          writeMigrationRegistry(directory.path),
          throwsA(isA<GenerationException>()),
        );
        final path = await writeMigrationRegistry(
          directory.path,
          dialect: .sqlite,
        );
        final source = await File(path).readAsString();
        expect(source, contains('const migrationDialect = SqlDialect.sqlite'));
        await writeMigrationRegistry(directory.path);
        await expectLater(
          writeMigrationRegistry(directory.path, dialect: .postgres),
          throwsA(isA<GenerationException>()),
        );
        expect(await File(path).readAsString(), source);
        await expectLater(
          writeMigration(
            Migration('0001_wrong', ['SELECT 1'], dialect: .postgres),
            directory: directory.path,
            history: MigrationHistory([], dialect: .sqlite),
          ),
          throwsA(code('MIGRATION.TARGET')),
        );
        expect(
          await File('${directory.path}/m0001_wrong.dart').exists(),
          false,
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('wrong engine fails before any migration SQL for runner and every connected CLI command', () async {
    final migration = Migration.create('0001_start', [], dialect: .postgres);
    final history = MigrationHistory([
      (migration, migration.checksum),
    ], dialect: .postgres);
    final base = await sqlite(const SqliteOptions.memory());
    final statements = <String>[];
    final db = Database(base.driver, onQuery: (e) => statements.add(e.sql));
    try {
      await expectLater(
        Migrator(db.sql).apply(history.checked),
        throwsA(code('MIGRATION.TARGET')),
      );
      await expectLater(
        Migrator(db.sql).plan(history.checked),
        throwsA(code('MIGRATION.TARGET')),
      );
      await expectLater(
        Migrator(db.sql)
            .baseline(history.checked, expected: SchemaSnapshot([])),
        throwsA(code('MIGRATION.TARGET')),
      );
      expect(statements, isEmpty);
    } finally {
      await db.close();
    }
    for (final args in [
      ['plan'],
      ['apply'],
      ['status'],
      ['verify'],
      ['baseline'],
      ['inspect', 'scores'],
    ]) {
      var connected = false;
      try {
        await runMigrationCli(
          args,
          history: args.first == 'apply'
              ? MigrationHistory([], dialect: .postgres)
              : history,
          directory: 'unused',
          schema: SchemaSnapshot([]),
          connect: ({required readOnly}) async {
            connected = true;
            final base = await sqlite(const SqliteOptions.memory());
            return SqlDatabase(
              base.driver,
              onQuery: (e) => statements.add(e.sql),
            );
          },
        );
        expect(exitCode, 1, reason: args.first);
        expect(connected, true);
        expect(statements, isEmpty);
      } finally {
        exitCode = 0;
      }
    }
  });

  if (Platform.environment['ORM_TEST_POSTGRES'] case final url?) {
    test('PostgreSQL applies only its own generated conversion and rejects a SQLite history before SQL', () async {
      final base = postgres(
        PostgresOptions(
          url: Uri.parse(url),
          tls: .disable,
          schema: 'orm_target_tests',
          maxConnections: 1,
        ),
      );
      final statements = <String>[];
      final db = Database(base.driver, onQuery: (e) => statements.add(e.sql));
      try {
        final wrong = Migration.create('0001_wrong', [], dialect: .sqlite);
        await expectLater(
          Migrator(db.sql).apply([wrong]),
          throwsA(code('MIGRATION.TARGET')),
        );
        expect(statements, isEmpty);
        await db.execute(SqlCommand('CREATE SCHEMA orm_target_tests'));
        TableSchema table(Codec<Object?> codec) => TableSchema(
          'values',
          columns: [Column('id', codec)],
          primaryKey: ['id'],
        );
        final start = Migration.create('0001_start', [
          table(Codecs.text),
        ], dialect: .postgres);
        await Migrator(db.sql).apply([start]);
        await db.execute(SqlCommand('INSERT INTO "values" VALUES (\'42\')'));
        final change = Migration.diff(
          '0002_integer',
          dialect: .postgres,
          from: start.snapshot!,
          to: SchemaSnapshot([table(Codecs.integer)]),
          previous: start.checksum,
          using: {
            'values': {'id': 'id::bigint'},
          },
        );
        expect(migrationSource(change), isNot(contains('sqlite')));
        await Migrator(db.sql).apply([start, change]);
        expect(
          (await db.execute(SqlCommand('SELECT id FROM "values"')))
              .rows
              .single
              .single,
          42,
        );
        expect(await Migrator(db.sql).apply([start, change]), isEmpty);
      } finally {
        await db.execute(
          SqlCommand('DROP SCHEMA IF EXISTS orm_target_tests CASCADE'),
        );
        await db.close();
      }
    });
  }
}

/// Unit-level server-version response. Real PostgreSQL execution is tested above.
final class _VersionDriver implements Driver<Postgres>, SqlConnection {
  final statements = <String>[];
  @override
  Capabilities get capabilities =>
      const Capabilities(dialect: SqlDialect.postgres, maxParameters: 65535);
  @override
  bool? get transactionActive => false;
  @override
  Future<R> run<R>(Future<R> Function(SqlConnection) action) => action(this);
  @override
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    statements.add(command.sql);
    if (command.sql != 'SHOW server_version_num') {
      throw StateError('Unexpected SQL: ${command.sql}');
    }
    return const SqlResult(
      [
        ['170000'],
      ],
      columns: ['server_version_num'],
    );
  }

  @override
  Future<SqlCursor> openCursor(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) => throw UnimplementedError();
  @override
  Future<void> invalidate() async {}
  @override
  Future<void> close() async {}
}
