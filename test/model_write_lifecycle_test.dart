@Tags(['sqlite'])
library;

import 'package:orm/driver.dart';
import 'package:orm/orm.dart';
import 'package:orm/sql.dart';
import 'package:orm/sqlite.dart';
import 'package:orm/values.dart';
import 'package:test/test.dart';

import 'support/api_shape/models.dart' as models;
import 'support/api_shape/models.orm.dart';

void main() {
  late Database<Sqlite> db;
  final events = <QueryEvent>[];
  Matcher code(String value) =>
      isA<OrmException>().having((e) => e.code, 'code', value);
  setUp(() async {
    models.samples = 0;
    db = Database.fromSql(
      await sqlite(const SqliteOptions.memory(), onQuery: events.add),
    );
    await db.sql.raw(
      Sql(
        'CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT NOT NULL, name TEXT NOT NULL, nickname TEXT, stamp INTEGER NOT NULL)',
      ),
    );
    events.clear();
  });
  tearDown(() => db.close());

  test('ordinary named and input writes execute; awaiting a Future again does not replay', () async {
    final user = await db.user.create(email: 'a', name: 'Ada', nickname: 'old');
    final Future<int> updated = db.user.byId(user.id).patch(nickname: null);
    expect(await updated, 1);
    expect((await db.user.single()).nickname, isNull);
    expect((await db.user.single()).name, 'Ada');
    expect(await db.user.byId(user.id).update(userPatch(name: 'Reviewed')), 1);
    final Future<int> inserted = db.user.insert(
      userInsert(email: 'b', name: 'Bob'),
    );
    expect(await inserted, 1);
    expect(await inserted, 1);
    expect(await db.user.count(), 2);
    expect(await db.user.insertMany([userInsert(email: 'c', name: 'Cara')]), 1);
    expect(await db.user.byId(user.id).delete(), 1);
    expect(await db.user.count(), 2);
  });

  test('named patch tear-off preserves omission versus NULL', () async {
    final user = await db.user.create(
      email: 'a',
      name: 'Ada',
      nickname: 'keep',
    );
    final Future<int> Function({String? nickname}) patch = db.user
        .byId(user.id)
        .patch
        .call;
    await expectLater(patch(), throwsA(code('MUTATION.EMPTY')));
    expect((await db.user.single()).nickname, 'keep');
    expect(await patch(nickname: null), 1);
    expect((await db.user.single()).nickname, isNull);
  });

  test('plan constructs without factories or SQL, terminal resamples and prepare freezes', () async {
    final plan = db.user.plan;
    final write = plan.insert(userInsert(email: 'planned', name: 'Planned'));
    expect(models.samples, 0);
    expect(events, isEmpty);
    expect(await write.execute(), 1);
    expect(await write.execute(), 1);
    expect(models.samples, 2);
    final prepared = write.prepare();
    expect(models.samples, 3);
    await prepared.execute();
    await prepared.execute();
    expect(models.samples, 3);
    final stamps = await db.user
        .orderBy((u) => [u.id.asc()])
        .select((u) => u.stamp)
        .get();
    expect(stamps, [1, 2, 3, 3]);
  });

  test(
    'RETURNING validation and cancellation precede client defaults',
    () async {
      final write = db.user.plan.insert(
        userInsert(email: 'invalid', name: 'Invalid'),
      );
      await expectLater(
        write.returning().select((u) => u.memberships.many()).get(),
        throwsA(code('MUTATION.RELATION')),
      );
      await expectLater(
        write.returning().single(
          options: ExecutionOptions(
            cancellation: CancellationToken()..cancel(),
          ),
        ),
        throwsA(code('OPERATION.CANCELLED')),
      );
      expect(models.samples, 0);
      expect(events, isEmpty);
    },
  );

  test(
    'immediate batch checks options before traversing user iterable',
    () async {
      var traversed = false;
      Iterable<UserInsert> inputs() sync* {
        traversed = true;
        yield userInsert(email: 'cancelled', name: 'Cancelled');
      }

      await expectLater(
        db.user.insertMany(
          inputs(),
          options: ExecutionOptions(
            cancellation: CancellationToken()..cancel(),
          ),
        ),
        throwsA(code('OPERATION.CANCELLED')),
      );
      expect(traversed, false);
      expect(models.samples, 0);
      expect(events, isEmpty);
    },
  );

  test('cached plan does not extend borrowed session ownership', () async {
    late ModelTableWritePlan<User, UserFields, UserInsert, UserPatch> captured;
    await db.session((session) async {
      captured = session.user.plan;
    });
    final write = captured.insert(
      userInsert(email: 'escaped', name: 'Escaped'),
    );
    await expectLater(write.execute(), throwsA(code('SESSION.CLOSED')));
    expect(models.samples, 0);
    expect(events, isEmpty);
    expect(await db.user.insert(userInsert(email: 'root', name: 'Root')), 1);
  });
}
