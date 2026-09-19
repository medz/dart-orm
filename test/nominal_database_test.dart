import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import 'support/nominal/schema.dart' show Email;
import 'support/nominal/schema.orm.dart';

void main() {
  runNominalTests('sqlite', () => sqlite(const SqliteOptions.memory()));
  final url = Platform.environment['ORM_TEST_POSTGRES'];
  if (url != null) {
    const schema = 'orm_nominal_tests';
    late Database<Postgres> admin;
    setUpAll(() async {
      admin = postgres(
        PostgresOptions(url: Uri.parse(url), tls: PostgresTls.disable),
      );
      await admin.execute(SqlCommand('CREATE SCHEMA IF NOT EXISTS "$schema"'));
    });
    tearDownAll(() async {
      await admin.execute(SqlCommand('DROP SCHEMA "$schema" CASCADE'));
      await admin.close();
    });
    runNominalTests(
      'postgres',
      () async => postgres(
        PostgresOptions(
          url: Uri.parse(url),
          tls: PostgresTls.disable,
          schema: schema,
        ),
      ),
    );
  }
}

void runNominalTests(String name, Future<Database<Backend>> Function() open) {
  group('nominal models $name', () {
    late Database<Backend> db;
    setUp(() async {
      db = await open();
      for (final table in ['nominal_notes', 'nominal_accounts']) {
        await db.execute(SqlCommand('DROP TABLE IF EXISTS "$table"'));
      }
      for (final command in createSchema(appSchema, db.dialect)) {
        await db.execute(command);
      }
    });
    tearDown(() => db.close());

    test(
      'rows, insert defaults, codecs and patches retain nominal types',
      () async {
        final Account account = await db.accounts.create(
          email: const Email('a@example.com'),
          a: 2,
          b: 3,
          c: 4,
        );
        expect(account, isA<Account>());
        expect(account.email.value, 'a@example.com');
        expect(account.label, isNull);
        expect(account.enabled, false);
        expect(account.marker, 'seed');
        expect(account.total, 5);
        await db.accounts
            .byId(account.id)
            .patch(label: .set('Account'), enabled: .set(true));
        final Account updated = await db.accounts.byId(account.id).single();
        expect(updated.label, 'Account');
        expect(updated.enabled, true);
        await db.accounts.byId(account.id).patch(label: .set(null));
        expect((await db.accounts.byId(account.id).single()).label, isNull);
      },
    );

    test(
      'relations return nominal rows while projections retain their own types',
      () async {
        final Account owner = await db.transaction((tx) async {
          final Account owner = await tx.accounts.create(
            email: const Email('owner@example.com'),
            a: 1,
            b: 2,
            c: 3,
          );
          final Note note = await tx.notes.create(
            accountId: owner.id,
            body: 'hello',
          );
          expect(note, isA<Note>());
          return owner;
        });
        final List<Note> children = await db.accounts
            .byId(owner.id)
            .select((a) => a.notes.many())
            .single();
        expect(children.single.body, 'hello');
        final Account related = await db.notes
            .select((n) => n.account.required())
            .single();
        expect(related.email.value, 'owner@example.com');
        final ({int id, List<String> notes}) card = await db.accounts
            .byId(owner.id)
            .select(
              (a) => (
                a.id,
                a.notes.select((n) => n.body).many(),
              ).map((id, notes) => (id: id, notes: notes)),
            )
            .single();
        expect(card.id, owner.id);
        expect(card.notes, ['hello']);
        await db.accounts.byId(owner.id).delete().execute();
        expect(await db.notes.count(), 0);
      },
    );
  });
}
