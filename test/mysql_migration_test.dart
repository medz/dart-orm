import 'dart:io';

import 'package:orm/drivers/mysql.dart';
import 'package:orm/drivers/mariadb.dart';
import 'package:orm/migrate.dart';
import 'package:orm/runtime.dart';
import 'package:test/test.dart';

import '../tool/src/build_fixture.dart';

TableSchema _items({
  String table = 'items',
  String label = 'label',
  bool note = false,
  bool requiredNote = false,
}) => TableSchema(
  table,
  columns: [
    Column('id', Codecs.integer, generated: true),
    Column(label, Codecs.text),
    Column('enabled', Codecs.boolean, defaultSql: 'false'),
    Column('escaped', Codecs.text, defaultSql: r"'a''b\c'"),
    Column(
      'created',
      Codecs.localDateTime,
      temporalPrecision: 3,
      defaultSql: 'CURRENT_TIMESTAMP(3)',
    ),
    Column(
      'amount',
      Codecs.decimal,
      decimalPrecision: 12,
      decimalScale: 2,
      defaultSql: '0.00',
    ),
    if (note)
      Column(
        'note',
        requiredNote ? Codecs.text : Codecs.text.nullable(),
        nullable: !requiredNote,
      ),
  ],
  primaryKey: ['id'],
  uniqueKeys: [
    [label],
  ],
  checks: [
    const CheckSchema(
      'items_amount_positive',
      'amount >= 0 AND amount <= 1000000',
    ),
  ],
);

