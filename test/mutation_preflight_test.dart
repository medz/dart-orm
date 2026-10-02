@Tags(['sqlite'])
library;

import 'package:orm/driver.dart';
import 'package:orm/orm.dart';
import 'package:orm/sql.dart';
import 'package:orm/sqlite.dart';
import 'package:orm/values.dart';
import 'package:test/test.dart';

import 'support/api_shape/models.orm.dart';
import 'support/api_shape/models.dart' as models;

void main() {
  late Database<Sqlite> db;
  final events = <QueryEvent>[];
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
    await db.user.create(email: 'ada', name: 'Ada');
    events.clear();
  });
  tearDown(() => db.close());
  Matcher code(String value) =>
      isA<OrmException>().having((e) => e.code, 'code', value);

  test(
    'known model shapes reject before assignment and RETURNING callbacks',
    () async {
      final alias = userTable.alias();
      final shapes = [
        db.user.take(1),
        db.user.skip(1),
        db.user.orderBy((u) => [u.id.asc()]),
        db.user.join(alias, on: (u, other) => u.id.eq(other.id)),
      ];
      var assignments = 0, selections = 0;
      for (final shape in shapes) {
        final write = shape.plan.update(
          userPatch.values(
            stamp: .expression((u) {
              assignments++;
              return u.stamp.plus(1);
            }),
          ),
        );
        await expectLater(write.execute(), throwsA(code('MUTATION.QUERY')));
        await expectLater(
          write.returning().select((u) {
            selections++;
            return u.id;
          }).get(),
          throwsA(code('MUTATION.QUERY')),
        );
      }
      expect(assignments, 0);
      expect(selections, 0);
      expect(events, isEmpty);
      expect((await db.user.single()).stamp, 1);
    },
  );

  test(
    'manual table preparation rejects shapes and expired scope before callback',
    () async {
      var calls = 0;
      expect(
        () => db.table(userTable).take(1).update((u) {
          calls++;
          return [u.name.set('invalid')];
        }),
        throwsA(code('MUTATION.QUERY')),
      );
      late TableQuery<User, UserFields> escaped;
      await db.session((session) async {
        escaped = session.table(userTable);
      });
      expect(
        () => escaped.update((u) {
          calls++;
          return [u.name.set('expired')];
        }),
        throwsA(code('SESSION.CLOSED')),
      );
      expect(calls, 0);
      expect(events, isEmpty);
    },
  );

  test(
    'invalid AST discovered from a callback does not promise zero callbacks',
    () async {
      var calls = 0;
      final alias = userTable.alias();
      await expectLater(
        db.user.update(
          userPatch.values(
            stamp: .expression((_) {
              calls++;
              return alias.fields.stamp;
            }),
          ),
        ),
        throwsA(code('QUERY.SCOPE')),
      );
      expect(calls, 1);
      expect(events, isEmpty);
    },
  );

  test(
    'cancelled operation and invalid options reject before input callbacks',
    () async {
      var calls = 0;
      final write = db.user.plan.update(
        userPatch.values(
          stamp: .expression((u) {
            calls++;
            return u.stamp.plus(1);
          }),
        ),
      );
      await expectLater(
        write.execute(
          options: ExecutionOptions(
            cancellation: CancellationToken()..cancel(),
          ),
        ),
        throwsA(code('OPERATION.CANCELLED')),
      );
      await expectLater(
        write.execute(options: const ExecutionOptions(timeout: Duration.zero)),
        throwsArgumentError,
      );
      expect(calls, 0);
      expect(events, isEmpty);
    },
  );
}
