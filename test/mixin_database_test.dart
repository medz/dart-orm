@Tags(['database'])
library;

import 'dart:io';

import 'package:orm/postgres.dart';
import 'package:test/test.dart';

import '../tool/src/build_fixture.dart';

void main() {
  final url = Platform.environment['ORM_TEST_POSTGRES'];
  for (final engine in ['sqlite', 'postgres']) {
    test(
      '$engine fresh optional mixin client retains shared fields and business methods',
      () async {
        final fixture = await BuildFixture.create(
          ormPath: Directory.current.path,
        );
        final namespace =
            'orm_mixin_${pid}_${DateTime.now().microsecondsSinceEpoch}';
        final admin = engine == 'postgres'
            ? postgres(PostgresOptions(url: Uri.parse(url!), tls: .disable))
            : null;
        try {
          await fixture.file('lib/schema.dart').delete();
          await fixture.write(
            'lib/models.dart',
            await File('example/annotated/mixins.dart').readAsString(),
          );
          await fixture.write('orm.config.dart', '''
import 'package:orm/config.dart';
void main() => defineConfig(database: .$engine, models: 'lib/models.dart',
  output: 'lib/models.orm.dart', migrations: 'migrations',
  ${engine == 'postgres' ? "defaultNamespace: '$namespace'," : ''}
);
''');
          await fixture.write('bin/mixins.dart', _consumer);
          await fixture.run(['run', 'orm', 'generate']);
          await fixture.run([
            'run',
            'orm',
            'migrate',
            'create',
            '0001_initial',
          ]);
          await fixture.run(['analyze']);
          final result = await fixture.run([
            'run',
            'orm_build_fixture:mixins',
            engine,
          ]);
          expect(result.output, contains('mixin-$engine-ok'));
        } finally {
          try {
            await admin?.execute(
              SqlCommand('DROP SCHEMA IF EXISTS "$namespace" CASCADE'),
            );
          } finally {
            await admin?.close();
            await fixture.dispose();
          }
        }
      },
      tags: engine,
      skip: engine == 'postgres' && url == null
          ? 'Set ORM_TEST_POSTGRES to an isolated test database.'
          : false,
      timeout: const Timeout(Duration(minutes: 4)),
    );
  }
}

const _consumer = r'''
import 'dart:io';
import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:orm_build_fixture/models.dart' as original;
import 'package:orm_build_fixture/models.orm.dart';
import 'package:orm_build_fixture/models.snapshot.dart' as physical;
import '../migrations/m0001_initial.dart' as initial;

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main(List<String> args) async {
  final engine = args.single;
  final namespace = physical.schema.tables.first.namespace;
  final Database<Backend> db = engine == 'sqlite'
      ? await sqlite(const SqliteOptions.memory())
      : postgres(PostgresOptions(
          url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
          tls: .disable, schema: namespace));
  try {
    if (engine == 'postgres') {
      await db.execute(SqlCommand('CREATE SCHEMA "$namespace"'));
    }
    await Migrator(db.sql).apply([initial.migration]);
    check((await verifySchema(db.sql, physical.schema)).matches,
        'Saved mixin migration differs from the catalog.');

    final Memo memo = await db.memo.create(title: 'Memo');
    final original.Memo originalMemo = memo;
    final original.SharedFields shared = originalMemo;
    check(shared.id > 0 && shared.describe() == '${memo.id}: label-1',
        'Returned DTO lost mixin storage or business methods.');
    check(memo.active && memo.note == 'guest' && memo.local == 'local',
        'Mixin initializers replaced database/constructor defaults.');
    final original.Task task = await db.task.create(memoId: memo.id, title: 'Task',
        label: .set('manual'), active: .set(false), note: .set(null));
    check(task.describe() == '${task.id}: manual' && !task.active && task.note == null,
        'Explicit values/null lost precedence over defaults.');
    check(original.labelCalls == 1, 'An explicit insert executed the shared factory.');

    await db.memo.byId(memo.id).patch(label: .set('changed'), note: .set(null));
    final original.Memo patched = await db.memo.byId(memo.id).single();
    check(patched.describe() == '${memo.id}: changed' && patched.note == null && patched.active,
        'Patch/read transformed stored mixin values or reapplied defaults.');
    check(original.labelCalls == 1, 'Patch/read executed an insert factory.');
    final original.Memo related = await db.task.byId(task.id)
        .select((t) => t.memo.required()).single();
    final List<original.Task> tasks = await db.memo.byId(memo.id)
        .select((m) => m.tasks.many()).single();
    check(related.describe() == patched.describe() && tasks.single.describe() == task.describe(),
        'Relation mapping lost original DTO mixin methods.');
    await db.memo.byId(memo.id).delete().execute();
    check(await db.memo.count() == 0 && await db.task.count() == 0,
        'Mixin keys or cascade deletion did not work.');
    print('mixin-$engine-ok');
  } finally { await db.close(); }
}
''';