void main() {
  for (final dialect in [SqlDialect.mysql, SqlDialect.mariadb]) {
    test(
      '${dialect.name} freezes recoverable DDL and standalone Dart source',
      () {
        final migration = Migration.create('0001_initial', [
          _items(),
        ], dialect: dialect);
        expect(migration.steps, everyElement(isA<CheckedTableSql>()));
        expect(migrationSource(migration), contains('CheckedTableSql('));
        expect(
          migrationSource(migration),
          contains('SqlDialect.${dialect.name}'),
        );
        expect(
          migration.checksum,
          Migration.create('0001_initial', [
            _items(),
          ], dialect: dialect).checksum,
        );
        validateMigrations([migration], dialect: dialect);
      },
    );
    test('${dialect.name} rejects uncheckpointed DDL and unsafe narrowing', () {
      expect(
        () => validateMigrations([
          Migration('0001_unsafe', [
            'CREATE TABLE unsafe (id INT)',
          ], dialect: dialect),
        ], dialect: dialect),
        throwsA(isA<OrmException>()),
      );
      for (final sql in [
        'UPDATE n SET id = 1; COMMIT',
        'UPDATE n SET id = 1 /*!; COMMIT */',
      ]) {
        expect(
          () => validateMigrations([
            Migration('0001_hidden', [sql], dialect: dialect),
          ], dialect: dialect),
          throwsA(isA<OrmException>()),
        );
      }
      final a = TableSchema(
        'n',
        columns: [Column('id', Codecs.integer)],
        primaryKey: ['id'],
      );
      final b = TableSchema(
        'n',
        columns: [Column('id', Codecs.integer, integerBits: 16)],
        primaryKey: ['id'],
      );
      expect(
        () => Migration.diff(
          '0002_narrow',
          dialect: dialect,
          from: SchemaSnapshot([a]),
          to: SchemaSnapshot([b]),
        ),
        throwsA(isA<OrmException>()),
      );
      expect(
        () => Migration.diff(
          '0002_drop',
          dialect: dialect,
          from: SchemaSnapshot([a]),
          to: SchemaSnapshot([]),
        ),
        throwsA(isA<OrmException>()),
      );
    });
  }
  test('MySQL and MariaDB frozen Dart migrations compile with unchanged fingerprints', () async {
    final fixture = await BuildFixture.create(ormPath: Directory.current.path);
    try {
      final imports = <String>[];
      final assertions = <String>[];
      for (final dialect in [SqlDialect.mysql, SqlDialect.mariadb]) {
        final first = Migration.create('0001_initial', [
          _items(),
        ], dialect: dialect);
        final after = _items(note: true);
        final change = Migration.diff(
          '0002_backfill',
          dialect: dialect,
          from: first.snapshot!,
          to: SchemaSnapshot([after]),
        );
        final second = Migration.steps(
          '0002_backfill',
          [
            ...change.steps,
            Backfill(after, set: {'note': 'label'}, doneWhen: 'SELECT TRUE'),
          ],
          dialect: dialect,
          previous: first.checksum,
          snapshot: SchemaSnapshot([after]),
        );
        for (final migration in [first, second]) {
          final alias = '${dialect.name}_${migration.id}';
          await fixture.write('lib/$alias.dart', migrationSource(migration));
          imports.add("import '../lib/$alias.dart' as $alias;");
          assertions.add(
            "if ($alias.migration.checksum != $alias.migrationChecksum || $alias.migration.checksum != '${migration.checksum}') throw StateError('$alias fingerprint');",
          );
        }
      }
      for (final dialect in [SqlDialect.mysql, SqlDialect.mariadb]) {
        assertions.add(
          'validateMigrations([${dialect.name}_0001_initial.migration, ${dialect.name}_0002_backfill.migration], dialect: SqlDialect.${dialect.name});',
        );
      }
      await fixture.write(
        'bin/check.dart',
        "import 'package:orm/migrate.dart';\n${imports.join('\n')}\nvoid main() { ${assertions.join('\n')} print('frozen-mysql-history-ok'); }",
      );
      final result = await fixture.run(['run', 'bin/check.dart']);
      expect(result.output, contains('frozen-mysql-history-ok'));
    } finally {
      await fixture.dispose();
    }
  });

  for (final engine in ['mysql', 'mariadb']) {
    final variable = 'ORM_TEST_${engine.toUpperCase()}';
    final address = Platform.environment[variable];
    final tls = MysqlTls.values.byName(
      Platform.environment['${variable}_TLS'] ?? 'verifyFull',
    );
    group(
      '$engine migrations',
      () {
        late SqlDatabase<Backend> admin, db;
        late _FaultDriver driver;
        final namespace = 'orm_migrations_${pid}_$engine';
        Future<Driver<Backend>> open(Uri url) async => engine == 'mysql'
            ? await MysqlDriver.open(MysqlOptions(url: url, tls: tls))
            : await MariadbDriver.open(MariadbOptions(url: url, tls: tls));
        setUpAll(() async {
          admin = SqlDatabase(await open(Uri.parse(address!)));
        });
        tearDownAll(() => admin.close());
        setUp(() async {
          await admin.execute(
            SqlCommand('DROP DATABASE IF EXISTS "$namespace"'),
          );
          await admin.execute(
            SqlCommand(
              'CREATE DATABASE "$namespace" CHARACTER SET utf8mb4 COLLATE utf8mb4_bin',
            ),
          );
          driver = _FaultDriver(
            await open(Uri.parse(address!).replace(path: '/$namespace')),
          );
          db = SqlDatabase(driver);
        });
        tearDown(() async {
          await db.close();
          await admin.execute(SqlCommand('DROP DATABASE "$namespace"'));
        });
        Migration initial() =>
            Migration.create('0001_initial', [_items()], dialect: db.dialect);

        test('create, catalog, immutable history and DML agree', () async {
          final migration = initial();
          expect(await Migrator(db).apply([migration]), ['0001_initial']);
          final check = await verifySchema(db, migration.snapshot!);
          expect(check.differences, isEmpty);
          expect(check.unmanaged, isEmpty);
          expect(await Migrator(db).apply([migration]), isEmpty);
          expect(
            (await Migrator(db).requireVersion([migration])).id,
            migration.id,
          );
          expect(
            (await Migrator(db).progress()).map((p) => p.state),
            everyElement(MigrationStepState.complete),
          );
          await expectLater(
            Migrator(db).plan([
              Migration.create('0001_initial', [
                _items(note: true),
              ], dialect: db.dialect),
            ]),
            throwsA(isA<OrmException>()),
          );
        });

        for (final metadata in ['_orm_migrations', '_orm_migration_steps']) {
          test('temporary-only $metadata cannot receive migration state', () async {
            final first = initial();
            await db.session((session) async {
              final columns = metadata == '_orm_migrations'
                  ? 'id VARCHAR(191) NOT NULL PRIMARY KEY, checksum CHAR(64) NOT NULL, applied_at VARCHAR(40) NOT NULL'
                  : 'migration_id VARCHAR(191) NOT NULL, checksum CHAR(64) NOT NULL, step INT NOT NULL, state VARCHAR(16) NOT NULL, phase VARCHAR(32) NOT NULL, failure TEXT, backfill LONGTEXT, PRIMARY KEY(migration_id, step)';
              expect(
                (await session.execute(
                  SqlCommand(
                    'SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=?',
                    [metadata],
                  ),
                )).rows,
                isEmpty,
              );
              await session.execute(
                SqlCommand(
                  'CREATE TEMPORARY TABLE "$metadata" ($columns) ENGINE=InnoDB',
                ),
              );
              try {
                await expectLater(
                  Migrator(session).apply([first]),
                  throwsA(
                    isA<OrmException>().having(
                      (error) => error.code,
                      'code',
                      'MIGRATION.SESSION',
                    ),
                  ),
                );
                expect(
                  (await session.execute(
                    SqlCommand('SELECT * FROM "$metadata"'),
                  )).rows,
                  isEmpty,
                );
                expect(await inspectColumns(session, 'items'), isEmpty);
              } finally {
                await session.execute(
                  SqlCommand('DROP TEMPORARY TABLE "$metadata"'),
                );
              }
            });
            expect(await Migrator(db).history(), isEmpty);
            expect(await Migrator(db).progress(), isEmpty);
            expect(await Migrator(db).apply([first]), [first.id]);
          });
        }

        test(
          'DDL acknowledgement failure resumes from exact catalog state',
          () async {
            final first = initial();
            await Migrator(db).apply([first]);
            final second = Migration.diff(
              '0002_note',
              dialect: db.dialect,
              from: first.snapshot!,
              to: SchemaSnapshot([_items(note: true)]),
              previous: first.checksum,
            );
            driver.failAfterDdl = true;
            await expectLater(
              Migrator(db).apply([first, second]),
              throwsA(isA<OrmException>()),
            );
            expect(
              (await inspectColumns(db, 'items')).map((c) => c.name),
              contains('note'),
            );
            expect((await Migrator(db).history()), hasLength(1));
            final executed = driver.alterCount;
            expect(await Migrator(db).apply([first, second]), [second.id]);
            expect(
              driver.alterCount,
              executed,
              reason: 'the acknowledged durable DDL must not replay',
            );
          },
        );

        test(
          'same table name with wrong shape is never accepted as completion',
          () async {
            await db.execute(
              SqlCommand(
                'CREATE TABLE items (id BIGINT NOT NULL PRIMARY KEY) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin',
              ),
            );
            await expectLater(
              Migrator(db).apply([initial()]),
              throwsA(isA<OrmException>()),
            );
            expect(await Migrator(db).history(), isEmpty);
            expect(
              (await Migrator(db).progress()).single.failure,
              'MIGRATION.RECOVERY',
            );
            expect((await inspectColumns(db, 'items')), hasLength(1));
            final other = SqlDatabase(
              await open(Uri.parse(address!).replace(path: '/$namespace')),
            );
            try {
              await expectLater(
                Migrator(other, lockTimeout: Duration.zero).apply([initial()]),
                throwsA(
                  isA<OrmException>().having(
                    (e) => e.code,
                    'code',
                    'MIGRATION.STEP',
                  ),
                ),
              );
            } finally {
              await other.close();
            }
          },
        );

        test(
          'bounded backfill checkpoints rows with DML in one transaction',
          () async {
            final first = initial();
            await Migrator(db).apply([first]);
            await db.execute(
              SqlCommand("INSERT INTO items(label) VALUES ('a'), ('b'), ('c')"),
            );
            final expanded = _items(note: true);
            final diff = Migration.diff(
              '0002_fill',
              dialect: db.dialect,
              from: first.snapshot!,
              to: SchemaSnapshot([expanded]),
            );
            final second = Migration.steps(
              '0002_fill',
              [
                ...diff.steps,
                Backfill(
                  expanded,
                  set: {'note': 'label'},
                  where: 'note IS NULL',
                  doneWhen: 'SELECT NOT EXISTS (SELECT 1 FROM items WHERE note IS NULL)',
                  batchSize: 1,
                ),
              ],
              dialect: db.dialect,
              snapshot: SchemaSnapshot([expanded]),
              previous: first.checksum,
            );
            expect(
              await Migrator(db).apply([first, second], maxBackfillBatches: 1),
              isEmpty,
            );
            expect((await Migrator(db).progress()).last.backfill!.rows, 1);
            expect(await Migrator(db).apply([first, second]), [second.id]);
            expect(
              (await db.execute(
                SqlCommand('SELECT label,note FROM items ORDER BY id'),
              )).rows,
              [
                ['a', 'a'],
                ['b', 'b'],
                ['c', 'c'],
              ],
            );
            final third = Migration.diff(
              '0003_required',
              dialect: db.dialect,
              from: second.snapshot!,
              to: SchemaSnapshot([_items(note: true, requiredNote: true)]),
              previous: second.checksum,
            );
            expect(await Migrator(db).apply([first, second, third]), [
              third.id,
            ]);
          },
        );

        test(
          'exact BigInt and instant cursors survive backfill resume',
          () async {
            final table = TableSchema(
              'cursor_keys',
              columns: [
                Column('huge', Codecs.bigint),
                Column('moment', Codecs.dateTime),
                Column('touches', Codecs.integer, defaultSql: '0'),
              ],
              primaryKey: ['huge', 'moment'],
            );
            final first = Migration.create('0001_keys', [
              table,
            ], dialect: db.dialect);
            await Migrator(db).apply([first]);
            final moments = [
              DateTime.utc(2026, 1, 1, 0, 0, 0, 0, 1),
              DateTime.utc(2026, 1, 1, 0, 0, 0, 0, 2),
            ];
            for (var i = 0; i < 2; i++) {
              await db.execute(
                SqlCommand(
                  'INSERT INTO cursor_keys(huge,moment) VALUES (?,?)',
                  [
                    BigInt.parse('90071992547409930000') + BigInt.from(i),
                    moments[i],
                  ],
                ),
              );
            }
            final second = Migration.steps(
              '0002_fill',
              [
                Backfill(
                  table,
                  set: {'touches': 'touches + 1'},
                  where: 'touches = 0',
                  doneWhen: 'SELECT NOT EXISTS (SELECT 1 FROM cursor_keys WHERE touches <> 1)',
                  batchSize: 1,
                ),
              ],
              dialect: db.dialect,
              previous: first.checksum,
              snapshot: SchemaSnapshot([table]),
            );
            expect(
              await Migrator(db).apply([first, second], maxBackfillBatches: 1),
              isEmpty,
            );
            expect((await Migrator(db).progress()).last.backfill!.rows, 1);
            expect(await Migrator(db).apply([first, second]), [second.id]);
            final rows = (await db.execute(
              SqlCommand(
                'SELECT huge,moment,touches FROM cursor_keys ORDER BY huge,moment',
              ),
            )).rows;
            expect(rows.map((r) => r[0].toString()), [
              '90071992547409930000',
              '90071992547409930001',
            ]);
            expect(rows.map((r) => Codecs.dateTime.decode(r[1])), moments);
            expect(rows.map((r) => r[2]), [1, 1]);
          },
        );

        test('DML rolls back when its completion checkpoint fails', () async {
          final first = initial();
          await Migrator(db).apply([first]);
          await db.execute(
            SqlCommand("INSERT INTO items(label) VALUES ('old')"),
          );
          final second = Migration(
            '0002_data',
            ["UPDATE items SET label = 'new'"],
            dialect: db.dialect,
            previous: first.checksum,
          );
          driver.failDmlCheckpoint = true;
          await expectLater(
            Migrator(db).apply([first, second]),
            throwsA(isA<OrmException>()),
          );
          expect(
            (await db.execute(SqlCommand('SELECT label FROM items')))
                .rows
                .single
                .single,
            'old',
          );
          expect(await Migrator(db).apply([first, second]), [second.id]);
          expect(
            (await db.execute(SqlCommand('SELECT label FROM items')))
                .rows
                .single
                .single,
            'new',
          );
        });

        test(
          'uncertain DML commit preserves completion and never repeats writes',
          () async {
            final first = initial();
            await Migrator(db).apply([first]);
            await db.execute(
              SqlCommand("INSERT INTO items(label) VALUES ('old')"),
            );
            final second = Migration(
              '0002_data',
              ["UPDATE items SET label = CONCAT(label, '!')"],
              dialect: db.dialect,
              previous: first.checksum,
            );
            driver.failAfterDmlCommit = true;
            await expectLater(
              Migrator(db).apply([first, second]),
              throwsA(isA<OrmException>()),
            );
            expect(
              (await Migrator(db).progress()).last.state,
              MigrationStepState.complete,
            );
            expect(
              (await db.execute(SqlCommand('SELECT label FROM items')))
                  .rows
                  .single
                  .single,
              'old!',
            );
            expect(await Migrator(db).apply([first, second]), [second.id]);
            expect(
              (await db.execute(SqlCommand('SELECT label FROM items')))
                  .rows
                  .single
                  .single,
              'old!',
            );
          },
        );

        test(
          'explicit table and column renames retain data and canonical keys',
          () async {
            final first = initial();
            await Migrator(db).apply([first]);
            await db.execute(
              SqlCommand("INSERT INTO items(label) VALUES ('kept')"),
            );
            final next = _items(table: 'products', label: 'title');
            final second = Migration.diff(
              '0002_rename',
              dialect: db.dialect,
              from: first.snapshot!,
              to: SchemaSnapshot([next]),
              renames: const SchemaRenames(
                tables: {'items': 'products'},
                columns: {
                  'products': {'label': 'title'},
                },
              ),
              previous: first.checksum,
            );
            expect(await Migrator(db).apply([first, second]), [second.id]);
            expect(
              (await db.execute(SqlCommand('SELECT title FROM products')))
                  .rows
                  .single
                  .single,
              'kept',
            );
            expect(
              (await verifySchema(db, second.snapshot!)).differences,
              isEmpty,
            );
          },
        );

        test('foreign keys, supporting indexes, JSON and computed values round trip', () async {
          final parent = TableSchema(
            'parents',
            columns: [Column('id', Codecs.integer)],
            primaryKey: ['id'],
          );
          final child = TableSchema(
            'children',
            columns: [
              Column('id', Codecs.integer),
              Column('parent_id', Codecs.integer),
              Column(
                'document',
                Codecs.jsonDocument.nullable(),
                nullable: true,
              ),
              Column(
                'doubled',
                Codecs.integer.nullable(),
                nullable: true,
                computed: const ComputedColumn('id * (id + 1)'),
              ),
            ],
            primaryKey: ['id'],
            foreignKeys: [
              const ForeignKey(
                ['parent_id'],
                'parents',
                ['id'],
                onDelete: 'NO ACTION',
              ),
            ],
          );
          final first = Migration.create('0001_relations', [
            parent,
            child,
          ], dialect: db.dialect);
          expect(await Migrator(db).apply([first]), [first.id]);
          final verified = await verifySchema(db, first.snapshot!);
          expect(verified.differences, isEmpty);
          expect(verified.unmanaged, isEmpty);
          await db.execute(SqlCommand('INSERT INTO parents VALUES (1)'));
          await db.execute(
            SqlCommand('INSERT INTO children(id,parent_id) VALUES(2,1)'),
          );
          expect(
            (await db.execute(SqlCommand('SELECT doubled FROM children')))
                .rows
                .single
                .single,
            6,
          );
          final second = Migration.diff(
            '0002_drop_relations',
            dialect: db.dialect,
            from: first.snapshot!,
            to: SchemaSnapshot([]),
            previous: first.checksum,
            allowDestructive: true,
          );
          expect(await Migrator(db).apply([first, second]), [second.id]);
        });

        test(
          'baseline verifies existing schema and registers the fixed engine',
          () async {
            final first = initial();
            for (final command in createSchema([_items()], db.dialect)) {
              await db.execute(command);
            }
            expect(
              (await Migrator(
                db,
              ).baseline([first], expected: first.snapshot!)).matches,
              true,
            );
            expect(
              (await Migrator(db).history()).single.checksum,
              first.checksum,
            );
          },
        );
      },
      skip: address == null
          ? 'Set $variable to a disposable database with CREATE DATABASE privileges.'
          : false,
    );
  }
}

