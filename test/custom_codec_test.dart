import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import 'support/codecs/alternate.dart' as alt;
import 'support/codecs/schema.dart' show Person;
import 'support/codecs/schema.orm.dart';
import 'support/codecs/types.dart';

void main() {
  runCodecTests('sqlite', () => sqlite(const SqliteOptions.memory()));
  final url = Platform.environment['ORM_TEST_POSTGRES'];
  if (url != null) {
    const schema = 'orm_codec_tests';
    late Database<Postgres> admin;
    setUpAll(() async {
      admin = postgres(PostgresOptions(url: Uri.parse(url), tls: .disable));
      await admin.execute(SqlCommand('CREATE SCHEMA IF NOT EXISTS "$schema"'));
    });
    tearDownAll(() async {
      await admin.execute(SqlCommand('DROP SCHEMA "$schema" CASCADE'));
      await admin.close();
    });
    runCodecTests(
      'postgres',
      () async => postgres(
        PostgresOptions(url: Uri.parse(url), tls: .disable, schema: schema),
      ),
    );
  }
}

void runCodecTests(String name, Future<Database<Backend>> Function() open) {
  group('custom codecs $name', () {
    late Database<Backend> db;
    final initial = Migration.create('0001_initial', appSchema);
    setUp(() async {
      db = await open();
      for (final table in ['notes', 'people', '_orm_migrations']) {
        await db.execute(SqlCommand('DROP TABLE IF EXISTS "$table"'));
      }
      await Migrator(db).apply([initial]);
    });
    tearDown(() => db.close());

    Future<Person> person({
      String email = 'seven@example.com',
      SqlJson? details,
    }) => db.people.create(
      email: Email(email),
      membership: .pending,
      tags: ['dart', '数据库'],
      location: (city: '成都', zone: 8),
      alternate: const alt.Email('different domain'),
      details: details,
    );
    String parameter(int i) => db.dialect == .postgres ? '\$$i' : '?$i';

    test(
      'generated custom values round trip through create, select and patch',
      () async {
        final value = await person();
        final PersonId id = value.id;
        expect(id.value, 1);
        expect(value.email.value, 'seven@example.com');
        expect(value.membership, Membership.pending);
        expect(value.previousMembership, isNull);
        expect(value.tags, ['dart', '数据库']);
        expect(value.location, (city: '成都', zone: 8));
        expect(value.alternate.label, 'different domain');
        final Query<({Email email, Location? location}), PeopleFields>
        projection = db.people
            .byId(id)
            .select(
              (p) => (
                p.email,
                p.location,
              ).map((email, location) => (email: email, location: location)),
            );
        expect((await projection.single()).email.value, value.email.value);
        await db.people
            .byId(id)
            .patch(
              email: .set(const Email('updated@example.com')),
              membership: .set(.cancelled),
              previousMembership: .set(.pending),
              tags: .set([]),
              location: .set(null),
            );
        final updated = await db.people.byId(id).single();
        expect(updated.email.value, 'updated@example.com');
        expect(updated.membership, Membership.cancelled);
        expect(updated.previousMembership, Membership.pending);
        expect(updated.location, isNull);
        expect(updated.tags, isEmpty);
      },
    );

    test('enum labels are stable text and unknown labels fail decoding', () async {
      final value = await person();
      expect(
        (await db.execute(SqlCommand('SELECT membership FROM people')))
            .rows
            .single,
        ['pending-payment'],
      );
      await db.people.byId(value.id).patch(membership: .set(.cancelled));
      expect(
        (await db.execute(SqlCommand('SELECT membership FROM people')))
            .rows
            .single,
        ['closed'],
      );
      await db.execute(
        SqlCommand("UPDATE people SET membership = 'future-value'"),
      );
      await expectLater(
        db.people.get(),
        throwsA(
          isA<OrmException>().having((e) => e.code, 'code', 'CODEC.ENUM'),
        ),
      );
      // Decoding is outside SQL execution; a bad value does not lose the lease.
      expect(await db.people.count(), 1);
    });

    test(
      'domain validation and bound parameters apply to writes and predicates',
      () async {
        final value = await person(email: "'@x'); DROP TABLE people; --");
        final query = db.people.where((p) => p.email.eq(value.email));
        final command = query.compile();
        expect(command.sql, isNot(contains(value.email.value)));
        expect(command.parameters, [value.email.value]);
        expect((await query.single()).id, value.id);
        final events = <QueryEvent>[];
        final observed = Database(db.driver, onQuery: events.add);
        await expectLater(
          () => observed.people.create(
            email: const Email('invalid'),
            membership: .active,
            tags: [],
            alternate: const alt.Email('a'),
          ),
          throwsFormatException,
        );
        expect(events, isEmpty);
        await db.execute(SqlCommand("UPDATE people SET email = 'invalid'"));
        await expectLater(db.people.single(), throwsFormatException);
        expect(await db.people.count(), 1);
      },
    );

    test(
      'JSON documents distinguish SQL NULL, JSON null and string scalars',
      () async {
        final value = await person();
        expect(value.details, isNull);
        expect(await db.people.where((p) => p.details.isNull()).count(), 1);
        for (final document in <Object?>[
          null,
          'plain string',
          'null',
          '"quoted"',
          42,
          true,
          <Object?>[null, 'x'],
          <String, Object?>{
            'nested': [null, '文本'],
          },
        ]) {
          await db.people
              .byId(value.id)
              .patch(details: .set(SqlJson(document)));
          final result = await db.people
              .byId(value.id)
              .select((p) => p.details)
              .single();
          expect(result, isA<SqlJson>());
          expect(result!.value, document);
          expect(await db.people.where((p) => p.details.isNull()).count(), 0);
          final raw = (await db.execute(
            SqlCommand('SELECT details FROM people'),
          )).rows.single.single;
          expect(Codecs.json.decode(raw), document);
        }
        await db.people.byId(value.id).patch(details: .set(null));
        expect((await db.people.single()).details, isNull);
      },
    );

    test('nullable structured codec rejects JSON null instead of masking invalid data', () async {
      final value = await person();
      await db.execute(
        SqlCommand('UPDATE people SET location = ${parameter(1)}', ['null']),
      );
      await expectLater(db.people.single(), throwsA(isA<TypeError>()));
      await db.people.byId(value.id).patch(location: .set(null));
      expect((await db.people.single()).location, isNull);
    });

    test('custom IDs and domain projections work across joined and batched relations', () async {
      final owner = await person();
      for (var i = 0; i < 3; i++) {
        await db.notes.create(ownerId: owner.id, body: 'note$i');
      }
      final events = <QueryEvent>[];
      final observed = Database(db.driver, onQuery: events.add);
      final emails = await observed.notes
          .select((n) => n.owner.select((p) => p.email).required())
          .get();
      expect(emails.map((e) => e.value), List.filled(3, owner.email.value));
      expect(events.length, 1);
      final children = await db.people
          .select(
            (p) => p.notes
                .orderBy((n) => [n.id.desc()])
                .take(2)
                .select(
                  (n) => (n.ownerId, n.body).map((id, body) => (id, body)),
                )
                .many(),
          )
          .single();
      expect(children, [(owner.id, 'note2'), (owner.id, 'note1')]);
      final batch = await db.notes
          .select(
            (n) =>
                n.owner.select((p) => p.membership).required(strategy: .batch),
          )
          .get();
      expect(batch, List.filled(3, Membership.pending));
    });

    test(
      'custom values participate in atomic batch writes and native upsert',
      () async {
        final ids = await db.people
            .insertMany(
              [1, 2, 3],
              (p, i) => [
                p.email.set(Email('batch$i@example.com')),
                p.membership.set(.active),
                p.tags.set(['$i']),
                p.alternate.set(const alt.Email('a')),
              ],
            )
            .returning((p) => p.id)
            .get();
        expect(ids.map((id) => id.value), [1, 2, 3]);
        await db.people
            .insert(
              (p) => [
                p.email.set(const Email('batch1@example.com')),
                p.membership.set(.cancelled),
                p.tags.set(['changed']),
                p.alternate.set(const alt.Email('b')),
              ],
            )
            .onConflictUpdate(
              target: (p) => [p.email],
              set: (existing, incoming) => [
                existing.membership.setExpression(incoming.membership),
                existing.tags.setExpression(incoming.tags),
              ],
            )
            .execute();
        final value = await db.people.byId(ids.first).single();
        expect(value.membership, Membership.cancelled);
        expect(value.tags, ['changed']);
        expect(await db.people.count(), 3);
      },
    );

    test(
      'custom IDs and enums survive cursor transport and streaming decoders',
      () async {
        final first = await person(
          email: 'first@example.com',
          details: const SqlJson('scalar'),
        );
        final second = await person(
          email: 'second@example.com',
          details: const SqlJson(null),
        );
        final token = db.people.cursorToken(
          (p) => [p.membership.cursor(first.membership), p.id.cursor(first.id)],
        );
        final rows = await db.people
            .seekToken(token, orderBy: (p) => [p.membership.asc(), p.id.asc()])
            .stream(batchSize: 1)
            .toList();
        expect(rows.single.id, second.id);
        expect(rows.single.details, isA<SqlJson>());
        expect(rows.single.details!.value, isNull);
        final docs = await db.people
            .orderBy((p) => [p.id.asc()])
            .select((p) => p.details)
            .stream(batchSize: 1)
            .toList();
        expect(docs.map((d) => d!.value), ['scalar', null]);
      },
    );

    test('migration snapshots retain physical storage without executing domain codecs', () async {
      final snapshot = SchemaSnapshot(appSchema);
      final restored = SchemaSnapshot.fromJson(snapshot.toJson());
      expect(restored.toJson(), snapshot.toJson());
      final verification = await verifySchema(db, restored);
      expect(verification.differences, isEmpty);
      expect(verification.unmanaged, isEmpty);
      final columns = await inspectColumns(db, 'people');
      expect(columns.firstWhere((c) => c.name == 'location').nullable, true);
      expect(columns.firstWhere((c) => c.name == 'membership').nullable, false);
      expect((await Migrator(db).history()).single.checksum, initial.checksum);
    });
  });
}
