import 'package:orm/sql.dart';
import 'package:test/test.dart';

final _id = Column('id', Codecs.integer);
final _name = Column('name', Codecs.text.nullable(), nullable: true);
final _json = Column('data', Codecs.json.nullable(), nullable: true);
final _time = Column('created_at', Codecs.dateTime);
final _schema = TableSchema(
  'items',
  columns: [_id, _name, _json, _time],
  primaryKey: ['id'],
);

final class _Fields(super.table) extends Fields {
  late final id = column(_id);
  late final name = column(_name);
  late final data = column(_json);
  late final createdAt = column(_time);
}

final _table = Table<(int, String?), _Fields>(
  _schema,
  _Fields.new,
  (f) => (f.id, f.name).row,
);

void main() {
  for (final dialect in SqlDialect.values) {
    test('$dialect builds independently and rejects execution', () {
      final builder = SqlBuilder(dialect);
      final query = builder.table(_table).where((r) => r.id.gt(3)).take(2);
      expect(query.compile().parameters, [3, 2]);
      expect(query.inspect().reads, ['items']);
      expect(
        query.get,
        throwsA(
          isA<OrmException>().having((e) => e.code, 'code', 'QUERY.UNBOUND'),
        ),
      );
    });
  }
  for (final dialect in [SqlDialect.mysql, SqlDialect.mariadb]) {
    test('$dialect positional parameters follow final SQL order', () {
      final query = SqlBuilder(dialect)
          .table(_table)
          .where((r) => r.id.gt(10))
          .orderBy((r) => [r.id.plus(5).asc(nulls: NullOrder.last)])
          .select((r) => r.id.plus(2))
          .take(3);
      final command = query.compile();
      expect(command.parameters, [2, 10, 5, 5, 3]);
      expect(command.sql, isNot(contains('NULLS')));
      expect(command.sql, contains('`items`'));
      expect('?'.allMatches(command.sql).length, command.parameters.length);
      expect(command.sql, isNot(contains('\u0001')));
    });
    test('$dialect JSON projection preserves text and SQL NULL', () {
      final command = SqlBuilder(dialect)
          .table(_table)
          .select((r) => r.data)
          .compile();
      expect(
        command.sql,
        contains('CAST(`t0`.`data` AS CHAR CHARACTER SET utf8mb4)'),
      );
    });
    test('$dialect instant conversion is typed, text is unchanged', () {
      final time = DateTime.utc(2026, 9, 19, 1, 2, 3, 4, 5);
      final command = SqlBuilder(dialect)
          .table(_table)
          .insert(
            (r) => [
              r.id.set(1),
              r.name.set('2026-09-19 01:02:03.004005+00'),
              r.createdAt.set(time),
            ],
          )
          .compile();
      expect(command.parameters, [
        1,
        '2026-09-19 01:02:03.004005+00',
        '2026-09-19 01:02:03.004005',
      ]);
      expect(command.sql, isNot(contains('INSERT INTO `items` AS')));
    });
    test('$dialect conflict targets cannot silently change meaning', () {
      final table = SqlBuilder(dialect).table(_table);
      expect(
        () => table
            .insert((r) => [r.id.set(1)])
            .onConflictUpdate(
              target: (r) => [r.id],
              set: (a, b) => [a.name.setExpression(b.name)],
            )
            .compile(),
        throwsA(
          isA<OrmException>().having(
            (e) => e.code,
            'code',
            'CAPABILITY.CONFLICT_TARGET',
          ),
        ),
      );
      final command = table
          .insert((r) => [r.id.set(1)])
          .onDuplicateKeyUpdate(set: (a, b) => [a.name.setExpression(b.name)])
          .compile();
      expect(
        command.sql,
        contains('ON DUPLICATE KEY UPDATE `name` = VALUES(`name`)'),
      );
    });
  }
}
