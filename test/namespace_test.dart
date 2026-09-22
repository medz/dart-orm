import 'dart:async';
import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

final _id = Column('Id', Codecs.integer, generated: true);
final _name = Column('DisplayName', Codecs.text);

final class _UserFields extends Fields {
  _UserFields(super.table);
  late final id = column(_id);
  late final name = column(_name);
}

Table<({int id, String name}), _UserFields> _users(String namespace) => Table(
  _userSchema(namespace),
  _UserFields.new,
  (u) => (u.id, u.name).map((id, name) => (id: id, name: name)),
);

TableSchema _userSchema(
  String namespace, {
  String name = 'Users',
  bool check = false,
}) => TableSchema(
  name,
  namespace: namespace,
  columns: [_id, _name],
  primaryKey: ['Id'],
  indexes: [
    IndexSchema('Names.Index', ['DisplayName']),
  ],
  checks: check ? [CheckSchema('NameLength', 'length("DisplayName") > 0')] : [],
);

TableSchema _messages(
  String namespace,
  String target, {
  String action = 'RESTRICT',
}) => TableSchema(
  'Messages',
  namespace: namespace,
  columns: [Column('Id', Codecs.integer), Column('AuthorId', Codecs.integer)],
  primaryKey: ['Id'],
  foreignKeys: [
    ForeignKey(
      ['AuthorId'],
      'Users',
      ['Id'],
      targetNamespace: target,
      onDelete: action,
    ),
  ],
);

