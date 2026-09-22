@Tags(['core'])
library;

import 'package:orm/orm.dart';
import 'package:test/test.dart';

final _id = Column('id', Codecs.integer, generated: true);
final _name = Column('name', Codecs.text.nullable(), nullable: true);
final _amount = Column('amount', Codecs.decimal);
final _document = Column('document', Codecs.jsonDocument);
final _time = Column('time', Codecs.time, temporalPrecision: 3);
final _schema = TableSchema(
  'review_items',
  columns: [_id, _name, _amount, _document, _time],
  primaryKey: ['id'],
);

final class _Fields(super.table) extends Fields {
  late final id = column(_id);
  late final name = column(_name);
  late final amount = column(_amount);
  late final document = column(_document);
  late final time = column(_time);
}

final _table = Table<(int, String?), _Fields>(
  _schema,
  _Fields.new,
  (r) => (r.id, r.name).row,
);

final class _PrecisionKeyFields<T>(super.table, this.definition)
    extends Fields {
  final Column<T> definition;
  late final key = column(definition);
}

Table<T, _PrecisionKeyFields<T>> _precisionKeyTable<T>(Column<T> key) => Table(
  TableSchema('precision_keys', columns: [key], primaryKey: ['key']),
  (table) => _PrecisionKeyFields(table, key),
  (fields) => fields.key,
);

