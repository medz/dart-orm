import 'dart:io';

import 'package:orm/postgres.dart';
import 'package:test/test.dart';

import '../tool/src/build_fixture.dart';

void main() {
  final url = Platform.environment['ORM_TEST_POSTGRES'];
  test(
    'generated namespace clients execute cross-schema relations on PostgreSQL',
    () async {
      final fixture = await BuildFixture.create(
        ormPath: Directory.current.path,
      );
      final admin = postgres(
        PostgresOptions(url: Uri.parse(url!), tls: .disable),
      );
      final name =
          'orm_namespace_${pid}_${DateTime.now().microsecondsSinceEpoch}';
      var created = false;
      try {
        await admin.execute(SqlCommand('CREATE DATABASE "$name"'));
        created = true;
        await fixture.file('lib/schema.dart').delete();
        await fixture.write('lib/schema/auth/users.dart', '''
import 'package:orm/schema.dart';
final user = model('Users', (id: identity(), name: text(name: 'DisplayName')));
''');
        await fixture.write('lib/schema/public/users.dart', '''
import 'package:orm/schema.dart';
import '../auth/users.dart' as auth;
final user = model('Users', (id: identity(), name: text(), accountId: integer()),
  relations: (u) => (account: references(u.accountId, () => auth.user),));
''');
        await fixture.run([
          'run',
          'orm',
          'generate',
          'lib/schema',
          '--database',
          'postgres',
        ]);
        await fixture.write('bin/namespaces.dart', r'''
import 'dart:io';
import 'package:orm/postgres.dart';
import 'package:orm/migrate.dart';
import '../lib/schema.orm.dart';

Future<List<Migration>> legacyHistory(Database<Postgres> db) async {
  TableSchema users({String? namespace, bool added = false}) => TableSchema(
    'LegacyUsers', namespace: namespace,
    columns: [Column('Id', Codecs.integer), if (added) Column('Name', Codecs.text, nullable: true)],
    primaryKey: ['Id'],
  );
  TableSchema posts({String? namespace}) => TableSchema('LegacyPosts', namespace: namespace,
    columns: [Column('UserId', Codecs.integer)],
    foreignKeys: [ForeignKey(['UserId'], 'LegacyUsers', ['Id'], targetNamespace: namespace)],
  );
  final legacy = Migration.create('0001_legacy', [users(), posts()], dialect: .postgres);
  final frozen = migrationSource(legacy);
  await Migrator(db.sql).apply([legacy]);
  await db.execute(SqlCommand('INSERT INTO "LegacyUsers" VALUES (42)'));
  await db.execute(SqlCommand('INSERT INTO "LegacyPosts" VALUES (42)'));
  final qualified = Migration.diff('0002_qualified', dialect: .postgres,
    from: legacy.snapshot!, to: SchemaSnapshot([users(namespace: 'public'), posts(namespace: 'public')]));
  if (qualified.steps.isNotEmpty) throw StateError('Qualification changed SQL: ${qualified.toJson()}');
  final upgrade = Migration.diff('0002_upgrade', dialect: .postgres, from: legacy.snapshot!,
    to: SchemaSnapshot([users(namespace: 'public', added: true), posts(namespace: 'public')]),
    previous: legacy.checksum);
  if (upgrade.steps.length != 1 || upgrade.steps.single is! ExecuteSql ||
      (upgrade.steps.single as ExecuteSql).sql != 'ALTER TABLE "public"."LegacyUsers" ADD COLUMN "Name" TEXT') {
    throw StateError('Unexpected upgrade: ${upgrade.toJson()}');
  }
  await Migrator(db.sql).apply([legacy, upgrade]);
  if (!(await verifySchema(db.sql, upgrade.snapshot!)).matches ||
      (await db.execute(SqlCommand('SELECT "UserId" FROM "public"."LegacyPosts"'))).rows.single.single != 42 ||
      migrationSource(legacy) != frozen) {
    throw StateError('Legacy upgrade changed data or frozen history.');
  }
  return [legacy, upgrade];
}

Future<void> main() async {
  final db = postgres(PostgresOptions(url: Uri.parse(Platform.environment['ORM_NAMESPACE_TEST_URL']!), tls: .disable));
  try {
    final history = await legacyHistory(db);
    final plan = Migration.create('0003_initial', appSchema, dialect: .postgres);
    final initial = Migration.steps(plan.id, plan.steps, dialect: .postgres,
      snapshot: plan.snapshot, previous: history.last.checksum);
    await Migrator(db.sql).apply([...history, initial]);
    final AuthUser account = await db.auth.user.create(name: 'Alice');
    final PublicUser profile = await db.public.user.create(name: 'Profile', accountId: account.id);
    final owner = await db.public.user.byId(profile.id).select((u) => u.account.select((a) => a.name).required()).single();
    if (owner != 'Alice') throw StateError('Wrong relationship target: $owner');
    await db.session((session) async {
      await session.execute(SqlCommand('SET search_path TO auth'));
      await session.execute(SqlCommand('CREATE TEMP TABLE "Users" (id bigint, name text)'));
      final rows = await session.public.user.get();
      if (rows.single.name != 'Profile') throw StateError('Session state changed table target.');
      final verification = await verifySchema(session.sql, initial.snapshot!);
      if (!verification.matches) throw StateError(verification.differences.join('\n'));
    });
    if ((await db.auth.user.get()).single.name != 'Alice') throw StateError('Wrong namespace.');
    print('namespace-client-ok');
  } finally { await db.close(); }
}
''');
        final result = await Process.run(
          Platform.resolvedExecutable,
          ['run', 'bin/namespaces.dart'],
          workingDirectory: fixture.directory.path,
          environment: {
            'ORM_NAMESPACE_TEST_URL': Uri.parse(url)
                .replace(path: '/$name')
                .toString(),
          },
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(result.stdout, contains('namespace-client-ok'));
      } finally {
        if (created) {
          await admin.execute(SqlCommand('DROP DATABASE "$name" WITH (FORCE)'));
        }
        await admin.close();
        await fixture.dispose();
      }
    },
    skip: url == null
        ? 'Set ORM_TEST_POSTGRES to a disposable PostgreSQL database.'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
