@Tags(['postgres'])
library;

import 'package:orm/driver.dart';
import 'package:orm/orm.dart';

import 'dart:io';

import 'package:orm/generate.dart';
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
      final admin = Database.fromSql(
        postgres(PostgresOptions(url: Uri.parse(url!), tls: .disable)),
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
@Model(table: 'Users', namespace: 'auth')
class Account {
  @Id(generated: true) final int id;
  @Column(name: 'DisplayName') final String name;
  const Account({required this.id, required this.name});
}
''');
        await fixture.write('lib/schema/public/users.dart', '''
import 'package:orm/schema.dart';
import '../auth/users.dart';
@Model(table: 'Users')
class Profile {
  @Id(generated: true) final int id;
  final String name;
  @Relation(target: Account, name: 'account') final int accountId;
  const Profile({required this.id, required this.name, required this.accountId});
}
''');
        await writeGeneratedSchema(
          fixture.file('lib/schema').path,
          dialect: .postgres,
        );
        await fixture.write(
          'bin/namespaces.dart',
          r'''import 'package:orm/orm.dart';
import 'package:orm/sql.dart';
import 'package:orm/driver.dart';
import 'dart:io';
import 'package:orm/postgres.dart';
import 'package:orm/migrate.dart';
import '../lib/schema.orm.dart';

Future<void> main() async {
  final db = Database.fromSql(postgres(PostgresOptions(url: Uri.parse(Platform.environment['ORM_NAMESPACE_TEST_URL']!), tls: .disable)));
  try {
    final initial = Migration.create('0001_initial', appSchema, dialect: .postgres);
    await Migrator(db.sql).apply([initial]);
    final Account account = await db.account.create(name: 'Alice');
    final Profile profile = await db.profile.create(name: 'Profile', accountId: account.id);
    final owner = await db.profile.byId(profile.id).select((u) => u.account.select((a) => a.name).required()).single();
    if (owner != 'Alice') throw StateError('Wrong relationship target: $owner');
    await db.session((session) async {
      await session.execute(SqlCommand('SET search_path TO auth'));
      await session.execute(SqlCommand('CREATE TEMP TABLE "Users" (id bigint, name text)'));
      final rows = await session.profile.get();
      if (rows.single.name != 'Profile') throw StateError('Session state changed table target.');
      final verification = await verifySchema(session.sql, initial.snapshot!);
      if (!verification.matches) throw StateError(verification.differences.join('\n'));
    });
    if ((await db.account.get()).single.name != 'Alice') throw StateError('Wrong namespace.');
    print('namespace-client-ok');
  } finally { await db.close(); }
}
''',
        );
        final result = await Process.run(
          Platform.resolvedExecutable,
          ['run', 'orm_build_fixture:namespaces'],
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
    tags: 'postgres',
  );
}