final class _FaultDriver implements Driver<Backend> {
  final Driver<Backend> inner;
  bool failAfterDdl = false, failDmlCheckpoint = false;
  bool failAfterDmlCommit = false, commitFailureArmed = false;
  int alterCount = 0;
  _FaultDriver(this.inner);
  @override
  Capabilities get capabilities => inner.capabilities;
  @override
  Future<R> run<R>(Future<R> Function(SqlConnection) action) =>
      inner.run((connection) => action(_FaultConnection(this, connection)));
  @override
  Future<void> close() => inner.close();
}

final class _FaultConnection implements SqlConnection {
  final _FaultDriver driver;
  final SqlConnection inner;
  _FaultConnection(this.driver, this.inner);
  @override
  bool? get transactionActive => inner.transactionActive;
  @override
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    if (driver.failDmlCheckpoint &&
        command.sql.contains('INSERT INTO "_orm_migration_steps"') &&
        command.parameters.length == 7 &&
        command.parameters[3] == 'complete') {
      driver.failDmlCheckpoint = false;
      throw StateError('injected checkpoint failure before submission');
    }
    final result = await inner.execute(command, options: options);
    if (driver.failAfterDmlCommit && command.sql.startsWith('UPDATE items')) {
      driver.commitFailureArmed = true;
    }
    if (command.sql == 'COMMIT' && driver.commitFailureArmed) {
      driver.failAfterDmlCommit = false;
      driver.commitFailureArmed = false;
      throw StateError('injected lost commit acknowledgement');
    }
    if (command.sql.startsWith('ALTER TABLE')) {
      driver.alterCount++;
      if (driver.failAfterDdl) {
        driver.failAfterDdl = false;
        throw StateError('injected lost DDL acknowledgement');
      }
    }
    return result;
  }

  @override
  Future<SqlCursor> openCursor(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) => inner.openCursor(command, options: options);
  @override
  Future<void> invalidate() => inner.invalidate();
}
