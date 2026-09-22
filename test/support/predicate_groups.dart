import 'package:orm/orm.dart';
import 'package:test/test.dart' hide allOf, anyOf;

final _id = Column('id', Codecs.integer);
final _score = Column('score', Codecs.integer);
final _tag = Column('tag', Codecs.text.nullable(), nullable: true);
final _schema = TableSchema(
  'orm_predicate_groups',
  columns: [_id, _score, _tag],
  primaryKey: ['id'],
);

final class _Fields(super.table) extends Fields {
  late final id = column(_id);
  late final score = column(_score);
  late final tag = column(_tag);
}

final _table = Table<(int, int, String?), _Fields>(
  _schema,
  _Fields.new,
  (f) => (f.id, f.score, f.tag).row,
);

void predicateGroupTests(Future<Database<Backend>> Function() open) {
  late Database<Backend> db;
  setUp(() async {
    db = await open();
    await db.execute(SqlCommand('DROP TABLE IF EXISTS orm_predicate_groups'));
    await db.execute(
      SqlCommand(
        'CREATE TABLE orm_predicate_groups (id INTEGER PRIMARY KEY, '
        'score INTEGER NOT NULL, tag VARCHAR(40))',
      ),
    );
    await db.table(_table).insertMany(
      [(1, 10, null), (2, 20, 'x'), (3, 30, 'y'), (4, 40, 'blocked')],
      (f, row) => [f.id.set(row.$1), f.score.set(row.$2), f.tag.set(row.$3)],
    ).execute();
  });
  tearDown(() async {
    await db.execute(SqlCommand('DROP TABLE IF EXISTS orm_predicate_groups'));
    await db.close();
  });

  test('empty groups and NULL preserve SQL truth tables', () async {
    final rows = await db
        .table(_table)
        .orderBy((f) => [f.id.asc()])
        .select(
          (f) => (
            allOf([]),
            anyOf([]),
            allOf([f.tag.eq(.value('x')), value(true, Codecs.boolean)]),
            anyOf([f.tag.eq(.value('x')), value(false, Codecs.boolean)]),
            allOf([f.tag.eq(.value('x')), value(false, Codecs.boolean)]),
            anyOf([f.tag.eq(.value('x')), value(true, Codecs.boolean)]),
          ).row,
        )
        .get();
    expect(rows, [
      (true, false, null, null, false, true),
      (true, false, true, true, false, true),
      (true, false, false, false, false, true),
      (true, false, false, false, false, true),
    ]);
    expect(await db.table(_table).where((_) => allOf([])).count(), 4);
    expect(await db.table(_table).where((_) => anyOf([])).count(), 0);
  });

  test(
    'dynamic nested groups select, update and delete the same rows',
    () async {
      const included = [1, 3];
      const minimumScore = 10;
      final target = db
          .table(_table)
          .where(
            (f) => allOf([
              if (minimumScore > 0) f.score.gte(.value(minimumScore)),
              anyOf([for (final id in included) f.id.eq(.value(id))]),
              anyOf([f.tag.eq(.value('blocked')).not(), f.tag.isNull()]),
            ]),
          );
      expect(
        await target.orderBy((f) => [f.id.asc()]).select((f) => f.id).get(),
        [1, 3],
      );
      expect(await target.update((f) => [f.score.increment(1)]).execute(), 2);
      expect(
        await db
            .table(_table)
            .orderBy((f) => [f.id.asc()])
            .select((f) => f.score)
            .get(),
        [11, 20, 31, 40],
      );
      expect(await target.delete().execute(), 2);
      expect(
        await db
            .table(_table)
            .orderBy((f) => [f.id.asc()])
            .select((f) => f.id)
            .get(),
        [2, 4],
      );
    },
  );

  test('successive WHERE adds AND around complete OR groups', () async {
    final query = db
        .table(_table)
        .where((f) => anyOf([f.id.eq(.value(1)), f.id.eq(.value(2))]))
        .where((f) => anyOf([f.score.gt(.value(15)), f.tag.eq(.value('y'))]));
    expect(await query.select((f) => f.id).get(), [2]);
    expect(await query.where((_) => anyOf([])).count(), 0);
  });
}
