import 'dart:typed_data';

import 'package:orm/database.dart';
import 'package:orm/query.dart';
import 'package:orm/schema.dart';
import 'package:test/test.dart' hide startsWith;
import 'package:test/test.dart' as match show startsWith;

import '../example/models.dart';
import '../example/models.db.dart' show AppSession;
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
            final table = '${quoteIdentifier(db.session.schema)}."users"';
            expect(
              fixture.statements.every((event) => event.sql.contains(table)),
              isTrue,
            );
          },
        );

        test(
          'byte filters capture immutable values and remain reusable',
          () async {
            final db = fixture.db;
            final first = await db.users.create(
              username: 'first bytes',
              age: 1,
              avatar: Uint8List.fromList([1, 2]),
            );
            final second = await db.users.create(
              username: 'second bytes',
              age: 2,
              avatar: Uint8List.fromList([3, 4]),
            );
            final absent = await db.users.create(
              username: 'null bytes',
              age: 3,
            );
            final bytes = Uint8List.fromList([1, 2]);
            final otherBytes = Uint8List.fromList([3, 4]);
            final values = <Uint8List?>[bytes, null];
            final equality = eq<Uint8List?>(bytes);
            final inequality = ne<Uint8List?>(bytes);
            final membership = oneOf<Uint8List?>(values);
            final group =
                (eq<Uint8List?>(bytes) | eq<Uint8List?>(otherBytes)) &
                ne<Uint8List?>(null);
            bytes[0] = 9;
            otherBytes[0] = 8;
            values
              ..clear()
              ..add(Uint8List.fromList([9, 2]));
            final checks = [
              (
                label: 'eq',
                query: db.users.where(avatar: equality),
                ids: [first.id],
              ),
              (
                label: 'ne',
                query: db.users.where(avatar: inequality),
                ids: [second.id],
              ),
              (
                label: 'oneOf',
                query: db.users.where(avatar: membership),
                ids: [first.id, absent.id],
              ),
              (
                label: 'groups',
                query: db.users.where(avatar: group),
                ids: [first.id, second.id],
              ),
            ];
            Future<void> checkQueries() async {
              for (final check in checks) {
                expect(
                  (await check.query.orderBy(id: asc).all()).map(
                    (row) => row.id,
                  ),
                  check.ids,
                  reason: check.label,
                );
              }
            }

            await checkQueries();
            bytes[1] = 7;
            otherBytes[1] = 6;
            values.clear();
            await checkQueries();
            final bound = <Uint8List>[];
            equality.compile('avatar', (value) {
              bound.add(value as Uint8List);
              return '?';
            }, ScalarType.bytes);
            expect(() => bound.single[0] = 5, throwsUnsupportedError);
            expect(
              () => bound.single.buffer.asUint8List()[0] = 5,
              throwsUnsupportedError,
            );
            expect(bound.single, [1, 2]);
            await checkQueries();
          },
        );

        test('byte writes capture call-time values in root and queued transactions', () async {
          Future<void> checkWrites(AppSession session, String scope) async {
            final createdBytes = Uint8List.fromList([0, 255]);
            final creating = session.users.create(
              username: '$scope bytes',
              age: 1,
              avatar: createdBytes.asUnmodifiableView(),
            );
            createdBytes[0] = 40;
            final row = await creating;
            expect(row.avatar, [0, 255], reason: '$scope create');
            expect((await session.users.get(row.id))!.avatar, [0, 255]);
            final updatedBytes = Uint8List.fromList([1, 254]);
            final updating = session.users.update(row.id, avatar: updatedBytes);
            updatedBytes[0] = 41;
            expect((await updating)!.avatar, [1, 254], reason: '$scope update');
            expect((await session.users.get(row.id))!.avatar, [1, 254]);
            final rawBytes = Uint8List.fromList([2, 253]);
            final parameters = <Object?>[rawBytes, row.id];
            final value = engine == Engine.sqlite ? '?' : '\$1';
            final key = engine == Engine.sqlite ? '?' : '\$2';
            final writing = session.run(
              'UPDATE ${quoteIdentifier(session.schema)}."users" SET "avatar" = $value WHERE "id" = $key',
              parameters: parameters,
            );
            rawBytes[0] = 42;
            parameters[0] = Uint8List.fromList([43, 252]);
            parameters[1] = row.id + 100;
            await writing;
            expect((await session.users.get(row.id))!.avatar, [
              2,
              253,
            ], reason: '$scope raw run');
          }

          await checkWrites(fixture.db.session, 'root');
          await fixture.db.transaction((tx) => checkWrites(tx, 'transaction'));
          expect(
            (await fixture.db.users.orderBy(id: asc).all()).map(
              (row) => row.avatar,
            ),
            [
              [2, 253],
              [2, 253],
            ],
          );
        });

        if (engine == Engine.sqlite) {
          test('bound strings retain embedded NUL', () async {
            final db = fixture.db;
            const value = 'before\u0000after';
            final row = await db.users.create(
              username: value,
              age: 28,
              nickname: value,
            );
            expect(row.username, value);
            expect((await db.users.get(row.id))?.nickname, value);
            expect(
              (await db.users.where(username: eq(value)).all()).single.id,
              row.id,
            );
            expect(
              (await db.users.update(
                row.id,
                nickname: 'next\u0000value',
              ))?.nickname,
              'next\u0000value',
            );
            expect(
              fixture.statements.every(
                (event) => !event.sql.contains('\u0000'),
              ),
              isTrue,
            );
          });
        }

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

        test(
          'OR groups retain AND, null semantics and immutable scopes',
          () async {
            final db = fixture.db;
            final adult = await db.users.create(username: 'adult', age: 28);
            final child = await db.users.create(
              username: 'child',
              age: 17,
              nickname: 'minor',
            );
            final senior = await db.users.create(
              username: 'senior',
              age: 70,
              nickname: 'member',
            );
            await db.users.create(
              username: 'elderly',
              age: 80,
              nickname: 'member',
            );
            await db.users.create(
              username: 'disabled',
              age: 28,
              nickname: 'member',
              active: false,
            );
            await db.users.create(username: 'outsider', age: 28);

            final active = db.users.where(active: eq(true));
            final members = active.whereAny(
              username: eq('adult'),
              nickname: oneOf(['member', 'minor']),
            );
            final eligible = members.whereAny(
              age: (gte(18) & lt(65)) | eq(70),
              nickname: eq('minor'),
            );
            expect(
              (await eligible.orderBy(id: asc).all()).map((row) => row.id),
              [adult.id, child.id, senior.id],
            );
            expect(
              (await eligible
                      .orderBy(id: asc)
                      .offset(1)
                      .limit(1)
                      .select<UserCard>())
                  .single
                  .id,
              child.id,
            );
            expect(
              (await members
                      .whereAny(nickname: eq(null), age: lt(18))
                      .orderBy(id: asc)
                      .all())
                  .map((row) => row.id),
              [adult.id, child.id],
            );
            expect(await eligible.all(), hasLength(3));
            expect(await members.all(), hasLength(4));
            expect(await active.all(), hasLength(5));

            final query = TableQuery<List<Object?>>(
              db.session,
              frozenSchema.tables.first,
              (row) => row,
            );
            final fields = <String, Filter<Object?>>{
              'username': eq<Object?>('adult'),
              'nickname': eq<Object?>('absent'),
            };
            final saved = query.whereAnyFields(fields);
            fields.clear();
            expect((await saved.all()).single.first, adult.id);
          },
        );

        test(
          'count retains filters without loading or decoding model rows',
          () async {
            final db = fixture.db;
            await db.users.create(username: 'sev%_!one', age: 28);
            await db.users.create(
              username: 'second',
              age: 18,
              nickname: 'sev%_!two',
            );
            await db.users.create(
              username: 'sev%_!both',
              age: 30,
              nickname: 'sev%_!both',
            );
            await db.users.create(username: 'sevXX!lookalike', age: 28);
            await db.users.create(
              username: 'sev%_!disabled',
              age: 28,
              active: false,
            );
            await db.users.create(username: 'sev%_!child', age: 17);
            final base = db.users.where(active: eq(true), age: gte(18));
            final matching = base.whereAny(
              username: startsWith('sev%_!'),
              nickname: startsWith('sev%_!'),
            );
            fixture.events.clear();
            final int total = await matching.count();
            expect(total, 3);
            expect(fixture.statements, hasLength(1));
            expect(fixture.statements.single.rows, 1);
            expect(
              fixture.statements.single.sql,
              match.startsWith('SELECT COUNT(*)'),
            );
            expect(fixture.statements.single.sql, isNot(contains('"avatar"')));
            expect(fixture.statements.single.sql, isNot(contains('sev')));
            expect(
              await matching
                  .where(nickname: oneOf<String?>([null, 'sev%_!two']))
                  .count(),
              2,
            );
            expect(await matching.count(), 3);
            expect(await base.count(), 4);

            final query = TableQuery<Never>(
              db.session,
              frozenSchema.tables.firstWhere((table) => table.name == 'users'),
              (_) => throw StateError('Counting must not decode model rows'),
            );
            expect(
              await query.whereFields({'nickname': eq<Object?>(null)}).count(),
              4,
            );
          },
        );

        test('count measures the requested page and omits ordering', () async {
          for (var index = 0; index < 4; index++) {
            await fixture.db.users.create(username: 'count$index', age: index);
          }
          final base = fixture.db.users.orderBy(age: desc);
          for (final page in [
            (query: base.limit(2), expected: 2),
            (query: base.offset(1).limit(2), expected: 2),
            (query: base.offset(2), expected: 2),
            (query: base.offset(10), expected: 0),
            (query: base.limit(0), expected: 0),
          ]) {
            fixture.events.clear();
            final int count = await page.query.count();
            expect(count, page.expected);
            expect(fixture.statements, hasLength(1));
            expect(fixture.statements.single.rows, 1);
            expect(fixture.statements.single.sql, isNot(contains('ORDER BY')));
            expect(fixture.statements.single.sql, isNot(contains('"avatar"')));
          }
          fixture.events.clear();
          expect(await base.count(), 4);
          expect(fixture.statements.single.sql, isNot(contains('ORDER BY')));
          expect((await base.all()).map((row) => row.age), [3, 2, 1, 0]);
        });

        test('OR scopes retain the primary key and guarded writes', () async {
          final db = fixture.db;
          final allowed = await db.users.create(username: 'allowed', age: 28);
          final inactive = await db.users.create(
            username: 'inactive',
            age: 30,
            nickname: 'team',
            active: false,
          );
          final other = await db.users.create(username: 'other', age: 40);
          final scope = db.users
              .whereAny(username: eq('allowed'), nickname: eq('team'))
              .where(active: eq(true));

          expect((await scope.get(allowed.id))?.id, allowed.id);
          expect(await scope.get(inactive.id), isNull);
          expect(await scope.get(other.id), isNull);
          expect(await scope.update(inactive.id, age: 99), isNull);
          expect(await scope.update(other.id, age: 99), isNull);
          expect((await scope.update(allowed.id, age: 29))?.age, 29);
          expect(await scope.delete(inactive.id), 0);
          expect(await scope.delete(other.id), 0);
          expect(await scope.delete(allowed.id), 1);
          expect((await db.users.get(inactive.id))?.age, 30);
          expect((await db.users.get(other.id))?.age, 40);
        });

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
          expect(
            () => query.whereAnyFields({'missing': eq<Object?>(1)}),
            throwsArgumentError,
          );
          await expectLater(
            query.selectRows(['missing'], (row) => row),
            throwsArgumentError,
          );
          expect(() => db.users.select<PostCard>(), throwsArgumentError);
          expect(() => db.users.where(), throwsArgumentError);
          expect(() => db.users.whereAny(), throwsArgumentError);
          await expectLater(
            query.whereAnyFields({'age': eq<Object?>('old')}).all(),
            throwsArgumentError,
          );
          await expectLater(
            query.whereAnyFields({'age': eq<Object?>('old')}).count(),
            throwsArgumentError,
          );
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
            db.users.whereAny(id: eq(1)).create(username: 'invalid', age: 1),
            throwsStateError,
          );
          await expectLater(
            db.users
                .whereAny(id: eq(1))
                .createIfAbsent(.username, username: 'invalid', age: 1),
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
              .whereAny(sku: eq('p'), name: eq('Other'))
              .where(stock: gte(2))
              .decrement(product.id, stock: 2);
          expect(updated!.stock, 0);
          expect(updated.priceCents, 4900);
          expect(fixture.statements, hasLength(1));
          expect(fixture.statements.single.sql, match.startsWith('UPDATE'));
          expect(fixture.statements.single.sql, contains('RETURNING'));
          expect(
            await fixture.db.products
                .whereAny(sku: eq('p'), name: eq('Other'))
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

        test('unique claims ignore only the chosen key and leave existing rows unchanged', () async {
          final db = fixture.db;
          final first = await db.users.createIfAbsent(
            .username,
            username: 'claim',
            age: 28,
          );
          expect(first!.username, 'claim');
          fixture.events.clear();
          expect(
            await db.users.createIfAbsent(
              .username,
              username: 'claim',
              age: 99,
              nickname: 'new',
            ),
            isNull,
          );
          expect(fixture.statements, hasLength(1));
          expect(
            fixture.statements.single.sql,
            contains('ON CONFLICT ("username") DO NOTHING RETURNING'),
          );
          final existing = (await db.users.get(first.id))!;
          expect(existing.age, 28);
          expect(existing.nickname, isNull);
          final query = TableQuery<List<Object?>>(
            db.session,
            frozenSchema.tables.first,
            (row) => row,
          );
          fixture.events.clear();
          expect(
            () => query.insertIfAbsent({
              'username': 'u',
              'age': 1,
            }, conflictField: 'age'),
            throwsArgumentError,
          );
          expect(
            () => query.insertIfAbsent({'age': 1}, conflictField: 'username'),
            throwsArgumentError,
          );
          expect(
            () => query.insertIfAbsent({
              'username': null,
              'age': 1,
            }, conflictField: 'username'),
            throwsArgumentError,
          );
          expect(fixture.events, isEmpty);
          await expectLater(
            db.orders.createIfAbsent(
              .requestKey,
              userId: 999,
              requestKey: 'invalid',
              requestSignature: '1:1',
              createdAt: DateTime.now(),
            ),
            throwsException,
          );
          expect(await db.orders.all(), isEmpty);
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
          final extremes = fixture.db.users.whereAny(
            username: eq('max'),
            age: eq(minInteger),
          );
          expect(await extremes.increment(max.id, age: 1), isNull);
          expect(await extremes.decrement(min.id, age: 1), isNull);
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

        test('largest native integer delta preserves exact bounds', () async {
          const maxInteger = 9223372036854775807;
          const minInteger = -9223372036854775808;
          final user = await fixture.db.users.create(username: 'delta', age: 0);
          expect(
            (await fixture.db.users.increment(user.id, age: maxInteger))!.age,
            maxInteger,
          );
          expect(
            await fixture.db.users.increment(user.id, age: maxInteger),
            isNull,
          );
          expect(
            (await fixture.db.users.decrement(user.id, age: maxInteger))!.age,
            0,
          );
          expect(
            (await fixture.db.users.decrement(user.id, age: maxInteger))!.age,
            -maxInteger,
          );
          expect(
            await fixture.db.users.decrement(user.id, age: maxInteger),
            isNull,
          );
          expect((await fixture.db.users.get(user.id))!.age, -maxInteger);
          await fixture.db.users.update(user.id, age: minInteger);
          expect(
            (await fixture.db.users.increment(user.id, age: maxInteger))!.age,
            -1,
          );
          fixture.events.clear();
          // Native int overflow produces a negative delta, which must fail
          // validation before any assignment or guard is sent to the engine.
          final wrapped = int.parse(maxInteger.toString()) + 1;
          await expectLater(
            fixture.db.users.increment(user.id, age: wrapped),
            throwsArgumentError,
          );
          expect(fixture.statements, isEmpty);
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
              query.whereAnyFields({
                'id': oneOf<Object?>([1, 2]),
                'username': oneOf<Object?>(['one', 'two']),
              }).all(),
              throwsUnsupportedError,
            );
            await expectLater(
              query.whereAnyFields({
                'id': oneOf<Object?>([1, 2]),
                'username': oneOf<Object?>(['one', 'two']),
              }).count(),
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
  String get schema => delegate.schema;
  @override
  bool get inTransaction => delegate.inTransaction;
  @override
  Capabilities get capabilities =>
      const Capabilities(returning: false, maxParameters: 3);
  @override
  Future<QueryResult> run(String sql, {List<Object?> parameters = const []}) =>
      delegate.run(sql, parameters: parameters);
}
