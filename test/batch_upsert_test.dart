import 'dart:io';

import 'package:orm/driver.dart';
import 'package:orm/migrate.dart';
import 'package:orm/orm.dart';
import 'package:orm/postgres.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/sql.dart';
import 'package:orm/sqlite.dart';
import 'package:orm/values.dart';
import 'package:test/test.dart';

import '../example/company/schema.orm.dart' as company;
import '../example/company/sync.dart' as business;
import 'support/recording_driver.dart';

int _samples = 0;
int _stamp() => ++_samples;
final _id = Column('id', Codecs.integer, generated: true);
final _key = Column('external_key', Codecs.text);
final _value = Column(
  'value',
  Codecs.text.nullable(),
  nullable: true,
  defaultSql: "'server'",
);
final _version = Column('stamp', Codecs.integer, clientDefault: _stamp);
typedef _Row = ({int id, String key, String? value, int stamp});
final _table = Table<_Row, _Fields>(
  TableSchema(
    'batch_sync',
    columns: [_id, _key, _value, _version],
    primaryKey: ['id'],
    uniqueKeys: [
      ['external_key'],
      ['stamp'],
    ],
  ),
  _Fields.new,
  (r) => (r.id, r.key, r.value, r.stamp).map(
    (id, key, value, stamp) => (id: id, key: key, value: value, stamp: stamp),
  ),
);

final class _Fields extends Fields {
  _Fields(super.table);
  late final id = column(_id);
  late final key = column(_key);
  late final value = column(_value);
  late final stamp = column(_version);
}

Matcher _code(String code) =>
    isA<OrmException>().having((e) => e.code, 'code', code);

BatchInsert<_Fields> _upsert(BatchInsert<_Fields> batch) =>
    batch.onConflictUpdate(
      target: (r) => [r.key],
      set: (existing, incoming) => [
        existing.value.setExpression(incoming.value),
      ],
    );

void main() {
  group('unsupported target dialects', () {
    for (final dialect in [SqlDialect.mysql, SqlDialect.mariadb]) {
      test(
        '${dialect.name} rejects targeted batch conflicts, including empty inputs',
        () {
          for (final keys in [
            <String>[],
            ['a'],
          ]) {
            final batch = _upsert(
              SqlBuilder(dialect)
                  .table(_table)
                  .insertMany(keys, (r, key) => [r.key.set(key)]),
            );
            expect(batch.compile, throwsA(_code('CAPABILITY.CONFLICT_TARGET')));
          }
        },
      );
    }
  }, tags: ['core']);
  for (final dialect in [SqlDialect.sqlite, SqlDialect.postgres]) {
    group(
      dialect.name,
      () => _databaseTests(dialect),
      tags: [dialect.name],
      skip:
          dialect == SqlDialect.postgres &&
              Platform.environment['ORM_TEST_POSTGRES'] == null
          ? 'Set ORM_TEST_POSTGRES to run real PostgreSQL.'
          : false,
    );
  }
}

