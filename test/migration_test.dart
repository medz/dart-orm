import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

TableSchema accounts({
  String name = 'accounts',
  String label = 'nickname',
  bool requiredLabel = false,
  String scoreDefault = '0',
  bool textScore = false,
  bool extra = false,
  bool compoundUnique = false,
}) => TableSchema(
  name,
  columns: [
    Column('id', Codecs.integer, generated: true),
    Column('email', Codecs.text),
    Column(
      label,
      requiredLabel ? Codecs.text : Codecs.text.nullable(),
      nullable: !requiredLabel,
    ),
    Column(
      'score',
      textScore ? Codecs.text : Codecs.integer,
      defaultSql: scoreDefault,
    ),
    if (extra) Column('status', Codecs.text, defaultSql: "'active'"),
  ],
  primaryKey: ['id'],
  uniqueKeys: [
    compoundUnique ? ['email', label] : ['email'],
  ],
  indexes: [
    IndexSchema('account_label', [label]),
  ],
);
TableSchema notes({String target = 'accounts', String onDelete = 'CASCADE'}) =>
    TableSchema(
      'notes',
      columns: [
        Column('id', Codecs.integer),
        Column('account_id', Codecs.integer),
        Column('body', Codecs.text),
      ],
      primaryKey: ['id'],
      foreignKeys: [
        ForeignKey(['account_id'], target, ['id'], onDelete: onDelete),
      ],
    );

void main() {
  runMigrations('sqlite', () => sqlite(const SqliteOptions.memory()));
  final url = Platform.environment['ORM_TEST_POSTGRES'];
  if (url != null) {
    late Database<Postgres> admin;
    setUpAll(() async {
      admin = postgres(PostgresOptions(url: Uri.parse(url), tls: .disable));
      await admin.execute(
        SqlCommand('CREATE SCHEMA IF NOT EXISTS orm_migration_tests'),
      );
    });
    tearDownAll(() async {
      await admin.execute(
        SqlCommand('DROP SCHEMA orm_migration_tests CASCADE'),
      );
      await admin.close();
    });
    runMigrations(
      'postgres',
      () async => postgres(
        PostgresOptions(
          url: Uri.parse(url),
          tls: .disable,
          schema: 'orm_migration_tests',
        ),
      ),
    );
  }
  test('diff requires explicit renames, casts and backfills', () {
    final from = SchemaSnapshot([accounts()]);
    final renamed = SchemaSnapshot([accounts(name: 'members')]);
    expect(
      () => Migration.diff('0002_change', from: from, to: renamed),
      throwsA(
        isA<OrmException>().having(
          (e) => e.code,
          'code',
          'MIGRATION.DESTRUCTIVE',
        ),
      ),
    );
    expect(
      () => Migration.diff(
        '0002_change',
        from: from,
        to: SchemaSnapshot([accounts(textScore: true)]),
      ),
      throwsA(
        isA<OrmException>().having((e) => e.code, 'code', 'MIGRATION.CAST'),
      ),
    );
    final required = TableSchema(
      'accounts',
      columns: [...accounts().columns, Column('required', Codecs.text)],
      primaryKey: ['id'],
      uniqueKeys: [
        ['email'],
      ],
    );
    expect(
      () => Migration.diff(
        '0002_change',
        from: from,
        to: SchemaSnapshot([required]),
      ),
      throwsA(
        isA<OrmException>().having((e) => e.code, 'code', 'MIGRATION.BACKFILL'),
      ),
    );
    expect(
      Migration.diff(
        '0002_same',
        from: from,
        to: from,
      ).steps.values.every((s) => s.isEmpty),
      true,
    );
  });
}

