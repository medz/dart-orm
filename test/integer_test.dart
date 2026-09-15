import 'dart:io';

import 'package:orm/generate.dart';
import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import 'support/integers/schema.orm.dart';
import 'support/integers/schema.snapshot.dart' as physical;

void main() {
  for (final backend in [
    'sqlite',
    if (Platform.environment.containsKey('ORM_TEST_POSTGRES')) 'postgres',
  ]) {
    group('integer widths $backend', () {
      late Database<Backend> db;
      setUp(() async {
        if (backend == 'sqlite') {
          db = await sqlite(const SqliteOptions.memory());
        } else {
          db = postgres(
            PostgresOptions(
              url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
              tls: .disable,
              schema: 'orm_integer_tests',
            ),
          );
          await db.execute(
            SqlCommand('DROP SCHEMA IF EXISTS orm_integer_tests CASCADE'),
          );
          await db.execute(SqlCommand('CREATE SCHEMA orm_integer_tests'));
        }
      });
      tearDown(() => db.close());
      Future<void> create() => Migrator(db).apply([
        Migration.create('0001_samples', appSchema, dialect: db.dialect),
      ]);

      test('storage bounds, nulls and wider sums keep the normal integer value codec', () async {
        await create();
        final a = await db.samples.create(
          small: 32767,
          medium: 2147483647,
          large: 9007199254740993,
        );
        final b = await db.samples.create(
          small: 32767,
          medium: 2147483647,
          large: -9007199254740993,
          optional: -32768,
        );
        expect(a.optional, null);
        expect(b.optional, -32768);
        final sums = await db.samples
            .select((s) => (s.small.sum(), s.medium.sum(), s.large.sum()).row)
            .single();
        expect(sums, (65534, 4294967294, 0));
        expect((await db.samples.byId(a.id).single()).large, 9007199254740993);
        for (final values in [
          (32768, 0),
          (-32769, 0),
          (0, 2147483648),
          (0, -2147483649),
        ]) {
          await expectLater(
            db.samples.create(small: values.$1, medium: values.$2, large: 0),
            throwsA(isA<SqlFailure>()),
          );
        }
        expect(await db.samples.count(), 2);
        await expectLater(
          db.execute(SqlCommand('UPDATE samples SET small = 32768')),
          throwsA(isA<SqlFailure>()),
        );
        expect(
          (await verifySchema(db, SchemaSnapshot(appSchema))).differences,
          isEmpty,
        );
        final info = await inspectTable(db, 'samples');
        expect(info.columns.map((c) => c.integerBits).toList(), [
          32,
          16,
          32,
          64,
          16,
        ]);
        expect(info.unmanaged, isEmpty);
      });

      test('relations, union and cursors share int expressions across physical widths', () async {
        await create();
        final a = await db.samples.create(small: 10, medium: 20, large: 30);
        await db.owners.create(id: 1, sampleId: a.id);
        expect(
          await db.owners
              .select((o) => o.sample.select((s) => s.small).required())
              .single(),
          10,
        );
        final set = db.samples
            .select((s) => s.small)
            .unionAll(db.samples.select((s) => s.medium));
        expect(await set.get(), unorderedEquals([10, 20]));
        final values = await db.samples.orderBy((s) => [s.id.asc()]).get();
        expect(values.single.id, a.id);
        final stream = await set.stream().toList();
        expect(stream, unorderedEquals([10, 20]));
        final b = await db.samples.create(small: 11, medium: 21, large: 31);
        final token = db.samples.cursorToken((s) => [s.id.cursor(a.id)]);
        expect(
          (await db.samples
                  .seekToken(token, orderBy: (s) => [s.id.asc()])
                  .single())
              .id,
          b.id,
        );
      });

      test(
        'defaulted and quoted columns retain enforced nullable bounds',
        () async {
          final table = TableSchema(
            'quoted',
            columns: [
              Column('id', Codecs.integer, generated: true, integerBits: 16),
              Column(
                'a"b CHECK(1)',
                Codecs.integer,
                integerBits: 16,
                defaultSql: '7',
              ),
              Column(
                'optional',
                Codecs.integer.nullable(),
                nullable: true,
                integerBits: 32,
              ),
            ],
            primaryKey: ['id'],
          );
          await Migrator(db).apply([
            Migration.create('0001_quoted', [table], dialect: db.dialect),
          ]);
          await db.execute(SqlCommand('INSERT INTO quoted DEFAULT VALUES'));
          expect(
            (await db.execute(
              SqlCommand('SELECT "a""b CHECK(1)", optional FROM quoted'),
            )).rows,
            [
              [7, null],
            ],
          );
          expect(
            (await verifySchema(db, SchemaSnapshot([table]))).differences,
            isEmpty,
          );
          expect((await inspectTable(db, 'quoted')).unmanaged, isEmpty);
          await expectLater(
            db.execute(SqlCommand('UPDATE quoted SET "a""b CHECK(1)" = 32768')),
            throwsA(isA<SqlFailure>()),
          );
        },
      );

      test('Dart snapshots and imports retain widths without confusing value codecs', () async {
        await create();
        final snapshot = SchemaSnapshot(appSchema);
        final restored = physical.schema;
        expect(restored.checksum, snapshot.checksum);
        final imported = await importSchema(db);
        expect(imported.issues, isEmpty);
        expect(imported.dart, contains('@IntegerBits(16)'));
        expect(imported.dart, contains('@IntegerBits(32)'));
        final directory = await Directory(
          '.dart_tool/orm-integer-import-$backend',
        ).create(recursive: true);
        try {
          final file = File('${directory.path}/schema.dart');
          await file.writeAsString(imported.dart);
          final result = await generateSchema(file.path);
          expect(
            (await verifySchema(db, result.snapshot)).differences,
            isEmpty,
          );
        } finally {
          await directory.delete(recursive: true);
        }
      });

      TableSchema sized(int? bits, {String column = 'value'}) => TableSchema(
        'sized',
        columns: [
          Column('id', Codecs.integer),
          Column(column, Codecs.integer, integerBits: bits),
        ],
        primaryKey: ['id'],
      );
      test('widening and narrowing use reviewed conversions with atomic failure recovery', () async {
        final first = Migration.create('0001_sized', [
          sized(16),
        ], dialect: db.dialect);
        await Migrator(db).apply([first]);
        await db.execute(
          SqlCommand('INSERT INTO sized(id, value) VALUES (1, 32767)'),
        );
        final wider = Migration.diff(
          '0002_wider',
          from: first.snapshot!,
          to: SchemaSnapshot([sized(32)]),
          previous: first.checksum,
          using: {
            'sized': {'value': 'value'},
          },
          dialect: db.dialect,
        );
        await Migrator(db).apply([first, wider]);
        await db.execute(
          SqlCommand('INSERT INTO sized(id, value) VALUES (2, 32768)'),
        );
        final narrow = Migration.diff(
          '0003_narrow',
          from: wider.snapshot!,
          to: SchemaSnapshot([sized(16)]),
          previous: wider.checksum,
          using: {
            'sized': {'value': 'value'},
          },
          dialect: db.dialect,
        );
        await expectLater(
          Migrator(db).apply([first, wider, narrow]),
          throwsA(isA<SqlFailure>()),
        );
        expect((await Migrator(db).history()).length, 2);
        expect((await verifySchema(db, wider.snapshot!)).differences, isEmpty);
        expect(
          (await db.execute(SqlCommand('SELECT count(*) FROM sized')))
              .rows
              .single
              .single,
          2,
        );
        await db.execute(SqlCommand('DELETE FROM sized WHERE id = 2'));
        await Migrator(db).apply([first, wider, narrow]);
        expect((await verifySchema(db, narrow.snapshot!)).differences, isEmpty);
        if (backend == 'sqlite') {
          expect(
            (await db.execute(SqlCommand('PRAGMA foreign_keys')))
                .rows
                .single
                .single,
            1,
          );
        }
      });

      test(
        'column renames preserve width metadata and range constraints',
        () async {
          final first = Migration.create('0001_sized', [
            sized(16),
          ], dialect: db.dialect);
          await Migrator(db).apply([first]);
          final renamed = Migration.diff(
            '0002_renamed',
            from: first.snapshot!,
            to: SchemaSnapshot([sized(16, column: 'new_value')]),
            previous: first.checksum,
            renames: const SchemaRenames(
              columns: {
                'sized': {'value': 'new_value'},
              },
            ),
            dialect: db.dialect,
          );
          await Migrator(db).apply([first, renamed]);
          expect(
            (await verifySchema(db, renamed.snapshot!)).differences,
            isEmpty,
          );
          await expectLater(
            db.execute(
              SqlCommand('INSERT INTO sized(id, new_value) VALUES (1, 32768)'),
            ),
            throwsA(isA<SqlFailure>()),
          );
        },
      );

      test(
        'historical bounded backfills verify widths and resume normally',
        () async {
          final table = TableSchema(
            'sized',
            columns: [
              Column('id', Codecs.integer, integerBits: 16),
              Column('value', Codecs.integer, integerBits: 32),
            ],
            primaryKey: ['id'],
          );
          final first = Migration.create('0001_sized', [
            table,
          ], dialect: db.dialect);
          await Migrator(db).apply([first]);
          for (var i = 1; i <= 4; i++) {
            await db.execute(
              SqlCommand('INSERT INTO sized(id, value) VALUES ($i, 0)'),
            );
          }
          final second = Migration.steps(
            '0002_backfill',
            [
              Backfill(
                table,
                set: {'value': 'value + 1'},
                doneWhen:
                    'SELECT NOT EXISTS(SELECT 1 FROM sized WHERE value <> 1)',
                batchSize: 2,
              ),
            ],
            previous: first.checksum,
            dialect: db.dialect,
          );
          await Migrator(db).apply([first, second], maxBackfillBatches: 1);
          expect((await Migrator(db).progress()).single.backfill!.rows, 2);
          await Migrator(db).apply([first, second]);
          expect((await Migrator(db).progress()).single.backfill!.rows, 4);
        },
      );

      test('changing an identity width preserves generation and rejects out-of-range explicit IDs', () async {
        TableSchema identity(int bits) => TableSchema(
          'identities',
          columns: [
            Column('id', Codecs.integer, generated: true, integerBits: bits),
          ],
          primaryKey: ['id'],
        );
        final first = Migration.create('0001_identity', [
          identity(32),
        ], dialect: db.dialect);
        await Migrator(db).apply([first]);
        await db.execute(SqlCommand('INSERT INTO identities DEFAULT VALUES'));
        final narrow = Migration.diff(
          '0002_identity',
          from: first.snapshot!,
          to: SchemaSnapshot([identity(16)]),
          previous: first.checksum,
          using: {
            'identities': {'id': 'id'},
          },
          dialect: db.dialect,
        );
        await Migrator(db).apply([first, narrow]);
        await db.execute(SqlCommand('INSERT INTO identities DEFAULT VALUES'));
        expect(
          (await db.execute(
            SqlCommand('SELECT id FROM identities ORDER BY id'),
          )).rows,
          [
            [1],
            [2],
          ],
        );
        await expectLater(
          db.execute(SqlCommand('INSERT INTO identities(id) VALUES (32768)')),
          throwsA(isA<SqlFailure>()),
        );
        expect((await verifySchema(db, narrow.snapshot!)).differences, isEmpty);
        if (backend == 'postgres') {
          final sequence = await db.execute(
            SqlCommand(
              "SELECT seqtypid::regtype::text FROM pg_sequence WHERE seqrelid = pg_get_serial_sequence('identities', 'id')::regclass",
            ),
          );
          expect(sequence.rows.single.single, 'smallint');
        }
      });

      if (backend == 'sqlite') {
        test('quoted defaults and comments cannot masquerade as managed range checks', () async {
          final check =
              '"value" IS NULL OR (typeof("value") = \'integer\' AND "value" BETWEEN -32768 AND 32767)';
          await db.execute(
            SqlCommand(
              "CREATE TABLE sized(id INTEGER PRIMARY KEY NOT NULL, value INTEGER NOT NULL, note TEXT DEFAULT ('CHECK (${check.replaceAll("'", "''")})')) /* CHECK ($check) */",
            ),
          );
          final info = await inspectTable(db, 'sized');
          expect(
            info.columns.singleWhere((c) => c.name == 'value').integerBits,
            64,
          );
          expect(
            (await verifySchema(db, SchemaSnapshot([sized(16)]))).differences,
            contains('sized.value integer width differs'),
          );
          await db.execute(
            SqlCommand('INSERT INTO sized(id, value) VALUES (1, 32768)'),
          );
        });
        test('extra weaker expressions remain unmanaged and cannot claim a narrower width', () async {
          await db.execute(
            SqlCommand(
              'CREATE TABLE sized (id INTEGER PRIMARY KEY NOT NULL, value INTEGER CHECK ("value" IS NULL OR (typeof("value") = \'integer\' AND "value" BETWEEN -32768 AND 32767) OR 1))',
            ),
          );
          final info = await inspectTable(db, 'sized');
          expect(info.columns.last.integerBits, 64);
          expect(info.checks.single.expression, endsWith('OR 1'));
          final verification = await verifySchema(
            db,
            SchemaSnapshot([sized(16)]),
          );
          expect(
            verification.differences,
            contains('sized.value integer width differs'),
          );
          expect(verification.unmanaged.map((o) => o.kind), contains('check'));
        });
      }
    });
  }

  test('analyzer validates width annotations and integer-backed domain codecs', () async {
    final directory = await Directory('.dart_tool/orm-integer-source')
        .create(recursive: true);
    try {
      final source = File('${directory.path}/schema.dart');
      for (final declaration in [
        '@IntegerBits(8) int id',
        '@IntegerBits(32) String id',
        '@IntegerBits(16) @IntegerBits(32) int id',
      ]) {
        await source.writeAsString(
          "import 'package:orm/schema.dart';\ntypedef Row = ({$declaration});\nfinal rows = entity<Row>();",
        );
        await expectLater(
          generateSchema(source.path),
          throwsA(isA<GenerationException>()),
        );
      }
      await source.writeAsString('''import 'package:orm/schema.dart';
extension type Identifier(int value) {}
Identifier decode(Object? value) => Identifier(value as int);
int encode(Identifier value) => value.value;
const idCodec = Codec<Identifier>.integer(decode, encode);
typedef Row = ({@IntegerBits(16) @UseCodec(idCodec) Identifier id});
final rows = entity<Row>();
''');
      final generated = await generateSchema(source.path);
      final column = generated.snapshot.tables.single.columns.single;
      expect(column.integerBits, 16);
      expect(column.codec.sqlType, 'integer');
      expect(generated.dart, contains('integerBits: 16'));
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('width declarations reject wrong kinds and ranges without changing default snapshots', () {
    for (final bits in [0, 8, 128]) {
      expect(
        () => SchemaSnapshot([
          TableSchema(
            't',
            columns: [Column('id', Codecs.integer, integerBits: bits)],
          ),
        ]),
        throwsA(isA<OrmException>()),
      );
    }
    expect(
      () => SchemaSnapshot([
        TableSchema(
          't',
          columns: [Column('name', Codecs.text, integerBits: 16)],
        ),
      ]),
      throwsA(isA<OrmException>()),
    );
    final implicit = SchemaSnapshot([
      TableSchema('t', columns: [Column('id', Codecs.integer)]),
    ]);
    final explicit = SchemaSnapshot([
      TableSchema(
        't',
        columns: [Column('id', Codecs.integer, integerBits: 64)],
      ),
    ]);
    expect(implicit.checksum, explicit.checksum);
    final change = Migration.diff(
      '0001_same',
      from: implicit,
      to: explicit,
      dialect: SqlDialect.sqlite,
    );
    expect(change.steps.isEmpty, true);
    expect(
      () => Migration.diff(
        '0001_wider',
        from: implicit,
        to: SchemaSnapshot([
          TableSchema(
            't',
            columns: [Column('id', Codecs.integer, integerBits: 16)],
          ),
        ]),
        dialect: SqlDialect.sqlite,
      ),
      throwsA(isA<OrmException>()),
    );
  });
}
