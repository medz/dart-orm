import 'package:orm/database.dart';
import 'package:test/test.dart';

import '../example/shop.dart';
import 'support/database.dart';

void main() {
  for (final engine in Engine.values) {
    group(
      'complete shop on ${engine.name}',
      () {
        late TestDatabase fixture;
        setUp(() async => fixture = await openTestDatabase(engine));
        tearDown(() => fixture.db.close());

        test(
          'relationship loading uses two SELECTs and direct typed fields',
          () async {
            final db = fixture.db;
            final one = await db.users.create(username: 'seven', age: 28);
            final two = await db.users.create(username: 'second', age: 30);
            await db.posts.create(authorId: one.id, title: 'first');
            await db.posts.create(authorId: one.id, title: 'next');
            await db.posts.create(authorId: two.id, title: 'other');
            fixture.events.clear();
            final users = await usersWithPosts(db);
            expect(users.first.user.username, 'seven');
            expect(users.first.posts.map((post) => post.title), [
              'first',
              'next',
            ]);
            expect(users.last.posts.single.title, 'other');
            expect(
              fixture.statements.where(
                (event) => event.sql.startsWith('SELECT'),
              ),
              hasLength(2),
            );
            final result = await searchUsers(db, 'sev');
            expect(result.users.single.username, 'seven');
            expect(result.total, 1);
          },
        );

        test(
          'prefix search returns a total and page in two read-only SELECTs',
          () async {
            final db = fixture.db;
            final username = await db.users.create(
              username: 'sev%_!one',
              age: 28,
            );
            final nickname = await db.users.create(
              username: 'second',
              age: 30,
              nickname: 'sev%_!two',
            );
            final both = await db.users.create(
              username: 'sev%_!both',
              age: 40,
              nickname: 'sev%_!both',
            );
            await db.users.create(
              username: 'sev%_!disabled',
              age: 28,
              nickname: 'sev%_!disabled',
              active: false,
            );
            await db.users.create(
              username: 'sevXX!one',
              age: 28,
              nickname: 'sevXX!two',
            );
            fixture.events.clear();
            final matches = await searchUsers(db, 'sev%_!');
            expect(matches.users.map((row) => row.id), [
              username.id,
              nickname.id,
              both.id,
            ]);
            expect(matches.total, 3);
            final selects = fixture.statements
                .where((event) => event.sql.startsWith('SELECT'))
                .toList();
            expect(selects, hasLength(2));
            expect(selects.map((event) => event.rows), [1, 3]);
            expect(
              selects.every((event) => !event.sql.contains('"avatar"')),
              isTrue,
            );
            expect(
              selects.every((event) => !event.sql.contains('sev')),
              isTrue,
            );
            final work = fixture.events
                .where(
                  (event) =>
                      event.kind != 'statement' ||
                      event.sql.startsWith('SELECT'),
                )
                .toList();
            expect(work.map((event) => event.kind), [
              'begin',
              'statement',
              'statement',
              'commit',
            ]);
            expect(work.map((event) => event.transactionId).toSet(), {
              work.first.transactionId,
            });
            expect(work.first.transactionId, isNotNull);
            if (engine == Engine.postgresql) {
              expect(work.first.sql, contains('READ ONLY'));
            } else {
              expect(
                fixture.statements.map((event) => event.sql),
                contains('PRAGMA query_only = ON'),
              );
            }
          },
        );

        test(
          'search paging keeps the filtered total for empty and later pages',
          () async {
            final db = fixture.db;
            final first = await db.users.create(username: 'page one', age: 20);
            final second = await db.users.create(
              username: 'second',
              age: 21,
              nickname: 'page two',
            );
            await db.users.create(
              username: 'page disabled',
              age: 22,
              active: false,
            );
            await db.users.create(username: 'outside', age: 23);
            for (final check in [
              (prefix: 'page ', offset: 0, total: 2, ids: [first.id]),
              (prefix: 'page ', offset: 1, total: 2, ids: [second.id]),
              (prefix: 'page ', offset: 10, total: 2, ids: <int>[]),
              (prefix: 'absent', offset: 0, total: 0, ids: <int>[]),
            ]) {
              fixture.events.clear();
              final result = await searchUsers(
                db,
                check.prefix,
                offset: check.offset,
                limit: 1,
              );
              expect(result.total, check.total);
              expect(result.users.map((user) => user.id), check.ids);
              final selects = fixture.statements.where(
                (event) => event.sql.startsWith('SELECT'),
              );
              expect(selects, hasLength(2));
              expect(selects.map((event) => event.rows), [1, check.ids.length]);
              expect(
                fixture.events.where((event) => event.kind == 'begin'),
                hasLength(1),
              );
              expect(
                fixture.events.where((event) => event.kind == 'commit'),
                hasLength(1),
              );
            }
          },
        );

        test(
          'invalid search paging fails before a transaction or SQL',
          () async {
            fixture.events.clear();
            for (final page in [
              (offset: -1, limit: 1),
              (offset: 0, limit: 0),
              (offset: 0, limit: 101),
            ]) {
              await expectLater(
                () => searchUsers(
                  fixture.db,
                  'prefix',
                  offset: page.offset,
                  limit: page.limit,
                ),
                throwsArgumentError,
              );
            }
            expect(fixture.events, isEmpty);
          },
        );

        test(
          'checkout freezes cents, merges duplicate items and replays once',
          () async {
            final db = fixture.db;
            final user = await db.users.create(username: 'seven', age: 28);
            final product = await db.products.create(
              sku: 'book',
              name: 'Book',
              priceCents: 4900,
              stock: 10,
            );
            fixture.events.clear();
            final receipt = await checkout(
              db,
              userId: user.id,
              requestKey: 'request',
              items: [
                (productId: product.id, quantity: 1),
                (productId: product.id, quantity: 2),
              ],
            );
            expect(receipt.order.totalCents, 14700);
            expect(receipt.order.status, 'placed');
            expect(receipt.replayed, isFalse);
            expect(receipt.lines.single.quantity, 3);
            expect(receipt.lines.single.unitPriceCents, 4900);
            expect(fixture.statements, hasLength(4));
            expect(
              fixture.statements.any((event) => event.sql.startsWith('SELECT')),
              isFalse,
            );
            await db.products.update(product.id, priceCents: 9999);
            fixture.events.clear();
            final replay = await checkout(
              db,
              userId: user.id,
              requestKey: 'request',
              items: [(productId: product.id, quantity: 3)],
            );
            expect(replay.order.id, receipt.order.id);
            expect(replay.order.totalCents, 14700);
            expect(replay.lines.single.unitPriceCents, 4900);
            expect(replay.replayed, isTrue);
            expect(fixture.statements, hasLength(3));
            expect((await db.products.get(product.id))!.stock, 7);
            await expectLater(
              checkout(
                db,
                userId: user.id,
                requestKey: 'request',
                items: [(productId: product.id, quantity: 1)],
              ),
              throwsStateError,
            );
            expect((await db.products.get(product.id))!.stock, 7);
          },
        );

        test('sold-out second item rolls back every earlier write', () async {
          final db = fixture.db;
          final user = await db.users.create(username: 'seven', age: 28);
          final first = await db.products.create(
            sku: 'first',
            name: 'First',
            priceCents: 100,
            stock: 10,
          );
          final last = await db.products.create(
            sku: 'last',
            name: 'Last',
            priceCents: 200,
            stock: 0,
          );
          fixture.events.clear();
          await expectLater(
            checkout(
              db,
              userId: user.id,
              requestKey: 'sold-out',
              items: [
                (productId: first.id, quantity: 2),
                (productId: last.id, quantity: 1),
              ],
            ),
            throwsStateError,
          );
          expect(
            fixture.events.where((event) => event.kind == 'rollback'),
            hasLength(1),
          );
          expect((await db.products.get(first.id))!.stock, 10);
          expect(await db.orders.all(), isEmpty);
          expect(await db.orderLines.all(), isEmpty);
          await db.products.increment(last.id, stock: 1);
          final success = await checkout(
            db,
            userId: user.id,
            requestKey: 'sold-out',
            items: [
              (productId: first.id, quantity: 2),
              (productId: last.id, quantity: 1),
            ],
          );
          expect(success.order.totalCents, 400);
          expect(success.lines, hasLength(2));
        });

        test(
          'concurrent replay produces one order and one stock debit',
          () async {
            final db = fixture.db;
            final user = await db.users.create(username: 'seven', age: 28);
            final product = await db.products.create(
              sku: 'book',
              name: 'Book',
              priceCents: 100,
              stock: 3,
            );
            final receipts = await Future.wait([
              checkout(
                db,
                userId: user.id,
                requestKey: 'same',
                items: [(productId: product.id, quantity: 2)],
              ),
              checkout(
                db,
                userId: user.id,
                requestKey: 'same',
                items: [(productId: product.id, quantity: 2)],
              ),
            ]);
            expect(
              receipts.map((receipt) => receipt.order.id).toSet(),
              hasLength(1),
            );
            expect(receipts.where((receipt) => receipt.replayed), hasLength(1));
            expect((await db.products.get(product.id))!.stock, 1);
            expect(await db.orders.all(), hasLength(1));
            expect(await db.orderLines.all(), hasLength(1));
          },
        );

        test(
          'concurrent distinct requests cannot oversell the last unit',
          () async {
            final db = fixture.db;
            final user = await db.users.create(username: 'seven', age: 28);
            final product = await db.products.create(
              sku: 'last',
              name: 'Last',
              priceCents: 100,
              stock: 1,
            );
            Future<bool> attempt(String key) async {
              try {
                await checkout(
                  db,
                  userId: user.id,
                  requestKey: key,
                  items: [(productId: product.id, quantity: 1)],
                );
                return true;
              } on StateError {
                return false;
              }
            }

            expect(
              (await Future.wait([attempt('one'), attempt('two')]))
                  .where((ok) => ok),
              hasLength(1),
            );
            expect((await db.products.get(product.id))!.stock, 0);
            expect(await db.orders.all(), hasLength(1));
          },
        );

        test('invalid carts fail before SQL', () async {
          await expectLater(
            checkout(
              fixture.db,
              userId: 1,
              requestKey: 'bad key',
              items: [(productId: 1, quantity: 1)],
            ),
            throwsArgumentError,
          );
          await expectLater(
            checkout(fixture.db, userId: 1, requestKey: 'key', items: []),
            throwsArgumentError,
          );
          await expectLater(
            checkout(
              fixture.db,
              userId: 1,
              requestKey: 'key',
              items: [
                (productId: 1, quantity: 99),
                (productId: 1, quantity: 1),
              ],
            ),
            throwsArgumentError,
          );
          expect(fixture.events, isEmpty);
        });
      },
      skip: engine == Engine.postgresql && !hasPostgres
          ? 'Set ORM_TEST_POSTGRES_HOST or ORM_TEST_POSTGRES_SOCKET for a real database'
          : false,
    );
  }
}