void runMigrations(String backend, Future<Database<Backend>> Function() open) {
  group('migrations $backend', () {
    late Database<Backend> db;
    late SchemaSnapshot start;
    late Migration initial;
    setUp(() async {
      db = await open();
      await db.execute(SqlCommand('DROP VIEW IF EXISTS account_cards'));
      for (final table in [
        'notes',
        'accounts',
        'members',
        'audit',
        '_orm_migrations',
      ]) {
        await db.execute(SqlCommand('DROP TABLE IF EXISTS "$table"'));
      }
      start = SchemaSnapshot([accounts(), notes()]);
      initial = Migration.create('0001_initial', start.tables);
      await Migrator(db).apply([initial]);
      await db.execute(
        SqlCommand(
          "INSERT INTO accounts(id, email, nickname, score) VALUES (1, 'seven', NULL, 17)",
        ),
      );
      await db.execute(
        SqlCommand("INSERT INTO notes VALUES (2, 1, 'preserve')"),
      );
    });
    tearDown(() => db.close());

    test(
      'explicit table and column renames preserve incoming references and data',
      () async {
        final target = SchemaSnapshot([
          accounts(
            name: 'members',
            label: 'label',
            scoreDefault: '5',
            extra: true,
          ),
          notes(target: 'members'),
        ]);
        final migration = Migration.diff(
          '0002_rename',
          from: start,
          to: target,
          previous: initial.checksum,
          renames: const SchemaRenames(
            tables: {'accounts': 'members'},
            columns: {
              'members': {'nickname': 'label'},
            },
          ),
        );
        await Migrator(db).apply([initial, migration]);
        expect(
          (await db.execute(
            SqlCommand('SELECT id, email, label, score, status FROM members'),
          )).rows.single,
          [1, 'seven', null, 17, 'active'],
        );
        expect(
          (await db.execute(SqlCommand('SELECT body FROM notes'))).rows.single,
          ['preserve'],
        );
        expect((await verifySchema(db, target)).differences, isEmpty);
        expect(await inspectColumns(db, 'accounts'), isEmpty);
      },
    );

    test('constraint changes resolve catalog names and retain rows', () async {
      final target = SchemaSnapshot([
        accounts(compoundUnique: true),
        notes(onDelete: 'RESTRICT'),
      ]);
      final migration = Migration.diff(
        '0002_constraints',
        from: start,
        to: target,
        previous: initial.checksum,
      );
      await Migrator(db).apply([initial, migration]);
      expect((await verifySchema(db, target)).differences, isEmpty);
      expect(
        (await db.execute(SqlCommand('SELECT COUNT(*) FROM notes')))
            .rows
            .single
            .single,
        1,
      );
      await expectLater(
        db.execute(SqlCommand('DELETE FROM accounts WHERE id = 1')),
        throwsA(anything),
      );
    });

    test(
      'failed NOT NULL rebuild restores data history and foreign key settings',
      () async {
        final target = SchemaSnapshot([accounts(requiredLabel: true), notes()]);
        final migration = Migration.diff(
          '0002_required',
          from: start,
          to: target,
          previous: initial.checksum,
        );
        await expectLater(
          Migrator(db).apply([initial, migration]),
          throwsA(anything),
        );
        expect((await verifySchema(db, start)).differences, isEmpty);
        expect((await Migrator(db).history()).length, 1);
        expect(
          (await db.execute(SqlCommand('SELECT nickname FROM accounts')))
              .rows
              .single
              .single,
          null,
        );
        if (db.dialect == SqlDialect.sqlite) {
          expect(
            (await db.execute(SqlCommand('PRAGMA foreign_keys')))
                .rows
                .single
                .single,
            1,
          );
        }
        final fill = Migration('0002_backfill', {
          for (final d in SqlDialect.values)
            d: [
              "UPDATE accounts SET nickname = 'Seven' WHERE nickname IS NULL",
            ],
        }, previous: initial.checksum);
        final required = Migration.diff(
          '0003_required',
          from: start,
          to: target,
          previous: fill.checksum,
        );
        await Migrator(db).apply([initial, fill, required]);
        expect((await verifySchema(db, target)).differences, isEmpty);
        expect(
          (await db.execute(SqlCommand('SELECT nickname FROM accounts')))
              .rows
              .single
              .single,
          'Seven',
        );
      },
    );

    test('reviewed conversion expressions preserve values when storage types change', () async {
      final target = SchemaSnapshot([
        accounts(textScore: true, scoreDefault: "'0'"),
        notes(),
      ]);
      final migration = Migration.diff(
        '0002_convert',
        from: start,
        to: target,
        previous: initial.checksum,
        using: {
          for (final d in SqlDialect.values)
            d: {
              'accounts': {'score': 'CAST(score AS TEXT)'},
            },
        },
      );
      await Migrator(db).apply([initial, migration]);
      expect(
        (await db.execute(SqlCommand('SELECT score FROM accounts')))
            .rows
            .single
            .single,
        '17',
      );
      expect((await verifySchema(db, target)).differences, isEmpty);
    });

    test('additive changes use ALTER without a table rebuild', () async {
      final target = SchemaSnapshot([accounts(extra: true), notes()]);
      final migration = Migration.diff(
        '0002_add',
        from: start,
        to: target,
        previous: initial.checksum,
      );
      expect(migration.steps[db.dialect]!.whereType<RebuildTable>(), isEmpty);
      await Migrator(db).apply([initial, migration]);
      expect((await verifySchema(db, target)).differences, isEmpty);
      expect(
        (await db.execute(SqlCommand('SELECT status FROM accounts')))
            .rows
            .single
            .single,
        'active',
      );
    });

    test(
      'reviewed table removal handles restrictive foreign keys atomically',
      () async {
        final restricted = SchemaSnapshot([
          accounts(),
          notes(onDelete: 'RESTRICT'),
        ]);
        final change = Migration.diff(
          '0002_restrict',
          from: start,
          to: restricted,
          previous: initial.checksum,
        );
        await Migrator(db).apply([initial, change]);
        final remove = Migration.diff(
          '0003_remove',
          from: restricted,
          to: SchemaSnapshot([]),
          previous: change.checksum,
          allowDestructive: true,
        );
        await Migrator(db).apply([initial, change, remove]);
        expect(await inspectColumns(db, 'accounts'), isEmpty);
        expect(await inspectColumns(db, 'notes'), isEmpty);
        expect((await Migrator(db).history()).length, 3);
        if (db.dialect == SqlDialect.sqlite) {
          expect(
            (await db.execute(SqlCommand('PRAGMA foreign_keys')))
                .rows
                .single
                .single,
            1,
          );
        }
      },
    );

    test('broken migration chain is refused before DDL', () async {
      final migration = Migration.diff(
        '0002_add',
        from: start,
        to: SchemaSnapshot([accounts(extra: true), notes()]),
        previous: 'wrong',
      );
      await expectLater(
        Migrator(db).apply([initial, migration]),
        throwsA(
          isA<OrmException>().having((e) => e.code, 'code', 'MIGRATION.CHAIN'),
        ),
      );
      expect((await verifySchema(db, start)).differences, isEmpty);
    });

    if (backend == 'sqlite') {
      test('catalog distinguishes nullable non-rowid primary keys', () async {
        await db.execute(
          SqlCommand('CREATE TABLE audit (id TEXT PRIMARY KEY)'),
        );
        expect((await inspectColumns(db, 'audit')).single.nullable, true);
        await db.execute(SqlCommand('DROP TABLE audit'));
        await db.execute(
          SqlCommand('CREATE TABLE audit (id INTEGER PRIMARY KEY)'),
        );
        expect((await inspectColumns(db, 'audit')).single.nullable, false);
      });

      test(
        'rebuild preserves unmanaged index trigger and view definitions',
        () async {
          await db.execute(
            SqlCommand('CREATE TABLE audit (account_id INTEGER, email TEXT)'),
          );
          await db.execute(
            SqlCommand('CREATE INDEX email_search ON accounts(lower(email))'),
          );
          await db.execute(
            SqlCommand(
              'CREATE TRIGGER account_audit AFTER UPDATE OF email ON accounts BEGIN INSERT INTO audit VALUES (new.id, new.email); END',
            ),
          );
          await db.execute(
            SqlCommand(
              'CREATE VIEW account_cards AS SELECT id, email FROM accounts',
            ),
          );
          final target = SchemaSnapshot([accounts(scoreDefault: '9'), notes()]);
          await Migrator(db).apply([
            initial,
            Migration.diff(
              '0002_default',
              from: start,
              to: target,
              previous: initial.checksum,
            ),
          ]);
          await db.execute(
            SqlCommand("UPDATE accounts SET email = 'updated' WHERE id = 1"),
          );
          expect(
            (await db.execute(SqlCommand('SELECT email FROM account_cards')))
                .rows
                .single
                .single,
            'updated',
          );
          expect(
            (await db.execute(SqlCommand('SELECT * FROM audit'))).rows.single,
            [1, 'updated'],
          );
          expect(
            (await inspectTable(db, 'accounts')).unmanaged.map((o) => o.name),
            containsAll(['email_search', 'account_audit', 'account_cards']),
          );
        },
      );

      test('foreign key check rolls back changed parent keys without cascading data away', () async {
        final rebuilt = RebuildTable(
          accounts(),
          accounts(),
          copy: {
            'id': 'id + 100',
            'email': 'email',
            'nickname': 'nickname',
            'score': 'score',
          },
        );
        final bad = Migration.steps('0002_invalid', {
          SqlDialect.sqlite: [rebuilt],
        }, previous: initial.checksum);
        await expectLater(
          Migrator(db).apply([initial, bad]),
          throwsA(
            isA<OrmException>().having(
              (e) => e.code,
              'code',
              'MIGRATION.FOREIGN_KEY',
            ),
          ),
        );
        expect(
          (await db.execute(SqlCommand('SELECT id FROM accounts')))
              .rows
              .single
              .single,
          1,
        );
        expect(
          (await db.execute(SqlCommand('SELECT body FROM notes')))
              .rows
              .single
              .single,
          'preserve',
        );
        expect(
          (await db.execute(SqlCommand('PRAGMA foreign_keys')))
              .rows
              .single
              .single,
          1,
        );
      });

      test('unmodeled CHECK constraints are refused without losing their definition', () async {
        await db.execute(
          SqlCommand(
            'ALTER TABLE accounts ADD COLUMN checked INTEGER CHECK (checked > 0)',
          ),
        );
        final old = TableSchema(
          'accounts',
          columns: [
            ...accounts().columns,
            Column('checked', Codecs.integer.nullable(), nullable: true),
          ],
          primaryKey: ['id'],
          uniqueKeys: [
            ['email'],
          ],
          indexes: accounts().indexes,
        );
        final next = TableSchema(
          'accounts',
          columns: [
            ...accounts(scoreDefault: '8').columns,
            Column('checked', Codecs.integer.nullable(), nullable: true),
          ],
          primaryKey: ['id'],
          uniqueKeys: [
            ['email'],
          ],
          indexes: accounts().indexes,
        );
        final migration = Migration.diff(
          '0002_default',
          from: SchemaSnapshot([old, notes()]),
          to: SchemaSnapshot([next, notes()]),
          previous: initial.checksum,
        );
        await expectLater(
          Migrator(db).apply([initial, migration]),
          throwsA(
            isA<OrmException>().having(
              (e) => e.code,
              'code',
              'MIGRATION.UNMANAGED',
            ),
          ),
        );
        await expectLater(
          db.execute(SqlCommand('UPDATE accounts SET checked = -1')),
          throwsA(anything),
        );
        expect((await Migrator(db).history()).length, 1);
      });
    }
  });
}
