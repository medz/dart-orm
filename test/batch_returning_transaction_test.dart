@Tags(['sqlite'])
library;

import 'package:orm/driver.dart';
import 'package:orm/orm.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/sql.dart';
import 'package:orm/sqlite.dart';
import 'package:orm/values.dart';
import 'package:test/test.dart';

void main() {
  late Database<Sqlite> db;
  var mapperCalls = 0;
  setUp(() async {
    mapperCalls = 0;
    db = Database.fromSql(await sqlite(const SqliteOptions.memory()));
    await db.execute(
      SqlCommand('CREATE TABLE batch_results (id INTEGER PRIMARY KEY)'),
    );
  });
  tearDown(() => db.close());

  Future<List<int>> failingBatch(Database<Sqlite> scope) => scope
      .table(_table)
      .insertMany([1, 2], (row, id) => [row.id.set(id)])
      .returning(
        (row) => row.id.map<int>((_) {
          mapperCalls++;
          throw StateError('mapper failed');
        }),
      )
      .get();

  test('owned batch rolls SQL back when RETURNING decoding fails', () async {
    await expectLater(failingBatch(db), throwsStateError);
    expect(await db.table(_table).count(), 0);
    // Database rollback cannot undo a Dart callback's effects.
    expect(mapperCalls, 1);
  });

  test(
    'caught batch decoding failure leaves explicit transaction usable',
    () async {
      await db.transaction((tx) async {
        await expectLater(failingBatch(tx), throwsStateError);
        await tx.table(_table).insert((row) => [row.id.set(3)]).execute();
      });
      expect(await db.table(_table).orderBy((row) => [row.id.asc()]).get(), [
        1,
        2,
        3,
      ]);
      expect(mapperCalls, 1);
    },
  );

  test(
    'uncaught batch decoding failure rolls explicit transaction back',
    () async {
      await expectLater(db.transaction(failingBatch), throwsStateError);
      expect(await db.table(_table).count(), 0);
      expect(mapperCalls, 1);
    },
  );

  test(
    'caught typed read and RETURNING result errors preserve main policy',
    () async {
      await db.transaction((tx) async {
        await tx.table(_table).insertMany([
          1,
          2,
        ], (row, id) => [row.id.set(id)]).execute();
        await expectLater(
          tx.table(_table).map<int>((_) => throw StateError('read')).get(),
          throwsStateError,
        );
        await expectLater(
          tx.table(_table).single(),
          throwsA(isA<OrmException>()),
        );
        await expectLater(
          tx
              .table(_table)
              .update((row) => [row.id.increment(10)])
              .returning(
                (row) => row.id.map<int>((_) => throw StateError('returned')),
              )
              .get(),
          throwsStateError,
        );
        await tx.table(_table).insert((row) => [row.id.set(3)]).execute();
      });
      expect(await db.table(_table).orderBy((row) => [row.id.asc()]).get(), [
        3,
        11,
        12,
      ]);
    },
  );
}

final _id = Column('id', Codecs.integer);
final _table = Table<int, _Fields>(
  TableSchema('batch_results', columns: [_id], primaryKey: ['id']),
  _Fields.new,
  (row) => row.id,
);

final class _Fields extends Fields {
  _Fields(super.table);
  late final id = column(_id);
}