void _databaseTests(SqlDialect dialect) {
  late Database<Backend> db;
  final events = <QueryEvent>[];
  setUp(() async {
    if (dialect == SqlDialect.sqlite) {
      db = Database.fromSql(
        await sqlite(const SqliteOptions.memory(), onQuery: events.add),
      );
    } else {
      final url = Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!);
      final namespace =
          'orm_batch_upsert_${pid}_${DateTime.now().microsecondsSinceEpoch}';
      final admin = Database.fromSql(
        postgres(PostgresOptions(url: url, tls: .disable)),
      );
      addTearDown(admin.close);
      await admin.execute(SqlCommand('CREATE SCHEMA "$namespace"'));
      addTearDown(
        () => admin.execute(SqlCommand('DROP SCHEMA "$namespace" CASCADE')),
      );
      db = Database.fromSql(
        postgres(
          PostgresOptions(url: url, tls: .disable, schema: namespace),
          onQuery: events.add,
        ),
      );
    }
    addTearDown(db.close);
    await Migrator(db.sql).apply([
      Migration.create('0001_batch_sync', [_table.schema], dialect: dialect),
    ]);
    _samples = 0;
    events.clear();
  });

  ({Database<Backend> db, RecordingDriver<Backend> driver}) limited(
    int limit, {
    bool returning = true,
  }) {
    final driver = RecordingDriver(
      db.driver,
      maxParameters: limit,
      withoutReturning: !returning,
    );
    return (db: Database(driver, onQuery: events.add), driver: driver);
  }

  test('uniform update rule retains IDs/stamps and copies incoming defaults or NULL', () async {
    final original = await db
        .table(_table)
        .createRow((r) => [r.key.set('old'), r.value.set('before')]);
    final batch = _upsert(
      db.table(_table).insertMany(
        ['old', 'null', 'default', 'new'],
        (r, key) => [
          r.key.set(key),
          if (key == 'null') r.value.set(null),
          if (key == 'default') r.value.defaultValue(),
        ],
      ),
    );
    expect(_samples, 5);
    final List<_Row> rows = await batch.returning(_table.selectRow).get();
    final byKey = {for (final row in rows) row.key: row};
    expect(byKey['old']!.id, original.id);
    expect(byKey['old']!.stamp, original.stamp);
    expect(byKey['old']!.value, 'server');
    expect(byKey['null']!.value, isNull);
    expect(byKey['default']!.value, 'server');
    expect(byKey['new']!.value, 'server');
    expect(byKey.values.map((r) => r.id).toSet(), hasLength(4));
    expect(_samples, 5);
  });

  test('conflict and RETURNING parameters share the limit; defaults freeze across replay', () async {
    final scope = limited(8);
    var callbacks = 0;
    final batch = scope.db
        .table(_table)
        .insertMany(
          List.generate(5, (i) => 'key-$i'),
          (r, key) => [r.key.set(key), r.value.set('insert')],
        )
        .onConflictUpdate(
          target: (r) => [r.key],
          set: (existing, incoming) {
            callbacks++;
            return [existing.value.set('patched')];
          },
        );
    expect(_samples, 5);
    expect(callbacks, 1);
    expect(batch.compile().map((c) => c.parameters.length), [7, 7, 4]);
    final returned = batch.returning(
      (r) => (r.key, r.key.eq(.value('tag'))).row,
    );
    expect(
      await returned.get(),
      unorderedEquals(List.generate(5, (i) => ('key-$i', false))),
    );
    expect(
      scope.driver.commands
          .where((c) => c.sql.startsWith('INSERT'))
          .map((c) => c.parameters.length),
      [8, 8, 5],
    );
    expect(await batch.execute(), 5);
    expect(_samples, 5);
    expect(callbacks, 1);
    expect(
      await db.table(_table).select((r) => r.value).get(),
      everyElement('patched'),
    );
  });

  for (final owned in [true, false]) {
    test(
      '${owned ? 'owned' : 'explicit'} transaction rolls back a failed later upsert chunk',
      () async {
        final original = await db
            .table(_table)
            .createRow(
              (r) => [r.key.set('old'), r.value.set('before'), r.stamp.set(1)],
            );
        final scope = limited(4);
        Future<void> execute(Database<Backend> view) async {
          final batch = _upsert(
            view.table(_table).insertMany(
              ['old', 'new', 'bad'],
              (r, key) => [
                r.key.set(key),
                r.value.set('changed'),
                r.stamp.set(
                  key == 'old'
                      ? 2
                      : key == 'new'
                      ? 3
                      : 1,
                ),
              ],
            ),
          );
          expect(batch.compile(), hasLength(3));
          await batch.execute();
        }

        if (owned) {
          await expectLater(execute(scope.db), throwsA(isA<SqlFailure>()));
        } else {
          await expectLater(
            scope.db.transaction((tx) async {
              await expectLater(execute(tx), throwsA(isA<SqlFailure>()));
            }),
            throwsA(_code('TRANSACTION.FAILED')),
          );
        }
        expect(await db.table(_table).get(), [original]);
        expect(events.any((e) => e.sql == 'ROLLBACK'), true);
      },
    );
  }

  test('all chunk budgets and invalid clauses fail before acquiring a write transaction', () async {
    final scope = limited(3);
    final batch = scope.db
        .table(_table)
        .insertMany(
          ['fits', 'too-large'],
          (r, key) => [
            r.key.set(key),
            if (key == 'too-large') r.value.set('extra'),
          ],
        )
        .onConflictUpdate(
          target: (r) => [r.key],
          set: (existing, incoming) => [existing.value.set('parameter')],
        );
    await expectLater(batch.execute(), throwsA(_code('QUERY.PARAMETERS')));
    expect(scope.driver.commands, isEmpty);
    final base = db.table(_table).insertMany([
      'valid',
    ], (r, key) => [r.key.set(key)]);
    expect(
      () => base.onConflictUpdate(
        target: (r) => [r.value],
        set: (e, i) => [e.value.setExpression(i.value)],
      ),
      throwsA(_code('MUTATION.CONFLICT')),
    );
    expect(
      () => base.onConflictUpdate(target: (r) => [r.key], set: (e, i) => []),
      throwsA(_code('MUTATION.EMPTY')),
    );
    final alias = _table.alias();
    await expectLater(
      base
          .onConflictUpdate(
            target: (r) => [r.key],
            set: (e, i) => [alias.fields.value.set('invalid')],
          )
          .execute(),
      throwsA(_code('QUERY.SCOPE')),
    );
    expect(events, isEmpty);
  });

  test(
    'RETURNING capability is rejected before SQL, including an empty batch',
    () async {
      final scope = limited(100, returning: false);
      for (final keys in [
        <String>[],
        ['a'],
      ]) {
        final batch = _upsert(
          scope.db.table(_table).insertMany(keys, (r, key) => [r.key.set(key)]),
        );
        await expectLater(
          batch.returning(_table.selectRow).get(),
          throwsA(_code('CAPABILITY.RETURNING')),
        );
      }
      expect(scope.driver.commands, isEmpty);
    },
  );

  test('empty valid upsert does no I/O', () async {
    final batch = _upsert(
      db.table(_table).insertMany(<String>[], (r, key) => [r.key.set(key)]),
    );
    expect(batch.compile(), isEmpty);
    expect(await batch.execute(), 0);
    expect(await batch.returning(_table.selectRow).get(), isEmpty);
    expect(events, isEmpty);
  });

  test(
    'all-default rows follow the engine syntax boundary before batch I/O',
    () async {
      final defaults = Table<int, _Fields>(
        TableSchema('default_rows', columns: [_id], primaryKey: ['id']),
        _Fields.new,
        (r) => r.id,
      );
      for (final command in createSchema([defaults.schema], dialect)) {
        await db.execute(command);
      }
      if (dialect == SqlDialect.sqlite) {
        // Establish the real engine limitation, then require batch preflight to
        // reject it without submitting that invalid statement.
        await expectLater(
          db.execute(
            SqlCommand(
              'INSERT INTO "default_rows" DEFAULT VALUES ON CONFLICT ("id") '
              'DO UPDATE SET "id" = excluded."id"',
            ),
          ),
          throwsA(isA<SqlFailure>()),
        );
      }
      events.clear();
      final batch = db
          .table(defaults)
          .insertMany([0, 1], (r, _) => [])
          .onConflictUpdate(
            target: (r) => [r.id],
            set: (e, i) => [e.id.setExpression(i.id)],
          );
      if (dialect == SqlDialect.sqlite) {
        await expectLater(
          batch.execute(),
          throwsA(_code('CAPABILITY.CONFLICT_DEFAULT_VALUES')),
        );
        expect(events, isEmpty);
      } else {
        expect(await batch.returning((r) => r.id).get(), hasLength(2));
      }
    },
  );

  for (final split in [false, true]) {
    test(
      'duplicate keys follow ${split ? 'separate chunks' : 'one statement'} native semantics',
      () async {
        final scope = limited(split ? 3 : 100);
        final batch = _upsert(
          scope.db.table(_table).insertMany([
            'first',
            'last',
          ], (r, value) => [r.key.set('same'), r.value.set(value)]),
        );
        expect(batch.compile(), hasLength(split ? 2 : 1));
        if (dialect == SqlDialect.postgres && !split) {
          await expectLater(batch.execute(), throwsA(isA<SqlFailure>()));
          expect(await db.table(_table).count(), 0);
        } else {
          expect(await batch.execute(), 2);
          final rows = await db.table(_table).get();
          expect(rows, hasLength(1));
          expect(rows.single.value, 'last');
        }
      },
    );
  }

  test(
    'generated prepared batch retains the full model RETURNING path',
    () async {
      await Migrator(db.sql).apply([
        Migration.create('0001_batch_sync', [_table.schema], dialect: dialect),
        Migration.create('0002_company', company.appSchema, dialect: dialect),
      ]);
      final department = await db.department.create(name: 'Engineering');
      final inputs = [
        for (final name in ['Ada', 'Bea'])
          company.employeeInsert(
            name: name,
            email: '$name@example.test',
            departmentId: department.id,
          ),
      ];
      final BatchInsert<company.EmployeeFields> batch = db.employee.plan
          .insertMany(inputs)
          .prepare()
          .onConflictUpdate(
            target: (e) => [e.email],
            set: (existing, incoming) => [
              existing.name.setExpression(incoming.name),
            ],
          );
      final BatchReturning<company.Employee> returning = batch.returning(
        company.employeeTable.selectRow,
      );
      final List<company.Employee> first = await returning.get();
      final second = await returning.get();
      expect(
        second.map((r) => (r.id, r.email, r.createdAt)),
        unorderedEquals(first.map((r) => (r.id, r.email, r.createdAt))),
      );
      final ada = first.singleWhere((r) => r.name == 'Ada');
      final bea = first.singleWhere((r) => r.name == 'Bea');
      await db.employee.byId(ada.id).patch(active: false, managerId: bea.id);
      events.clear();
      final synced = await db.transaction(
        (tx) => business.syncDirectory(tx, [
          (email: ada.email, name: 'Updated', departmentId: department.id),
          (
            email: 'Cara@example.test',
            name: 'Cara',
            departmentId: department.id,
          ),
        ]),
      );
      final updated = synced.singleWhere((r) => r.email == ada.email);
      expect(
        (updated.id, updated.createdAt, updated.active, updated.managerId),
        (ada.id, ada.createdAt, false, bea.id),
      );
      expect(updated.name, 'Updated');
      expect(events.where((e) => e.sql.startsWith('INSERT')), hasLength(1));
    },
  );
}