void main() {
  test(
    'manual tables reject dotted physical identity components before binding',
    () {
      final sql = SqlBuilder(.postgres);
      Table<({int id, String name}), _UserFields> definition(
        String name, {
        String? namespace,
      }) => Table(
        TableSchema(name, namespace: namespace, columns: [_id, _name]),
        _UserFields.new,
        (u) => (u.id, u.name).map((id, name) => (id: id, name: name)),
      );
      final invalid = throwsA(
        isA<OrmException>().having((e) => e.code, 'code', 'SCHEMA.IDENTIFIER'),
      );
      expect(() => sql.table(definition('auth.Users')).compile(), invalid);
      expect(
        () =>
            sql.table(definition('Users', namespace: 'auth.private')).compile(),
        invalid,
      );
      for (final key in [
        ForeignKey(['Id'], 'auth.Users', ['Id']),
        ForeignKey(['Id'], 'Users', ['Id'], targetNamespace: 'auth.private'),
      ]) {
        expect(
          () => TableSchema('Reports', columns: [_id], foreignKeys: [key]),
          invalid,
        );
      }
      expect(
        sql.table(definition('Users', namespace: 'auth')).compile().sql,
        contains('"auth"."Users"'),
      );
    },
  );

  test(
    'explicit namespaces reject unsupported query and migration engines',
    () async {
      final db = await sqlite(const SqliteOptions.memory());
      addTearDown(db.close);
      expect(
        () => db.table(_users('auth')).compile(),
        throwsA(isA<OrmException>()),
      );
      for (final dialect in [
        SqlDialect.sqlite,
        SqlDialect.mysql,
        SqlDialect.mariadb,
      ]) {
        expect(
          () => SchemaSnapshot([_userSchema('auth')]).forDialect(dialect),
          throwsA(isA<OrmException>()),
        );
      }
    },
  );

  test('namespace metadata survives source emission without changing old fingerprints', () {
    final plain = TableSchema('Users', columns: [_id], primaryKey: ['Id']);
    expect(SchemaSnapshot([plain]).toJson()['tables'], [
      {
        'name': 'Users',
        'columns': [
          {
            'name': 'Id',
            'type': 'integer',
            'nullable': false,
            'generated': true,
          },
        ],
        'primaryKey': ['Id'],
        'uniqueKeys': <Object?>[],
        'indexes': <Object?>[],
        'foreignKeys': <Object?>[],
      },
    ]);
    final migration = Migration.steps('0001_drop', [
      DropTable('Users', namespace: 'auth'),
      DropConstraint('Users', {
        'kind': 'p',
        'columns': ['Id'],
      }, namespace: 'auth'),
    ], dialect: .postgres);
    expect(migrationSource(migration), contains("namespace: \"auth\""));
    expect(migration.steps.first.toJson()['namespace'], 'auth');
  });

  final url = Platform.environment['ORM_TEST_POSTGRES'];
  group(
    'PostgreSQL namespaces',
    () {
      late Database<Postgres> db;
      late String first, second, history;
      var serial = 0;
      setUp(() async {
        final prefix = 'orm_ns_${pid}_${serial++}';
        first = '${prefix}_A';
        second = '${prefix}_B';
        history = '${prefix}_history';
        db = postgres(
          PostgresOptions(url: Uri.parse(url!), tls: .disable, schema: history),
        );
        await db.execute(SqlCommand('CREATE SCHEMA "$history"'));
      });
      tearDown(() async {
        for (final namespace in [first, second, history]) {
          await db.execute(
            SqlCommand('DROP SCHEMA IF EXISTS "$namespace" CASCADE'),
          );
        }
        await db.close();
      });

      test(
        'unqualified snapshots require explicit destructive replacement',
        () async {
          final old = TableSchema(
            'Users',
            columns: [_id, _name],
            primaryKey: ['Id'],
          );
          final initial = Migration.create('0001_initial', [
            old,
          ], dialect: .postgres);
          await Migrator(db.sql).apply([initial]);
          await db.execute(
            SqlCommand(
              'INSERT INTO "Users" ("DisplayName") VALUES (\'Old row\')',
            ),
          );
          final target = SchemaSnapshot([_userSchema(first)]);
          expect(
            () => Migration.diff(
              '0002_replace',
              dialect: .postgres,
              from: initial.snapshot!,
              to: target,
            ),
            throwsA(isA<OrmException>()),
          );
          final replace = Migration.diff(
            '0002_replace',
            dialect: .postgres,
            from: initial.snapshot!,
            to: target,
            previous: initial.checksum,
            allowDestructive: true,
          );
          await Migrator(db.sql).apply([initial, replace]);
          expect((await verifySchema(db.sql, target)).matches, true);
          expect(await db.table(_users(first)).get(), isEmpty);
          expect(
            (await inspectTable(db.sql, 'Users', namespace: history)).columns,
            isEmpty,
          );
        },
      );

      test('catalog probes ignore shadow system tables and helper functions', () async {
        final a = _users(first), b = _users(second);
        final initial = Migration.create('0001_initial', [
          a.schema,
          b.schema,
        ], dialect: .postgres);
        await Migrator(db.sql).apply([initial]);
        await db.table(a).createRow((u) => [u.name.set('Alice')]);
        await db.execute(
          SqlCommand(
            'CREATE TABLE "$second".pg_class AS SELECT * FROM pg_catalog.pg_class WHERE false',
          ),
        );
        await db.execute(
          SqlCommand(
            'CREATE FUNCTION "$second".row_security_active(oid) RETURNS boolean LANGUAGE plpgsql AS \$\$ BEGIN RAISE EXCEPTION \'shadow helper called\'; END \$\$',
          ),
        );
        await db.session((session) async {
          await session.execute(
            SqlCommand('SET search_path TO "$history", "$second", pg_catalog'),
          );
          expect(
            (await verifySchema(session.sql, initial.snapshot!)).differences,
            isEmpty,
          );
          final index = CheckedSql.createIndex(
            'Users',
            a.schema.indexes.single,
            namespace: first,
          );
          expect(
            (await session.execute(SqlCommand(index.readyWhen)))
                .rows
                .single
                .single,
            false,
          );
          expect(
            (await session.execute(SqlCommand(index.doneWhen)))
                .rows
                .single
                .single,
            true,
          );
          final fill = Migration.steps(
            '0002_fill',
            [
              Backfill(
                a.schema,
                set: {'DisplayName': "'Updated'"},
                where: '"DisplayName" <> \'Updated\'',
                doneWhen:
                    'SELECT NOT EXISTS (SELECT 1 FROM "$first"."Users" WHERE "DisplayName" <> \'Updated\')',
              ),
            ],
            dialect: .postgres,
            snapshot: initial.snapshot,
            previous: initial.checksum,
          );
          await Migrator(session.sql).apply([initial, fill]);
          expect((await session.table(a).get()).single.name, 'Updated');
          expect(
            await verifyColumns(session.sql, [
              TableSchema(
                'Users',
                namespace: first,
                columns: [_id, Column('Missing', Codecs.text)],
                primaryKey: ['Id'],
              ),
            ]),
            [
              '$first.Users.Missing is missing',
              '$first.Users.DisplayName is unmanaged',
            ],
          );
        });
      });

      test('same-named tables, SQL scope, cursors, joins and watch remain distinct', () async {
        final a = _users(first), b = _users(second);
        await Migrator(db.sql).apply([
          Migration.create('0001_initial', [
            a.schema,
            b.schema,
          ], dialect: .postgres),
        ]);
        await db.table(a).createRow((u) => [u.name.set('Alice')]);
        await db.table(b).createRow((u) => [u.name.set('Bob')]);
        final token = db.table(a).cursorToken((u) => [u.id.cursor(1)]);
        expect(
          () => db.table(b).seekToken(token, orderBy: (u) => [u.id.asc()]),
          throwsA(isA<OrmException>()),
        );
        final plan = db.table(a).inspect();
        expect(plan.reads, [a.schema.identity]);
        expect(plan.sql, contains('"$first"."Users"'));
        await db.session((session) async {
          await session.execute(SqlCommand('SET search_path TO "$second"'));
          await session.execute(
            SqlCommand(
              'CREATE TEMPORARY TABLE "Users" ("Id" bigint, "DisplayName" text)',
            ),
          );
          expect((await session.table(a).get()).single.name, 'Alice');
          expect((await session.table(b).get()).single.name, 'Bob');
          final cte = session.table(b).select((u) => u.id).asCte('Users');
          expect(await cte.query.get(), [1]);
          final alias = b.alias();
          final joined = await session
              .table(a)
              .join(alias, on: (left, right) => left.id.equals(right.id))
              .select(
                (left) => (left.name, alias.fields.name).map((a, b) => (a, b)),
              )
              .get();
          expect(joined, [('Alice', 'Bob')]);
        });
        final emissions = <List<({int id, String name})>>[];
        final initial = Completer<void>(), changed = Completer<void>();
        final subscription = db.table(a).watch().listen((rows) {
          emissions.add(rows);
          if (!initial.isCompleted) initial.complete();
          if (rows.single.name == 'Updated' && !changed.isCompleted) {
            changed.complete();
          }
        });
        try {
          await initial.future;
          await db
              .table(b)
              .where((u) => u.id.eq(1))
              .update((u) => [u.name.set('Other')])
              .execute();
          await db
              .table(a)
              .where((u) => u.id.eq(1))
              .update((u) => [u.name.set('Updated')])
              .execute();
          await changed.future.timeout(const Duration(seconds: 5));
          expect(emissions.map((rows) => rows.single.name), [
            'Alice',
            'Updated',
          ]);
        } finally {
          await subscription.cancel();
        }
      });

      test(
        'cross-schema foreign keys, checks and qualified diff verification',
        () async {
          final start = Migration.create('0001_initial', [
            _userSchema(first),
            _userSchema(second),
            _messages(second, first),
          ], dialect: .postgres);
          await Migrator(db.sql).apply([start]);
          expect(
            (await verifySchema(db.sql, start.snapshot!)).differences,
            isEmpty,
          );
          await db.execute(
            SqlCommand(
              'INSERT INTO "$first"."Users" ("DisplayName") VALUES (\'Alice\')',
            ),
          );
          await db.execute(
            SqlCommand('INSERT INTO "$second"."Messages" VALUES (1, 1)'),
          );
          final next = SchemaSnapshot([
            _userSchema(first, check: true),
            _userSchema(second),
            _messages(second, first, action: 'CASCADE'),
          ]);
          final change = Migration.diff(
            '0002_constraints',
            dialect: .postgres,
            from: start.snapshot!,
            to: next,
            previous: start.checksum,
          );
          await Migrator(db.sql).apply([start, change]);
          expect((await verifySchema(db.sql, next)).differences, isEmpty);
          await db.table(_users(first)).delete().execute();
          expect(
            (await db.execute(
              SqlCommand('SELECT count(*) FROM "$second"."Messages"'),
            )).rows.single.single,
            0,
          );
          final dropCheck = Migration.diff(
            '0003_check',
            dialect: .postgres,
            from: next,
            to: SchemaSnapshot([
              _userSchema(first),
              _userSchema(second),
              _messages(second, first, action: 'CASCADE'),
            ]),
            previous: change.checksum,
          );
          await Migrator(db.sql).apply([start, change, dropCheck]);
          expect(
            (await verifySchema(db.sql, dropCheck.snapshot!)).differences,
            isEmpty,
          );
        },
      );

      test('explicit schema moves preserve rows and never infer a destructive rename', () async {
        final start = Migration.create('0001_initial', [
          _userSchema(first),
        ], dialect: .postgres);
        await Migrator(db.sql).apply([start]);
        await db.table(_users(first)).createRow((u) => [u.name.set('Alice')]);
        final target = SchemaSnapshot([_userSchema(second, name: 'Members')]);
        expect(
          () => Migration.diff(
            '0002_move',
            dialect: .postgres,
            from: start.snapshot!,
            to: target,
          ),
          throwsA(isA<OrmException>()),
        );
        final move = Migration.diff(
          '0002_move',
          dialect: .postgres,
          from: start.snapshot!,
          to: target,
          renames: SchemaRenames(tables: {'$first.Users': '$second.Members'}),
          previous: start.checksum,
        );
        await Migrator(db.sql).apply([start, move]);
        expect((await verifySchema(db.sql, target)).differences, isEmpty);
        expect(
          (await db.execute(
            SqlCommand('SELECT "DisplayName" FROM "$second"."Members"'),
          )).rows.single.single,
          'Alice',
        );
        final removal = Migration.diff(
          '0003_remove',
          dialect: .postgres,
          from: target,
          to: SchemaSnapshot([]),
          allowDestructive: true,
          previous: move.checksum,
        );
        await Migrator(db.sql).apply([start, move, removal]);
        expect(
          (await inspectTable(db.sql, 'Members', namespace: second)).columns,
          isEmpty,
        );
      });
    },
    skip: url == null
        ? 'Set ORM_TEST_POSTGRES to a disposable PostgreSQL database.'
        : false,
  );
}
