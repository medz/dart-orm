@Tags(['sqlite'])
library;

import 'package:orm/orm.dart';
import 'package:orm/sql.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart' hide allOf, anyOf;

import 'support/tables.dart';

void main() {
  late Database<Sqlite> db;
  final events = <QueryEvent>[];

  setUp(() async {
    db = Database.fromSql(
      await sqlite(const SqliteOptions.memory(), onQuery: events.add),
    );
    await createTables(db);
    for (final (index, score) in [0, 0, 1, 2, 2, 2].indexed) {
      await db
          .table(users)
          .createRow((u) => [u.email.set('user$index'), u.score.set(score)]);
    }
    events.clear();
  });
  tearDown(() => db.close());

  test('repeated HAVING calls preserve earlier predicates with AND', () async {
    final base = db
        .table(users)
        .groupBy((u) => [u.score])
        .having((u) => u.id.count().gt(.value(1)))
        .orderBy((u) => [u.score.asc()])
        .select((u) => (u.score, u.id.count()).row);
    final filtered = base.having((u) => u.id.count().lt(.value(3)));

    expect(await filtered.get(), [(0, 2)]);
    expect(await base.get(), [(0, 2), (2, 3)]);
    expect(filtered.compile().parameters, [1, 3]);
  });

  test('HAVING combines complete OR groups before the next filter', () async {
    final query = db
        .table(users)
        .groupBy((u) => [u.score])
        .having(
          (u) =>
              anyOf([u.id.count().eq(.value(1)), u.id.count().eq(.value(3))]),
        )
        .having((u) => u.id.count().gt(.value(1)))
        .select((u) => (u.score, u.id.count()).row);

    expect(await query.get(), [(2, 3)]);
    expect(query.compile().parameters, [1, 3, 1]);
  });
}
