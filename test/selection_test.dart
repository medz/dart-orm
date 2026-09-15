import 'dart:io';

import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import 'support/tables.dart';

void main() {
  for (final dialect in SqlDialect.values) {
    group(
      'selection ${dialect.name}',
      () {
        late Database<Backend> db;
        final sqlEvents = <QueryEvent>[], decodeEvents = <DecodeEvent>[];
        setUp(() async {
          if (dialect == .sqlite) {
            db = await sqlite(
              const SqliteOptions.memory(),
              onQuery: sqlEvents.add,
              onDecode: decodeEvents.add,
            );
          } else {
            db = postgres(
              PostgresOptions(
                url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
                tls: .disable,
                schema: 'orm_selection_tests',
              ),
              onQuery: sqlEvents.add,
              onDecode: decodeEvents.add,
            );
            await db.execute(
              SqlCommand('DROP SCHEMA IF EXISTS orm_selection_tests CASCADE'),
            );
            await db.execute(SqlCommand('CREATE SCHEMA orm_selection_tests'));
          }
          await createTables(db);
          await db
              .table(users)
              .createRow((u) => [u.email.set('one'), u.score.set(2)]);
          sqlEvents.clear();
          decodeEvents.clear();
        });
        tearDown(() => db.close());

        test('all typed arities defer mapping and preserve left-to-right evaluation', () async {
          for (var arity = 2; arity <= 6; arity++) {
            final calls = <String>[];
            Selection<T> track<T>(Selection<T> field, String label) =>
                field.map((value) {
                  calls.add(label);
                  return value;
                });
            final query = db.table(users).select((u) {
              final a = track(u.id, 'id'),
                  b = track(u.email, 'email'),
                  c = track(u.nickname, 'nullable'),
                  d = track(u.score, 'score'),
                  e = track(u.score.gt(1), 'active');
              List<Object?> done(List<Object?> values) {
                calls.add('result');
                return values;
              }

              return switch (arity) {
                2 => (a, b).map((a, b) => done([a, b])),
                3 => (a, b, c).map((a, b, c) => done([a, b, c])),
                4 => (a, b, c, d).map((a, b, c, d) => done([a, b, c, d])),
                5 => (
                  a,
                  b,
                  c,
                  d,
                  e,
                ).map((a, b, c, d, e) => done([a, b, c, d, e])),
                _ => (
                  a,
                  b,
                  c,
                  d,
                  e,
                  a,
                ).map((a, b, c, d, e, f) => done([a, b, c, d, e, f])),
              };
            });
            final command = query.compile(), plan = query.inspect();
            expect(calls, isEmpty);
            expect(plan.sql, command.sql);
            expect(plan.columns, hasLength(arity == 6 ? 5 : arity));
            expect(
              await query.single(),
              [1, 'one', null, 2, true, 1].take(arity),
            );
            expect(calls, [
              ...[
                'id',
                'email',
                'nullable',
                'score',
                'active',
                'id',
              ].take(arity),
              'result',
            ]);
            calls.clear();
            // Reusing a selection must re-evaluate each output occurrence per row.
            expect(
              await query.stream(batchSize: 1).single,
              [1, 'one', null, 2, true, 1].take(arity),
            );
            expect(calls, [
              ...[
                'id',
                'email',
                'nullable',
                'score',
                'active',
                'id',
              ].take(arity),
              'result',
            ]);
          }
        });

        test(
          'first decoder failure prevents later fields and outer mapper',
          () async {
            final failure = StateError('decode failed'), calls = <String>[];
            final query = db
                .table(users)
                .select(
                  (u) =>
                      (
                        u.id.map<int>((_) {
                          calls.add('first');
                          throw failure;
                        }),
                        u.email.map((value) {
                          calls.add('second');
                          return value;
                        }),
                      ).map((id, email) {
                        calls.add('result');
                        return (id, email);
                      }),
                );
            query.inspect();
            expect(calls, isEmpty);
            await expectLater(query.get(), throwsA(same(failure)));
            expect(calls, ['first']);
            expect(sqlEvents.single.error, isNull);
            expect(decodeEvents.single.error, same(failure));
            expect(await db.table(users).count(), 1);
          },
        );

        test(
          'dynamic fields snapshot keys and preserve nulls and mapping order',
          () async {
            final selected = <String, Selection<Object?>>{}, calls = <String>[];
            final query = db.table(users).select((u) {
              selected.addAll({
                'label': u.email.map((v) {
                  calls.add('label');
                  return v;
                }),
                'empty': u.nickname.map((v) {
                  calls.add('empty');
                  return v;
                }),
                'repeated': u.email.map((v) {
                  calls.add('repeated');
                  return v;
                }),
              });
              return fields(selected);
            });
            selected.clear();
            expect(query.inspect().columns, hasLength(2));
            expect(calls, isEmpty);
            final result = await query.single();
            expect(result, {'label': 'one', 'empty': null, 'repeated': 'one'});
            expect(result.keys, ['label', 'empty', 'repeated']);
            expect(calls, ['label', 'empty', 'repeated']);
            expect(
              () => db.table(users).select((_) => fields({})).compile(),
              throwsA(
                isA<OrmException>().having(
                  (e) => e.code,
                  'code',
                  'QUERY.EMPTY_SELECTION',
                ),
              ),
            );
          },
        );
      },
      skip:
          dialect == .postgres &&
              Platform.environment['ORM_TEST_POSTGRES'] == null
          ? 'Set ORM_TEST_POSTGRES.'
          : false,
    );
  }
}
