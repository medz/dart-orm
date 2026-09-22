import 'dart:io';

import 'package:orm/generate.dart';
import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';
import 'package:test/test.dart' as matchers show allOf;

import 'support/precision/schema.orm.dart';
import 'support/precision/schema.snapshot.dart' as physical;

Decimal d(String value) => Decimal.parse(value);

void main() {
  for (final backend in [
    'sqlite',
    if (Platform.environment.containsKey('ORM_TEST_POSTGRES')) 'postgres',
  ]) {
    group('decimal precision $backend', () {
      late Database<Backend> db;
      setUp(() async {
        if (backend == 'sqlite') {
          db = await sqlite(const SqliteOptions.memory());
        } else {
          db = postgres(
            PostgresOptions(
              url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
              tls: .disable,
              schema: 'orm_precision_tests',
            ),
          );
          await db.execute(
            SqlCommand('DROP SCHEMA IF EXISTS orm_precision_tests CASCADE'),
          );
          await db.execute(SqlCommand('CREATE SCHEMA orm_precision_tests'));
        }
      });
      tearDown(() => db.close());
      Future<void> create() => Migrator(db.sql).apply([
        Migration.create('0001_precision', appSchema, dialect: db.dialect),
      ]);

      test('column coercion rounds signed ties and handles negative and excess scales', () async {
        await create();
        final a = await db.wallet.create(
          amount: d('123.455'),
          hundreds: d('12350'),
          fraction: d('.001235'),
        );
        expect(
          (a.amount, a.hundreds, a.fraction, a.defaulted, a.optional),
          (d('123.46'), d('12400'), d('.00124'), d('1.24'), null),
        );
        final b = await db.wallet.create(
          amount: d('-123.455'),
          hundreds: d('-12350'),
          fraction: d('-.001235'),
          optional: d('-1.235'),
        );
        expect(
          (b.amount, b.hundreds, b.fraction, b.optional),
          (d('-123.46'), d('-12400'), d('-.00124'), d('-1.24')),
        );
        final zero = await db.wallet.create(
          amount: Decimal.zero,
          hundreds: Decimal.zero,
          fraction: Decimal.zero,
        );
        expect(zero.fraction, Decimal.zero);
        for (final values in [
          ('999.995', '0', '0'),
          ('0', '99950', '0'),
          ('0', '0', '.009995'),
        ]) {
          await expectLater(
            db.wallet.create(
              amount: d(values.$1),
              hundreds: d(values.$2),
              fraction: d(values.$3),
            ),
            throwsA(isA<SqlFailure>()),
          );
        }
        expect(await db.wallet.count(), 3);
      });

      test('writes constrain columns while arithmetic and wider aggregates retain their result precision', () async {
        await create();
        final a = await db.wallet.create(
          amount: d('999.994'),
          hundreds: d('99949'),
          fraction: d('.009994'),
        );
        await db.wallet.create(
          amount: d('999.99'),
          hundreds: Decimal.zero,
          fraction: Decimal.zero,
        );
        expect(
          await db.wallet.select((w) => w.amount.sum()).single(),
          d('1999.98'),
        );
        expect(
          await db.wallet
              .select((w) => w.amount.sum().constrained(6, 1))
              .single(),
          d('2000'),
        );
        expect(
          await db.wallet
              .where((w) => w.amount.constrained(6, 0).eq(.value(d('1000'))))
              .count(),
          2,
        );
        final rounded = db.wallet
            .select((w) => w.amount.constrained(5, 1))
            .asCte('rounded');
        expect(
          await rounded.query
              .select((c) => c.ref((w) => w.amount.constrained(5, 1)))
              .get(),
          [d('1000'), d('1000')],
        );
        expect(
          await db.wallet
              .byId(a.id)
              .select((w) => w.amount.times(d('1000')))
              .single(),
          d('999990'),
        );
        await expectLater(
          db.wallet
              .byId(a.id)
              .update((w) => [w.amount.setExpression(w.amount.plus(d('.005')))])
              .execute(),
          throwsA(isA<SqlFailure>()),
        );
        expect((await db.wallet.byId(a.id).single()).amount, d('999.99'));
        await db.wallet
            .byId(a.id)
            .patch(
              amount: Change.set(d('1.235')),
              optional: Change.set(d('2.225')),
            );
        expect((await db.wallet.byId(a.id).single()).amount, d('1.24'));
        await db.wallet.byId(a.id).patch(optional: const Change.set(null));
        expect((await db.wallet.byId(a.id).single()).optional, null);
      });

      test(
        'batch inserts and upserts use column coercion and roll back as a unit',
        () async {
          await create();
          final ids = await db.price
              .insertMany([
                '1.234',
                '2.345',
              ], (p, v) => [p.id.set(d(v)), p.label.set(v)])
              .returning((p) => p.id)
              .get();
          expect(ids, [d('1.23'), d('2.35')]);
          await db.price
              .insert((p) => [p.id.set(d('1.234')), p.label.set('updated')])
              .onConflictUpdate(
                target: (p) => [p.id],
                set: (old, incoming) => [
                  old.label.setExpression(incoming.label),
                ],
              )
              .execute();
          expect((await db.price.byId(d('1.23')).single()).label, 'updated');
          await expectLater(
            db.price.insertMany([
              '3.456',
              '99.995',
            ], (p, v) => [p.id.set(d(v)), p.label.set(v)]).execute(),
            throwsA(isA<SqlFailure>()),
          );
          expect(await db.price.count(), 2);
          final child = await db.receipt.create(priceId: d('1.234'));
          expect(child.priceId, d('1.23'));
          expect(
            await db.receipt
                .select((r) => r.price.select((p) => p.label).required())
                .single(),
            'updated',
          );
        },
      );

      test('catalogs snapshots and imported declarations retain precision scale and defaults', () async {
        await create();
        final snapshot = SchemaSnapshot(appSchema);
        expect(physical.schema.checksum, snapshot.checksum);
        final verification = await verifySchema(db.sql, snapshot);
        expect(verification.differences, isEmpty);
        expect(verification.unmanaged, isEmpty);
        expect(await verifyColumns(db.sql, appSchema), isEmpty);
        final info = await inspectTable(db.sql, 'wallets');
        expect(info.columns.map((c) => (c.decimalPrecision, c.decimalScale)), [
          (null, null),
          (5, 2),
          (3, -2),
          (3, 5),
          (5, 2),
          (5, 2),
        ]);
        final draft = await importSchema(db.sql);
        expect(draft.issues, isEmpty);
        expect(
          draft.dart,
          matchers.allOf(contains('precision: 3'), contains('scale: -2')),
        );
        final dir = await Directory('.dart_tool/orm-precision-import-$backend')
            .create(recursive: true);
        try {
          final file = File('${dir.path}/schema.dart');
          await file.writeAsString(draft.dart);
          final generated = await generateSchema(file.path);
          final check = await verifySchema(db.sql, generated.snapshot);
          expect(check.differences, isEmpty);
        } finally {
          await dir.delete(recursive: true);
        }
      });

      test('reviewed scale reduction detects rounded duplicate keys and rolls back schema history', () async {
        TableSchema sized(int scale) => TableSchema(
          'sized',
          columns: [
            Column('id', Codecs.integer),
            Column(
              'amount',
              Codecs.decimal,
              decimalPrecision: 5,
              decimalScale: scale,
            ),
          ],
          primaryKey: ['id'],
          uniqueKeys: [
            ['amount'],
          ],
        );
        final first = Migration.create('0001_sized', [
          sized(3),
        ], dialect: db.dialect);
        await Migrator(db.sql).apply([first]);
        await db.execute(
          SqlCommand("INSERT INTO sized VALUES (1, '1.231'), (2, '1.234')"),
        );
        final next = Migration.diff(
          '0002_scale',
          from: first.snapshot!,
          to: SchemaSnapshot([sized(2)]),
          previous: first.checksum,
          using: {
            'sized': {'amount': 'amount'},
          },
          dialect: db.dialect,
        );
        await expectLater(
          Migrator(db.sql).apply([first, next]),
          throwsA(isA<SqlFailure>()),
        );
        expect((await Migrator(db.sql).history()).length, 1);
        expect(
          (await verifySchema(db.sql, first.snapshot!)).differences,
          isEmpty,
        );
        await db.execute(SqlCommand('DELETE FROM sized WHERE id = 2'));
        await Migrator(db.sql).apply([first, next]);
        expect(
          (await verifySchema(db.sql, next.snapshot!)).differences,
          isEmpty,
        );
        expect(
          Codecs.decimal.decode(
            (await db.execute(SqlCommand('SELECT amount FROM sized')))
                .rows
                .single
                .single,
          ),
          d('1.23'),
        );
      });

      test('physical renames and changing constrained defaults preserve column contracts', () async {
        TableSchema schema(
          String column,
          int precision,
          int scale,
          String value,
        ) => TableSchema(
          'renamed',
          columns: [
            Column('id', Codecs.integer),
            Column(
              column,
              Codecs.decimal,
              decimalPrecision: precision,
              decimalScale: scale,
              defaultSql: value,
            ),
          ],
          primaryKey: ['id'],
        );
        final first = Migration.create('0001_before', [
          schema('amount', 5, 3, "'1.2345'"),
        ], dialect: db.dialect);
        await Migrator(db.sql).apply([first]);
        await db.execute(SqlCommand('INSERT INTO renamed (id) VALUES (1)'));
        final next = Migration.diff(
          '0002_after',
          from: first.snapshot!,
          to: SchemaSnapshot([schema('price', 6, 2, "'2.345'")]),
          previous: first.checksum,
          renames: const SchemaRenames(
            columns: {
              'renamed': {'amount': 'price'},
            },
          ),
          using: {
            'renamed': {'price': 'price'},
          },
          dialect: db.dialect,
        );
        await Migrator(db.sql).apply([first, next]);
        await db.execute(SqlCommand('INSERT INTO renamed (id) VALUES (2)'));
        final rows = await db.execute(
          SqlCommand('SELECT price FROM renamed ORDER BY id'),
        );
        expect(rows.rows.map((r) => Codecs.decimal.decode(r.single)), [
          d('1.24'),
          d('2.35'),
        ]);
        final check = await verifySchema(db.sql, next.snapshot!);
        expect(check.differences, isEmpty);
        expect(check.unmanaged, isEmpty);
      });

      test(
        'maximum declared precision and scale bounds remain exact',
        () async {
          final columns = [
            Column('id', Codecs.integer),
            Column(
              'large',
              Codecs.decimal,
              decimalPrecision: 1000,
              decimalScale: -1000,
            ),
            Column(
              'tiny',
              Codecs.decimal,
              decimalPrecision: 1,
              decimalScale: 1000,
            ),
          ];
          final schema = TableSchema(
            'bounds',
            columns: columns,
            primaryKey: ['id'],
          );
          await Migrator(db.sql).apply([
            Migration.create('0001_bounds', [schema], dialect: db.dialect),
          ]);
          final parameter = backend == 'sqlite' ? '?1' : r'$1';
          final parameter2 = backend == 'sqlite' ? '?2' : r'$2';
          await db.execute(
            SqlCommand(
              'INSERT INTO bounds VALUES (1, $parameter, $parameter2)',
              [d('9e1999').toString(), d('9e-1000').toString()],
            ),
          );
          final row = (await db.execute(
            SqlCommand('SELECT large, tiny FROM bounds'),
          )).rows.single;
          expect(row.map(Codecs.decimal.decode), [d('9e1999'), d('9e-1000')]);
          expect(
            (await verifySchema(db.sql, SchemaSnapshot([schema]))).differences,
            isEmpty,
          );
        },
      );

      test(
        'historical backfills retain constrained decimal key declarations',
        () async {
          await create();
          for (final n in ['1.234', '2.345', '3.456']) {
            await db.price.create(id: d(n), label: 'pending');
          }
          final first = Migration.create(
            '0001_precision',
            appSchema,
            dialect: db.dialect,
          );
          final next = Migration.steps(
            '0002_backfill',
            [
              Backfill(
                priceSchema,
                set: {'label': "'done'"},
                doneWhen: "SELECT NOT EXISTS(SELECT 1 FROM prices WHERE label <> 'done')",
                batchSize: 1,
              ),
            ],
            previous: first.checksum,
            dialect: db.dialect,
          );
          await Migrator(db.sql).apply([first, next], maxBackfillBatches: 1);
          await Migrator(db.sql).apply([first, next]);
          expect(
            await db.price.where((p) => p.label.eq(.value('done'))).count(),
            3,
          );
        },
      );
    }, tags: backend);
  }

  test('SQLite enforces stored precision and checks default coercion and trusted-schema behavior', () async {
    final db = await sqlite(const SqliteOptions.memory());
    try {
      final expected = TableSchema(
        'quoted',
        columns: [
          Column('id', Codecs.integer),
          Column(
            'a"b',
            Codecs.decimal,
            decimalPrecision: 5,
            decimalScale: 2,
            defaultSql: "printf('%s.%s', '1', '235')",
          ),
        ],
        primaryKey: ['id'],
      );
      await Migrator(db.sql).apply([
        Migration.create('0001_quoted', [expected], dialect: db.dialect),
      ]);
      await db.execute(SqlCommand('INSERT INTO quoted (id) VALUES (1)'));
      expect(
        Codecs.decimal.decode(
          (await db.execute(SqlCommand('SELECT "a""b" FROM quoted')))
              .rows
              .single
              .single,
        ),
        d('1.24'),
      );
      expect(
        (await verifySchema(db.sql, SchemaSnapshot([expected]))).differences,
        isEmpty,
      );
      final draft = await importSchema(db.sql, tables: ['quoted']);
      expect(draft.dart, contains("printf('%s.%s', '1', '235')"));
      for (final value in ['1.234', '1000', 'invalid', 'NaN']) {
        await expectLater(
          db.execute(SqlCommand('UPDATE quoted SET "a""b" = ?1', [value])),
          throwsA(isA<SqlFailure>()),
        );
      }
      await db.execute(SqlCommand('PRAGMA trusted_schema = OFF'));
      await expectLater(
        db.execute(SqlCommand('INSERT INTO quoted (id) VALUES (2)')),
        throwsA(isA<SqlFailure>()),
      );
      expect(
        (await db.execute(SqlCommand('PRAGMA trusted_schema')))
            .rows
            .single
            .single,
        0,
      );
      await db.execute(SqlCommand('PRAGMA trusted_schema = ON'));
      await db.execute(SqlCommand('INSERT INTO quoted (id) VALUES (2)'));
      final ddl = createSchema([
        TableSchema(
          'missing',
          columns: [
            Column('id', Codecs.integer),
            Column(
              'amount',
              Codecs.decimal,
              decimalPrecision: 5,
              decimalScale: 2,
              defaultSql: "'1.235'",
            ),
          ],
          primaryKey: ['id'],
        ),
      ], SqlDialect.sqlite).first.sql;
      await db.execute(
        SqlCommand(
          ddl.replaceFirst("orm_decimal_cast_v1('1.235', 5, 2)", "'1.235'"),
        ),
      );
      final table = TableSchema(
        'missing',
        columns: [
          Column('id', Codecs.integer),
          Column(
            'amount',
            Codecs.decimal,
            decimalPrecision: 5,
            decimalScale: 2,
            defaultSql: "'1.235'",
          ),
        ],
        primaryKey: ['id'],
      );
      expect(
        (await verifySchema(db.sql, SchemaSnapshot([table]))).differences,
        ['missing.amount default differs'],
      );
    } finally {
      await db.close();
    }
  }, tags: 'sqlite');

  test('generation validates precision and scale and retains custom decimal codec types', () async {
    final dir = await Directory('.dart_tool/orm-precision-validation')
        .create(recursive: true);
    try {
      final file = File('${dir.path}/schema.dart');
      for (final declaration in [
        'n: decimal(precision: 0)',
        'n: decimal(precision: 1001)',
        'n: decimal(precision: 2, scale: -1001)',
        'n: decimal(precision: 2, scale: 1001)',
        'n: custom(Codecs.integer, precision: 2)',
        'n: decimal(precision: 2, precision: 3)',
      ]) {
        await file.writeAsString(
          "import 'package:orm/schema.dart'; final row = model('rows', ($declaration,));",
        );
        await expectLater(
          generateSchema(file.path),
          throwsA(isA<GenerationException>()),
        );
      }
      await file.writeAsString("""
import 'package:orm/schema.dart';
extension type Money(Decimal value) {
  static const codec = Codec<Money>('decimal', decode, encode);
  static Money decode(Object? value) => Money(Codecs.decimal.decode(value));
  static String encode(Money value) => value.value.toString();
}
final row = model('rows', (n: custom(Money.codec, precision: 8, scale: 2),));
""");
      final generated = await generateSchema(file.path);
      expect(generated.dart, contains('Column<models.Money>'));
      expect(generated.dart, contains('decimalPrecision: 8'));
      expect(generated.dart, contains('decimalScale: 2'));
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test(
    'metadata rejects invalid precisions scales and non-decimal columns',
    () {
      for (final column in [
        Column('n', Codecs.decimal, decimalScale: 2),
        Column('n', Codecs.decimal, decimalPrecision: 0),
        Column('n', Codecs.decimal, decimalPrecision: 1001),
        Column('n', Codecs.decimal, decimalPrecision: 3, decimalScale: -1001),
        Column('n', Codecs.decimal, decimalPrecision: 3, decimalScale: 1001),
        Column('n', Codecs.integer, decimalPrecision: 3),
      ]) {
        expect(
          () => createSchema([
            TableSchema('invalid', columns: [column]),
          ], SqlDialect.sqlite),
          throwsA(isA<OrmException>()),
        );
      }
      final a = SchemaSnapshot([
        TableSchema(
          'a',
          columns: [Column('n', Codecs.decimal, decimalPrecision: 3)],
        ),
      ]);
      final b = SchemaSnapshot([
        TableSchema(
          'a',
          columns: [
            Column('n', Codecs.decimal, decimalPrecision: 3, decimalScale: 0),
          ],
        ),
      ]);
      expect(a.checksum, b.checksum);
    },
  );
}