void main() {
  for (final dialect in [SqlDialect.mysql, SqlDialect.mariadb]) {
    group('$dialect review regressions', () {
      test(
        'binding uses the explicit transaction and expires with it',
        () async {
          final driver = _Driver(dialect);
          driver.connection.result = (command) =>
              command.sql.startsWith('SELECT')
              ? const SqlResult([
                  [1, 'bound'],
                ])
              : const SqlResult([]);
          final db = Database(driver);
          final builder = SqlBuilder(dialect);
          final description = builder.table(_table).where((r) => r.id.eq(1));
          late Query<(int, String?), _Fields> borrowed;
          try {
            await db.transaction((tx) async {
              borrowed = description.bind(tx);
              expect(await borrowed.get(), [(1, 'bound')]);
            });
            expect(driver.leases, 1);
            expect(
              borrowed.get,
              throwsA(
                isA<OrmException>().having(
                  (error) => error.code,
                  'code',
                  'SESSION.CLOSED',
                ),
              ),
            );
            final nested = builder
                .table(_table)
                .where(
                  (r) =>
                      r.id.isInQuery(builder.table(_table).select((c) => c.id)),
                );
            expect(
              () => nested.bind(db).compile(),
              throwsA(
                isA<OrmException>().having(
                  (error) => error.code,
                  'code',
                  'QUERY.SESSION',
                ),
              ),
            );
          } finally {
            await db.close();
          }
        },
      );

      test('insert scalar subqueries retain their own qualified aliases', () {
        final builder = SqlBuilder(dialect);
        final joined = _table.alias();
        final source = builder
            .table(_table)
            .join(joined, on: (a, b) => a.id.equals(b.id))
            .select((r) => r.name)
            .take(1);
        final command = builder
            .table(_table)
            .insert((r) => [r.id.set(3), r.name.setExpression(source.scalar())])
            .compile();
        expect(command.sql, contains('SELECT `t1`.`name`'));
        expect(command.sql, contains('`t1`.`id` = `t2`.`id`'));
        expect(command.parameters, [3, 1]);
      });

      test('do nothing cannot silently execute update triggers', () {
        expect(
          () =>
              SqlBuilder(dialect)
                  .table(_table)
                  .insert((r) => [r.id.set(1)])
                  .onConflictDoNothing()
                  .compile(),
          throwsA(isA<OrmException>()),
        );
      });

      test('decimal arithmetic rejects silent engine precision loss', () {
        final table = SqlBuilder(dialect).table(_table);
        for (final query in [
          table.select((r) => r.amount.plus(Decimal.parse('1'))),
          table.select((r) => r.amount.minus(Decimal.parse('1'))),
          table.select((r) => r.amount.times(Decimal.parse('1'))),
          table.select((r) => r.amount.sum()),
          table.select((r) => r.amount.constrained(2, 0)),
        ]) {
          expect(
            query.compile,
            throwsA(
              isA<OrmException>().having(
                (e) => e.code,
                'code',
                'CAPABILITY.DECIMAL_PRECISION',
              ),
            ),
          );
        }
      });

      test('decimal set operations reject implicit precision narrowing', () {
        final table = SqlBuilder(dialect).table(_table);
        expect(
          () => table
              .select((r) => r.amount)
              .unionAll(table.select((r) => r.amount)),
          throwsA(
            isA<OrmException>().having(
              (e) => e.code,
              'code',
              'CAPABILITY.DECIMAL_PRECISION',
            ),
          ),
        );
      });

      test('decimal average rejects unsupported exact rounding', () {
        expect(
          () =>
              SqlBuilder(dialect)
                  .table(_table)
                  .select((r) => r.amount.average(scale: 2))
                  .compile(),
          throwsA(isA<OrmException>()),
        );
      });

      test('decimal casts reject invalid MySQL scales', () {
        for (final scale in [-1, 3]) {
          expect(
            () =>
                SqlBuilder(dialect)
                    .table(_table)
                    .select((r) => r.amount.constrained(2, scale))
                    .compile(),
            throwsA(isA<OrmException>()),
          );
        }
      });

      test('BigInt comparisons use exact decimal parameters', () {
        final number = BigInt.parse('9007199254740993');
        final command = SqlBuilder(dialect)
            .table(_table)
            .select((_) => value(number, Codecs.bigint).eq(number + BigInt.one))
            .compile();
        expect(
          'CAST(? AS DECIMAL(65,0))'.allMatches(command.sql),
          hasLength(2),
        );
        expect(command.parameters, ['9007199254740993', '9007199254740994']);
      });

      test('a declared temporal precision remains writable', () {
        final command = SqlBuilder(dialect)
            .table(_table)
            .insert(
              (r) => [r.id.set(1), r.time.set(LocalTime.parse('01:02:03.456'))],
            )
            .compile();
        expect(command.parameters, [1, '01:02:03.456000']);
      });

      test(
        'precision-coerced createRow keys reject before acquiring a lease',
        () async {
          final driver = _Driver(dialect);
          final db = Database(driver);
          final decimal = _precisionKeyTable(
            Column('key', Codecs.decimal, decimalPrecision: 6, decimalScale: 2),
          );
          final time = _precisionKeyTable(
            Column('key', Codecs.time, temporalPrecision: 3),
          );
          try {
            for (final create in <Future<Object?> Function()>[
              () => db
                  .table(decimal)
                  .createRow(
                    (fields) => [fields.key.set(Decimal.parse('1.234'))],
                  ),
              () => db
                  .table(time)
                  .createRow(
                    (fields) => [
                      fields.key.set(LocalTime.parse('01:02:03.456789')),
                    ],
                  ),
            ]) {
              await expectLater(
                create,
                throwsA(
                  isA<OrmException>().having(
                    (error) => error.code,
                    'code',
                    'CAPABILITY.CREATE_KEY',
                  ),
                ),
              );
            }
            expect(driver.leases, 0);
            expect(driver.connection.commands, isEmpty);
          } finally {
            await db.close();
          }
        },
      );

      test('composite relation decimal keys bind as exact decimal', () async {
        final driver = _Driver(dialect);
        var selects = 0;
        driver.connection.result = (command) {
          if (!command.sql.startsWith('SELECT')) return const SqlResult([]);
          return ++selects == 1
              ? const SqlResult([
                  ['9007199254740993', 1],
                ])
              : const SqlResult([]);
        };
        final db = Database(driver);
        try {
          await db
              .table(_table)
              .select(
                (r) => Relation(
                  _table,
                  parent: [r.amount, r.id],
                  child: (c) => [c.amount, c.id],
                ).select((c) => c.id).many(),
              )
              .get();
          final child = driver.connection.commands.last;
          expect(child.sql, contains('CAST(? AS DECIMAL('));
          expect(child.parameters, ['9007199254740993', 1]);
        } finally {
          await db.close();
        }
      });

      for (final failure in ['identity', 'cardinality', 'decode']) {
        test(
          'caught createRow $failure failure prevents partial commit',
          () async {
            final driver = _Driver(dialect);
            driver.connection.result = (command) {
              if (command.sql.startsWith('INSERT')) {
                return SqlResult(
                  const [],
                  affectedRows: 1,
                  lastInsertId: failure == 'identity' ? null : 1,
                );
              }
              if (command.sql.startsWith('SELECT')) {
                return SqlResult(
                  failure == 'cardinality'
                      ? const []
                      : const [
                          [1, 42],
                        ],
                );
              }
              return const SqlResult([]);
            };
            final db = Database(driver);
            try {
              await expectLater(
                db.transaction((tx) async {
                  await expectLater(
                    tx.table(_table).createRow((r) => [r.name.set('inserted')]),
                    throwsA(anything),
                  );
                }),
                throwsA(
                  isA<OrmException>().having(
                    (error) => error.code,
                    'code',
                    'TRANSACTION.FAILED',
                  ),
                ),
              );
              expect(
                driver.connection.commands.map((c) => c.sql),
                contains('ROLLBACK'),
              );
              expect(
                driver.connection.commands.map((c) => c.sql),
                isNot(contains('COMMIT')),
              );
              expect(driver.leases, 1);
            } finally {
              await db.close();
            }
          },
        );
      }
    });
  }

  test('MySQL JSON comparison parses the encoded JSON parameter', () {
    final command = SqlBuilder(SqlDialect.mysql)
        .table(_table)
        .where((r) => r.document.eq(const SqlJson({'a': 1})))
        .compile();
    expect(command.sql, contains('CAST(? AS JSON)'));
    expect(command.parameters, ['{"a":1}']);
  });

  test('MySQL CTE retains JSON storage until the driver result boundary', () {
    final query = SqlBuilder(SqlDialect.mysql)
        .table(_table)
        .select((r) => r.document)
        .asCte('documents')
        .query;
    final command = query.compile();
    expect(
      'AS CHAR CHARACTER SET utf8mb4'.allMatches(command.sql),
      hasLength(1),
    );
  });

  test('JSON DISTINCT runs on native storage before result conversion', () {
    final query = SqlBuilder(SqlDialect.mysql)
        .table(_table)
        .select((r) => r.document)
        .distinct();
    expect(
      query.compile,
      throwsA(
        isA<OrmException>().having(
          (error) => error.code,
          'code',
          'CAPABILITY.JSON_DISTINCT',
        ),
      ),
    );
    final command = query.asCte('distinct_documents').query.compile();
    expect(command.sql, contains('SELECT DISTINCT `t1`.`document`'));
    expect(
      'AS CHAR CHARACTER SET utf8mb4'.allMatches(command.sql),
      hasLength(1),
    );
  });
}

final class _Driver implements Driver<Mysql> {
  @override
  final Capabilities capabilities;
  final connection = _Connection();
  int leases = 0;
  _Driver(SqlDialect dialect)
    : capabilities = Capabilities(
        dialect: dialect,
        maxParameters: 65535,
        returning: false,
        exactDecimal: true,
        temporal: true,
      );
  @override
  Future<R> run<R>(Future<R> Function(SqlConnection) action) {
    leases++;
    return Future.sync(() => action(connection));
  }

  @override
  Future<void> close() async {}
}

final class _Connection implements SqlConnection {
  final commands = <SqlCommand>[];
  SqlResult Function(SqlCommand) result = (_) => const SqlResult([]);
  bool active = false;
  @override
  bool get transactionActive => active;
  @override
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    commands.add(command);
    if (command.sql.startsWith('START TRANSACTION')) active = true;
    if (command.sql == 'COMMIT' || command.sql == 'ROLLBACK') active = false;
    return result(command);
  }

  @override
  Future<SqlCursor> openCursor(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) => throw UnsupportedError('No cursor in this regression fixture.');
  @override
  Future<void> invalidate() async {}
}
