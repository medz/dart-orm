@Tags(['database', 'mysql-suite'])
library;

import 'dart:io';

import 'package:orm/mariadb.dart';
import 'package:orm/mysql.dart';
import 'package:test/test.dart';

import '../tool/src/build_fixture.dart';

void main() {
  for (final engine in ['mysql', 'mariadb']) {
    final variable = 'ORM_TEST_${engine.toUpperCase()}';
    final address = Platform.environment[variable];
    test(
      '$engine fresh generated DTO consumer applies saved migrations and preserves mixin behavior',
      () async {
        final fixture = await BuildFixture.create(
          ormPath: Directory.current.path,
        );
        addTearDown(fixture.dispose);
        await fixture.file('lib/schema.dart').delete();
        await fixture.write('lib/models.dart', _models);
        await fixture.write('lib/shared.dart', _fields);
        await fixture.write('orm.config.dart', '''
import 'package:orm/config.dart';
void main() => defineConfig(
  database: .$engine,
  connect: ({required bool readOnly}) => throw StateError('Offline generation must not connect'),
);
''');
        await fixture.run(['run', 'orm', 'generate']);
        await fixture.run(['run', 'orm', 'migrate', 'create', '0001_initial']);
        await fixture.write('bin/consumer.dart', _consumer);
        await fixture.run(['analyze']);

        final tls = MysqlTls.values.byName(
          Platform.environment['${variable}_TLS'] ?? 'verifyFull',
        );
        final url = Uri.parse(address!);
        final Database<Backend> admin = engine == 'mysql'
            ? await mysql(MysqlOptions(url: url, tls: tls))
            : await mariadb(MariadbOptions(url: url, tls: tls));
        final namespace =
            'orm_generated_${engine}_${pid}_${DateTime.now().microsecondsSinceEpoch}';
        var created = false;
        try {
          await admin.execute(SqlCommand('CREATE DATABASE "$namespace"'));
          created = true;
          final result = await fixture.run(
            ['run', 'orm_build_fixture:consumer', engine],
            environment: {
              'ORM_GENERATED_URL': url.replace(path: '/$namespace').toString(),
              'ORM_GENERATED_TLS': tls.name,
            },
          );
          expect(result.output, contains('$engine-generated-consumer-ok'));
        } finally {
          try {
            if (created) {
              await admin.execute(SqlCommand('DROP DATABASE "$namespace"'));
            }
          } finally {
            await admin.close();
          }
        }
      },
      tags: engine,
      skip: address == null
          ? 'Set $variable to a disposable server with CREATE DATABASE privileges.'
          : false,
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}

const _models = r'''
import 'package:orm/schema.dart';
import 'shared.dart';
export 'shared.dart';
@Model()
final class Memo with SharedFields {
  final String title;

  Memo({
    required int id,
    required this.title,
    String label = 'constructor',
    bool active = false,
    String? note = 'guest',
  }) {
    this.id = id;
    this.label = label;
    this.active = active;
    this.note = note;
  }
}

@Model()
final class Task with SharedFields {
  @Relation(target: Memo, name: 'memo', inverse: 'tasks', onDelete: .cascade)
  final int memoId;
  final String title;

  Task({
    required int id,
    required this.memoId,
    required this.title,
    String label = 'constructor',
    bool active = false,
    String? note = 'guest',
  }) {
    this.id = id;
    this.label = label;
    this.active = active;
    this.note = note;
  }
}
''';

const _fields = r'''
import 'package:orm/schema.dart';

int labelCalls = 0;
String nextLabel() => 'label-${++labelCalls}';

// Mixins are optional. Ordinary DTOs can continue declaring their own fields.
mixin SharedFields {
  @Id(generated: true)
  int id = 0;

  @Column(name: 'display_label')
  @ClientDefault(nextLabel)
  String label = '';

  @DatabaseDefault(true)
  bool active = false;

  String? note;

  @Ignore()
  final String local = 'local';

  String describe() => '$id: $label';
}

''';

const _consumer = r'''
import 'dart:io';
import 'package:orm/mysql.dart';
import 'package:orm/mariadb.dart';

import '../migrations/migrations.g.dart' as history;

import 'package:orm/migrate.dart';
import 'package:orm_build_fixture/models.dart' as original;
import 'package:orm_build_fixture/models.orm.dart';
import 'package:orm_build_fixture/models.snapshot.dart'
    as physical;

import '../migrations/m0001_initial.dart' as initial;

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main(List<String> args) async {
  final url = Uri.parse(Platform.environment['ORM_GENERATED_URL']!);
  final tls = MysqlTls.values.byName(Platform.environment['ORM_GENERATED_TLS']!);
  final Database<Backend> db = args.single == 'mysql'
      ? await mysql(MysqlOptions(url: url, tls: tls))
      : await mariadb(MariadbOptions(url: url, tls: tls));
  try {
    check(db.dialect.name == args.single && history.migrationDialect == db.dialect, 'fixed engine');
    check(initial.migration.checksum == initial.migrationChecksum, 'immutable saved fingerprint');
    check(initial.migration.snapshot!.checksum == physical.schema.forDialect(db.dialect).checksum, 'frozen source matches generated snapshot');
    final opposite = db.dialect == SqlDialect.mysql ? SqlDialect.mariadb : SqlDialect.mysql;
    try {
      MigrationHistory(history.migrationHistory.entries, dialect: opposite).checked;
      throw StateError('Mixed-engine history was accepted');
    } on OrmException catch (error) {
      check(error.code == 'MIGRATION.TARGET', 'mixed-engine history error');
    }
    check(
      (await Migrator(db.sql).plan(history.migrationHistory.checked))
              .single
              .id ==
          '0001_initial',
      'saved history plan',
    );
    await Migrator(db.sql).apply(history.migrationHistory.checked);
    check(
      (await Migrator(db.sql).apply(history.migrationHistory.checked)).isEmpty,
      'repeat migration no-op',
    );
    check(
      (await Migrator(db.sql).history()).single.checksum ==
          initial.migrationChecksum,
      'recorded checksum',
    );
    check(
      (await verifySchema(db.sql, physical.schema)).matches,
      'generated migration catalog',
    );
    final Memo memo = await db.memo.create(title: 'Installed');
    final original.Memo identity = memo;
    final original.SharedFields shared = identity;
    check(
      shared.id > 0 && shared.describe() == '${memo.id}: label-1',
      'original DTO/mixin methods',
    );
    check(
      memo.active && memo.note == 'guest',
      'database and constructor defaults',
    );
    final original.Task task = await db.task.create(
      memoId: memo.id,
      title: 'Task',
      label: .set('manual'),
      active: .set(false),
      note: .set(null),
    );
    check(
      task.describe() == '${task.id}: manual' &&
          !task.active &&
          task.note == null,
      'explicit values/null',
    );
    await db.memo.byId(memo.id).patch(label: .set('Changed'), note: .set(null));
    final original.Memo read = await db.memo.byId(memo.id).single();
    check(
      read.describe() == '${memo.id}: Changed' &&
          read.note == null &&
          read.active,
      'patch and complete reads',
    );
    final original.Memo related = await db.task
        .byId(task.id)
        .select((t) => t.memo.required())
        .single();
    final List<original.Task> tasks = await db.memo
        .byId(memo.id)
        .select((m) => m.tasks.many())
        .single();
    check(
      related.describe() == read.describe() && tasks.single.id == task.id,
      'typed original relations',
    );
    check(original.labelCalls == 1, 'factories only run for omitted creates');
    await db.memo.byId(memo.id).delete().execute();
    check(
      await db.memo.count() == 0 && await db.task.count() == 0,
      'CRUD and cascade',
    );
    print('${db.dialect.name}-generated-consumer-ok');
  } finally {
    await db.close();
  }
}
''';
