import 'dart:typed_data';

import 'package:orm/database.dart';
import 'package:orm/query.dart';
import 'package:orm/schema.dart';
import 'package:test/test.dart' hide startsWith;
import 'package:test/test.dart' as match show startsWith;

import '../example/models.dart';
import '../example/models.snapshot.dart';
import 'support/database.dart';

void main() {
  for (final engine in Engine.values) {
    group(
      'generated query on ${engine.name}',
      () {
        late TestDatabase fixture;
        setUp(() async => fixture = await openTestDatabase(engine));
        tearDown(() => fixture.db.close());

        test(
          'CRUD preserves defaults, UTC, bytes, omission and explicit null',
          () async {
            final db = fixture.db;
            final instant = DateTime.parse('2026-10-09T12:34:56.123456+08:00');
            final row = await db.users.create(
              username: "seven'; DROP TABLE users; --",
              age: 28,
              nickname: 'Seven',
              joinedAt: instant,
              avatar: Uint8List.fromList([0, 255]),
            );
            expect(row.active, isTrue);
            expect(row.score, 0.0);
            expect(row.joinedAt, instant.toUtc());
            expect(row.avatar, [0, 255]);
            expect(row.username, "seven'; DROP TABLE users; --");
            final updated = (await db.users.update(row.id, age: 29))!;
            expect(updated.nickname, 'Seven');
            expect(
              (await db.users.update(row.id, nickname: null))!.nickname,
              isNull,
            );
            expect((await db.users.get(row.id))!.username, row.username);
            expect(
              await db.users.update(row.id + 100, nickname: 'absent'),
              isNull,
            );
            expect(await db.users.delete(row.id), 1);
            expect(await db.users.delete(row.id), 0);
            expect(await db.users.get(row.id), isNull);
            expect(
              fixture.statements.every(
                (event) => !event.sql.contains(row.username),
              ),
              isTrue,
            );
          },
        );

        test(
          'typed projections, immutable scopes, literal LIKE and nullable IN',
          () async {
            final db = fixture.db;
            await db.users.create(username: 'sev%_!', age: 28);
            await db.users.create(username: 'seven', age: 17, nickname: 'kid');
            await db.users.create(
              username: 'someone',
              age: 30,
              nickname: 'adult',
            );
            final base = db.users.where(age: gte(18) & lt(31));
            fixture.events.clear();
            final cards = await base
                .where(username: startsWith('sev%_!'))
                .select<UserCard>();
            expect(cards.single.username, 'sev%_!');
            expect(
              fixture.statements.single.sql,
              match.startsWith('SELECT "id", "username"'),
            );
            expect(fixture.statements.single.sql, isNot(contains('"avatar"')));
            expect(await base.all(), hasLength(2));
            final nullable = await db.users
                .where(nickname: oneOf<String?>([null, 'kid']))
                .orderBy(id: asc)
                .select<UserProfile>();
            expect(nullable.map((row) => row.nickname), [null, 'kid']);
            expect(await db.users.where(id: oneOf<int>([])).all(), isEmpty);
            expect(
              await db.users.where(nickname: ne<String?>(null)).all(),
              hasLength(2),
            );
            expect(
              await db.users.where(username: containsText('%_!')).all(),
              hasLength(1),
            );
            expect(
              (await db.users
                      .orderBy(age: desc)
                      .orderBy(id: asc)
                      .offset(1)
                      .limit(1)
                      .all())
                  .single
                  .age,
              28,
            );
          },
        );

        test('invalid scopes fail before SQL', () async {
          final db = fixture.db;
          final query = TableQuery<List<Object?>>(
            db.session,
            frozenSchema.tables.first,
            (row) => row,
          );
          fixture.events.clear();
          expect(
            () => query.whereFields({'missing': eq<Object?>(1)}),
            throwsArgumentError,
          );
          await expectLater(
            query.selectRows(['missing'], (row) => row),
            throwsArgumentError,
          );
          expect(() => db.users.select<PostCard>(), throwsArgumentError);
          expect(() => db.users.where(), throwsArgumentError);
          expect(
            () => db.users.orderBy(age: asc, id: asc),
            throwsArgumentError,
          );
          await expectLater(db.users.update(1), throwsArgumentError);
          await expectLater(db.users.limit(1).delete(1), throwsStateError);
          await expectLater(
            db.users.where(id: eq(1)).create(username: 'invalid', age: 1),
            throwsStateError,
          );
          await expectLater(
            db.users.where(active: gt(true)).all(),
            throwsArgumentError,
          );
          await expectLater(
            db.users.where(nickname: gt<String?>(null)).all(),
            throwsArgumentError,
          );
          await expectLater(
            query.updateById(1, {'id': 2}),
            throwsArgumentError,
          );
          await expectLater(
            query.updateById(1, {'age': null}),
            throwsArgumentError,
          );
          await expectLater(db.users.increment(1, age: 0), throwsArgumentError);
          expect(fixture.events, isEmpty);
        });

        test('atomic arithmetic uses one guarded UPDATE RETURNING', () async {
          final product = await fixture.db.products.create(
            sku: 'p',
            name: 'Product',
            priceCents: 4900,
            stock: 2,
          );
          fixture.events.clear();
          final updated = await fixture.db.products
              .where(stock: gte(2))
              .decrement(product.id, stock: 2);
          expect(updated!.stock, 0);
          expect(updated.priceCents, 4900);
          expect(fixture.statements, hasLength(1));
          expect(fixture.statements.single.sql, match.startsWith('UPDATE'));
          expect(fixture.statements.single.sql, contains('RETURNING'));
          expect(
            await fixture.db.products
                .where(stock: gte(1))
                .decrement(product.id, stock: 1),
            isNull,
          );
          expect(
            (await fixture.db.products.increment(product.id, stock: 3))!.stock,
            3,
          );
          final user = await fixture.db.users.create(
            username: 'real',
            age: 28,
            score: 1.5,
          );
          final increased = await fixture.db.users
              .where(active: eq(true))
              .increment(user.id, age: 1, score: 0.25);
          expect(increased!.age, 29);
          expect(increased.score, 1.75);
          expect(
            (await fixture.db.users.decrement(user.id, score: 0.5))!.score,
            1.25,
          );
          final lines = frozenSchema.tables.singleWhere(
            (table) => table.name == 'order_lines',
          );
          final query = TableQuery<List<Object?>>(
            fixture.db.session,
            lines,
            (row) => row,
          );
          await expectLater(
            query.incrementById(1, {'productId': 1}),
            throwsArgumentError,
          );
        });

        test('numeric overflow never persists an invalid scalar', () async {
          const maxInteger = 9223372036854775807;
          const minInteger = -9223372036854775808;
          const maxReal = 1.7976931348623157e308;
          final max = await fixture.db.users.create(
            username: 'max',
            age: maxInteger,
            score: maxReal,
          );
          final min = await fixture.db.users.create(
            username: 'min',
            age: minInteger,
            score: -maxReal,
          );
          expect(await fixture.db.users.increment(max.id, age: 1), isNull);
          expect(await fixture.db.users.decrement(min.id, age: 1), isNull);
          expect((await fixture.db.users.get(max.id))!.age, maxInteger);
          expect((await fixture.db.users.get(min.id))!.age, minInteger);
          if (engine == Engine.sqlite) {
            expect(
              await fixture.db.users.increment(max.id, score: maxReal),
              isNull,
            );
            expect(
              await fixture.db.users.decrement(min.id, score: maxReal),
              isNull,
            );
          } else {
            await expectLater(
              fixture.db.users.increment(max.id, score: maxReal),
              throwsException,
            );
            await expectLater(
              fixture.db.users.decrement(min.id, score: maxReal),
              throwsException,
            );
          }
          expect((await fixture.db.users.get(max.id))!.score, maxReal);
          expect((await fixture.db.users.get(min.id))!.score, -maxReal);
          expect(
            (await fixture.db.users.decrement(max.id, age: 1))!.age,
            maxInteger - 1,
          );
          expect(
            (await fixture.db.users.increment(min.id, age: 1))!.age,
            minInteger + 1,
          );
        });

        test(
          'streaming reads bounded batches within an expiring transaction',
          () async {
            for (var i = 0; i < 5; i++) {
              await fixture.db.users.create(username: 'user$i', age: i);
            }
            await expectLater(
              fixture.db.users.stream().toList(),
              throwsStateError,
            );
            fixture.events.clear();
            final streamed = await fixture.db.transaction((tx) async {
              await expectLater(
                tx.users.orderBy(age: asc).stream().toList(),
                throwsArgumentError,
              );
              await expectLater(
                tx.users.offset(1).stream().toList(),
                throwsArgumentError,
              );
              return tx.users.limit(5).stream(fetchSize: 2).toList();
            }, readOnly: true);
            expect(streamed.map((row) => row.username), [
              'user0',
              'user1',
              'user2',
              'user3',
              'user4',
            ]);
            final selects = fixture.statements
                .where((event) => event.sql.startsWith('SELECT'))
                .toList();
            expect(selects, hasLength(3));
            expect(selects.map((event) => event.rows), [2, 2, 1]);
            expect(
              fixture.events.where((event) => event.kind == 'begin'),
              hasLength(1),
            );
            expect(
              fixture.events.where((event) => event.kind == 'commit'),
              hasLength(1),
            );
            fixture.events.clear();
            await fixture.db.transaction((tx) async {
              final first = await tx.users
                  .stream(fetchSize: 2)
                  .take(1)
                  .toList();
              expect(first.single.username, 'user0');
            }, readOnly: true);
            final earlySelects = fixture.statements
                .where((event) => event.sql.startsWith('SELECT'))
                .toList();
            expect(earlySelects, hasLength(1));
            expect(earlySelects.single.rows, 2);
          },
        );

        test(
          'capabilities and parameter limit are checked before execution',
          () async {
            final session = _LimitedSession(fixture.db.session);
            final query = TableQuery<List<Object?>>(
              session,
              frozenSchema.tables.first,
              (row) => row,
            );
            await expectLater(
              query.whereFields({
                'id': oneOf<Object?>([1, 2, 3, 4]),
              }).all(),
              throwsUnsupportedError,
            );
            await expectLater(
              query.insert({'username': 'u', 'age': 1}),
              throwsUnsupportedError,
            );
            expect(fixture.events, isEmpty);
          },
        );

        test('quoted physical table identity is independent of record shape', () async {
          const name = 'odd " table';
          await fixture.db.session.run(
            'CREATE TABLE ${quoteIdentifier(name)} ("id" BIGINT PRIMARY KEY, "display name" TEXT NOT NULL)',
          );
          final query = TableQuery<({int id, String username})>(
            fixture.db.session,
            const TableDefinition(name, [
              ColumnDefinition(
                name: 'id',
                field: 'id',
                type: ScalarType.integer,
                primaryKey: true,
              ),
              ColumnDefinition(
                name: 'display name',
                field: 'username',
                type: ScalarType.text,
              ),
            ]),
            (row) => (
              id: decodeValue<int>(row[0]),
              username: decodeValue<String>(row[1]),
            ),
          );
          final row = await query.insert({'id': 1, 'username': 'direct'});
          expect(row.username, 'direct');
          expect((await query.get(1))!.username, 'direct');
        });
      },
      skip: engine == Engine.postgresql && !hasPostgres
          ? 'Set ORM_TEST_POSTGRES_HOST or ORM_TEST_POSTGRES_SOCKET for a real database'
          : false,
    );
  }
}

final class _LimitedSession implements Session {
  _LimitedSession(this.delegate);
  final Session delegate;
  @override
  Engine get engine => delegate.engine;
  @override
  bool get inTransaction => delegate.inTransaction;
  @override
  Capabilities get capabilities =>
      const Capabilities(returning: false, maxParameters: 3);
  @override
  Future<QueryResult> run(String sql, {List<Object?> parameters = const []}) =>
      delegate.run(sql, parameters: parameters);
}
