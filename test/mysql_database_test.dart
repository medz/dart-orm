import 'dart:io';

import 'package:orm/mysql.dart';
import 'package:orm/mariadb.dart';
import 'package:test/test.dart';

final _id = Column('id', Codecs.integer, generated: true);
final _name = Column('name', Codecs.text);
final _json = Column('data', Codecs.jsonDocument.nullable(), nullable: true);
final _amount = Column(
  'amount',
  Codecs.decimal,
  decimalPrecision: 30,
  decimalScale: 6,
);
final _created = Column('created_at', Codecs.dateTime, temporalPrecision: 6);
final _big = Column('large_integer', Codecs.bigint, defaultSql: '0');
final _schema = TableSchema(
  'orm_typed_rows',
  columns: [_id, _name, _json, _amount, _created, _big],
  primaryKey: ['id'],
  uniqueKeys: [
    ['name'],
  ],
);

final class _Fields(super.table) extends Fields {
  late final id = column(_id);
  late final name = column(_name);
  late final data = column(_json);
  late final amount = column(_amount);
  late final created = column(_created);
  late final big = column(_big);
}

typedef _Row = (int, String, SqlJson?, Decimal, DateTime);
final _table = Table<_Row, _Fields>(
  _schema,
  _Fields.new,
  (f) => (f.id, f.name, f.data, f.amount, f.created).row,
);

