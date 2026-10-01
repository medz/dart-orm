@Tags(['postgres'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:orm/postgres.dart';
import 'package:test/test.dart';

import '../tool/src/build_fixture.dart';

void main() {
  final url = Platform.environment['ORM_TEST_POSTGRES'];
  test(
    'fresh PostgreSQL consumer generates, migrates and returns original DTOs',
    () async {
      final fixture = await BuildFixture.create(
        ormPath: Directory.current.path,
      );
      final namespace =
          'orm_annotated_${pid}_${DateTime.now().microsecondsSinceEpoch}';
      final admin = postgres(
        PostgresOptions(url: Uri.parse(url!), tls: .disable),
      );
      try {
        await fixture.file('lib/schema.dart').delete();
        final factoryProbe = fixture.file('factory-executed.txt');
        final source = await File('example/annotated/models.dart')
            .readAsString();
        await fixture.write(
          'lib/models.dart',
          "import 'dart:io';\n${source.replaceFirst("String nextMarker() => 'marker-\${++markerCalls}';", 'String nextMarker() { probeFactory(); return \'marker-\${++markerCalls}\'; }').replaceFirst('DateTime nextInstant() {', 'DateTime nextInstant() { probeFactory();')}\n"
              'void probeFactory() => File(${jsonEncode(factoryProbe.path)}).writeAsStringSync("called");\n',
        );
        await fixture.write('orm.config.dart', '''
import 'package:orm/config.dart';
void main() => defineConfig(
  database: .postgres,
  defaultNamespace: '$namespace',
  models: 'lib/models.dart',
  output: 'lib/models.orm.dart',
  migrations: 'migrations',
);
''');
        await fixture.write('bin/annotated.dart', _consumer);
        expect(await fixture.file('lib/models.orm.dart').exists(), false);
        expect(await fixture.file('lib/models.snapshot.dart').exists(), false);
        await fixture.run(['run', 'orm', 'generate']);
        expect(
          await factoryProbe.exists(),
          false,
          reason: 'Generation must not execute application factories.',
        );
        await fixture.run(['run', 'orm', 'migrate', 'create', '0001_initial']);
        expect(
          await factoryProbe.exists(),
          false,
          reason: 'Migration creation must not execute application factories.',
        );
        final migration = await fixture
            .file('migrations/m0001_initial.dart')
            .readAsString();
        expect(migration, isNot(contains('models.dart')));
        await fixture.run(['analyze']);
        final result = await fixture.run([
          'run',
          'orm_build_fixture:annotated',
        ]);
        expect(result.output, contains('annotated-postgres-ok'));
        expect(
          await factoryProbe.exists(),
          true,
          reason:
              'Actual inserts must exercise the cross-process factory probe.',
        );
      } finally {
        try {
          // Only this consumer's unique namespace is eligible for cleanup.
          await admin.execute(
            SqlCommand('DROP SCHEMA IF EXISTS "$namespace" CASCADE'),
          );
        } finally {
          await admin.close();
          await fixture.dispose();
        }
      }
    },
    skip: url == null
        ? 'Set ORM_TEST_POSTGRES to an isolated test database.'
        : false,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

const _consumer = r'''
import 'dart:io';
import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm_build_fixture/models.dart' as original;
import 'package:orm_build_fixture/models.orm.dart';
import 'package:orm_build_fixture/models.snapshot.dart' as physical;
import '../migrations/m0001_initial.dart' as initial;

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final namespace = physical.schema.tables.first.namespace!;
  final events = <QueryEvent>[];
  final db = postgres(PostgresOptions(
    url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
    tls: .disable,
    schema: namespace,
  ), onQuery: events.add);
  try {
    await db.execute(SqlCommand('CREATE SCHEMA "$namespace"'));
    final migrator = Migrator(db.sql);
    check((await migrator.apply([initial.migration])).single == '0001_initial',
        'The freshly saved migration was not applied.');
    check((await migrator.apply([initial.migration])).isEmpty,
        'Applying the saved migration twice must be a no-op.');
    check((await verifySchema(db.sql, physical.schema)).matches,
        'Generated metadata differs from the PostgreSQL catalog.');
    check(original.markerCalls == 0 && original.instantCalls == 0,
        'Applying the saved migration executed application default factories.');

    final User created = await db.user.create(email: 'fresh@example.com');
    final original.User row = created;
    check(row.id > 0 && row.greeting() == 'Hello, Anonymous',
        'Generated identity or original DTO business method was lost.');
    check(row.active && row.marker == 'marker-1' && row.score == 7,
        'Database/client defaults and constructor fallback were not preserved.');
    await db.user.byId(row.id).patch(name: .set('Changed'), nickname: .set(null));
    final original.User patched = await db.user.byId(row.id).single();
    check(patched.greeting() == 'Hello, Changed' && patched.nickname == null,
        'Patch/read lost original DTO identity or explicit null.');
    check(patched.active && patched.marker == 'marker-1' && original.markerCalls == 1,
        'Patch/read reapplied insert defaults.');

    final original.Post post = await db.post.create(authorId: row.id, title: 'Fresh');
    check(post.summary() == 'Fresh (draft)' && original.instantCalls == 1,
        'PostgreSQL returning lost defaults or the original Post method.');
    events.clear();
    final original.User author = await db.post.byId(post.id)
        .select((p) => p.author.required()).single();
    check(author.greeting() == 'Hello, Changed' && events.length == 1,
        'To-one relation lost the original DTO or issued extra queries.');
    events.clear();
    final List<original.Post> posts = await db.user.byId(row.id)
        .select((u) => u.posts.many()).single();
    check(posts.single.summary() == 'Fresh (draft)' && events.length == 2,
        'Inverse relation lost original DTOs or batched loading.');
    check(await db.user.byId(row.id).delete().execute() == 1,
        'Delete did not report the affected row.');
    check(await db.user.count() == 0 && await db.post.count() == 0,
        'Delete/cascade left generated rows behind.');
    check((await verifySchema(db.sql, physical.schema)).matches,
        'CRUD changed the generated schema.');
    print('annotated-postgres-ok');
  } finally {
    await db.close();
  }
}
''';