void main() {
  for (final engine in ['mysql', 'mariadb']) {
    final variable = 'ORM_TEST_${engine.toUpperCase()}';
    final address = Platform.environment[variable];
    final tls = MysqlTls.values.byName(
      Platform.environment['${variable}_TLS'] ?? 'verifyFull',
    );
    group(
      engine,
      () {
        late Database<Backend> db;
        final events = <QueryEvent>[];
        final instant = DateTime.utc(2026, 9, 19, 1, 2, 3, 0, 1);
        Future<_Row> create(String name, {SqlJson? data}) => db
            .table(_table)
            .createRow(
              (r) => [
                r.name.set(name),
                r.data.set(data),
                r.amount.set(Decimal.parse('9007199254740993.000001')),
                r.created.set(instant),
              ],
            );
        setUp(() async {
          db = engine == 'mysql'
              ? await mysql(
                  MysqlOptions(url: Uri.parse(address!), tls: tls),
                  onQuery: events.add,
                )
              : await mariadb(
                  MariadbOptions(url: Uri.parse(address!), tls: tls),
                  onQuery: events.add,
                );
          await db.execute(SqlCommand('DROP TABLE IF EXISTS orm_typed_rows'));
          await db.execute(
            SqlCommand(
              'CREATE TABLE orm_typed_rows (id BIGINT PRIMARY KEY AUTO_INCREMENT, name VARCHAR(255) NOT NULL UNIQUE, data JSON NULL, amount DECIMAL(30,6) NOT NULL, created_at DATETIME(6) NOT NULL, large_integer DECIMAL(65,0) NOT NULL DEFAULT 0)',
            ),
          );
          events.clear();
        });
        tearDown(() async {
          await db.execute(SqlCommand('DROP TABLE IF EXISTS orm_typed_rows'));
          await db.close();
        });
        test(
          'create returns exact values on its transaction connection',
          () async {
            final row = await create('one', data: const SqlJson({'n': 1}));
            expect(row.$1, 1);
            expect(row.$2, 'one');
            expect(row.$3!.value, {'n': 1});
            expect(row.$4.toString(), '9007199254740993.000001');
            expect(row.$5, instant);
            expect(events.where((e) => e.sql.startsWith('INSERT')).length, 1);
            expect(events.where((e) => e.sql.startsWith('SELECT')).length, 1);
          },
        );
        test(
          'JSON null, SQL NULL and parameter comparison stay distinct',
          () async {
            await create('sql-null');
            await create('json-null', data: const SqlJson(null));
            await create('object', data: const SqlJson({'n': 1}));
            final rows = await db
                .table(_table)
                .orderBy((r) => [r.id.asc()])
                .get();
            expect(rows[0].$3, null);
            expect(rows[1].$3, isA<SqlJson>());
            expect(rows[1].$3!.value, null);
            final matching = await db
                .table(_table)
                .where((r) => r.data.eq(const SqlJson({'n': 1})))
                .select((r) => r.name)
                .get();
            expect(matching, ['object']);
            final cte = db
                .table(_table)
                .select((r) => (r.name, r.data).row)
                .asCte('docs');
            final throughCte = await cte.query
                .where((r) => r.ref((f) => f.data).eq(const SqlJson({'n': 1})))
                .get();
            expect(throughCte.single.$1, 'object');
          },
        );
        test(
          'rollback and savepoint preserve explicit transaction boundaries',
          () async {
            await expectLater(
              db.transaction((tx) async {
                await tx
                    .table(_table)
                    .insert(
                      (r) => [
                        r.name.set('rollback'),
                        r.amount.set(Decimal.parse('1')),
                        r.created.set(instant),
                      ],
                    )
                    .execute();
                throw StateError('rollback');
              }),
              throwsStateError,
            );
            expect(await db.table(_table).count(), 0);
            await db.transaction((tx) async {
              await tx
                  .table(_table)
                  .insert(
                    (r) => [
                      r.name.set('keep'),
                      r.amount.set(Decimal.parse('1')),
                      r.created.set(instant),
                    ],
                  )
                  .execute();
              await expectLater(
                tx.savepoint((nested) async {
                  await nested
                      .table(_table)
                      .insert(
                        (r) => [
                          r.name.set('discard'),
                          r.amount.set(Decimal.parse('2')),
                          r.created.set(instant),
                        ],
                      )
                      .execute();
                  throw StateError('savepoint');
                }),
                throwsStateError,
              );
            });
            expect(await db.table(_table).select((r) => r.name).get(), [
              'keep',
            ]);
          },
        );
        test(
          'exact composite relation keys and BigInt avoid float coercion',
          () async {
            for (final key in ['9007199254740992', '9007199254740993']) {
              await db
                  .table(_table)
                  .insert(
                    (r) => [
                      r.name.set(key),
                      r.amount.set(Decimal.parse(key)),
                      r.created.set(instant),
                      r.big.set(BigInt.parse(key)),
                    ],
                  )
                  .execute();
            }
            final names = await db
                .table(_table)
                .where((r) => r.big.eq(BigInt.parse('9007199254740993')))
                .select((r) => r.name)
                .get();
            expect(names, ['9007199254740993']);
            events.clear();
            final matches = await db
                .table(_table)
                .orderBy((r) => [r.id.asc()])
                .select(
                  (r) => (
                    r.name,
                    Relation(
                      _table,
                      parent: [r.amount, r.created],
                      child: (c) => [c.amount, c.created],
                    ).select((c) => c.name).many(),
                  ).map((name, related) => (name, related)),
                )
                .get();
            expect(matches.map((r) => r.$2), [
              ['9007199254740992'],
              ['9007199254740993'],
            ]);
            expect(events.where((e) => e.sql.startsWith('SELECT')).length, 2);
          },
        );
        test('JSON DISTINCT through a CTE retains native comparison', () async {
          await create('first', data: const SqlJson({'n': 1}));
          await create('second', data: const SqlJson({'n': 1}));
          final result = await db
              .table(_table)
              .select((r) => r.data)
              .distinct()
              .asCte('distinct_docs')
              .query
              .get();
          expect(result.single!.value, {'n': 1});
          final union = await db
              .table(_table)
              .where((r) => r.name.eq('first'))
              .select((r) => r.data)
              .union(
                db
                    .table(_table)
                    .where((r) => r.name.eq('second'))
                    .select((r) => r.data),
              )
              .get();
          expect(union.single!.value, {'n': 1});
        });
        test(
          'decimal column overflow fails instead of storing a clamped value',
          () async {
            await expectLater(
              db
                  .table(_table)
                  .insert(
                    (r) => [
                      r.name.set('overflow'),
                      r.amount.set(Decimal.parse('9999999999999999999999999')),
                      r.created.set(instant),
                    ],
                  )
                  .execute(),
              throwsA(isA<SqlFailure>()),
            );
            expect(await db.table(_table).count(), 0);
          },
        );
        test('duplicate update uses native unique key semantics', () async {
          await create('one');
          await db
              .table(_table)
              .insert(
                (r) => [
                  r.name.set('one'),
                  r.amount.set(Decimal.parse('2')),
                  r.created.set(instant),
                ],
              )
              .onDuplicateKeyUpdate(
                set: (existing, incoming) => [
                  existing.amount.setExpression(incoming.amount),
                ],
              )
              .execute();
          expect((await db.table(_table).single()).$4.toString(), '2');
        });
        test('named SQL handles MySQL comments, quoted identifiers and repeated values', () async {
          final template = SqlTemplate(
            "SELECT :n + :n AS `n:quoted`, ':literal' AS s # :ignored\n",
            dialect: db.dialect,
          );
          final command = template.compile(db.capabilities, {
            'n': value(3, Codecs.integer),
          });
          expect(command.parameters, [3, 3]);
          final result = await db.sql.execute(command);
          expect(result.rows.single, [6, ':literal']);
        });
      },
      skip: address == null
          ? 'Set $variable for live database validation.'
          : false,
    );
  }
}
