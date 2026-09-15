import 'dart:io';

import 'package:orm/generate.dart';
import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import 'support/defaults/schema.orm.dart';
import 'support/defaults/schema.snapshot.dart' as physical;
import 'support/defaults/types.dart' as d;

void main() {
  for (final dialect in SqlDialect.values) {
    group(
      'client defaults ${dialect.name}',
      () {
        late Database<Backend> db;
        setUp(() async {
          d.reset();
          if (dialect == SqlDialect.sqlite) {
            db = await sqlite(const SqliteOptions.memory());
          } else {
            db = postgres(
              PostgresOptions(
                url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
                tls: .disable,
                schema: 'orm_client_default_tests',
              ),
            );
            await db.execute(
              SqlCommand(
                'DROP SCHEMA IF EXISTS orm_client_default_tests CASCADE',
              ),
            );
            await db.execute(
              SqlCommand('CREATE SCHEMA orm_client_default_tests'),
            );
          }
          await Migrator(db).apply([
            Migration.create('0001_initial', appSchema, dialect: db.dialect),
          ]);
          expect(
            [d.idCalls, d.nameCalls, d.stateCalls, d.nullCalls],
            [0, 0, 0, 0],
          );
        });
        tearDown(() => db.close());

        test(
          'omitted values use typed Dart factories and return stored records',
          () async {
            final before = DateTime.now().toUtc();
            final row = await db.tickets.create();
            expect(row.id, d.TicketId(1));
            expect(row.name, 'ticket-1');
            expect(row.label, isNull);
            expect(row.state, 'client-1');
            expect(row.createdAt.isBefore(before), false);
            expect(row.createdAt.isAfter(DateTime.now().toUtc()), false);
            expect(
              [d.idCalls, d.nameCalls, d.stateCalls, d.nullCalls],
              [1, 1, 1, 1],
            );
            expect(await db.tickets.single(), row);
          },
        );

        test(
          'explicit values, null and SQL DEFAULT bypass their client factory',
          () async {
            final instant = DateTime.utc(2026, 9, 15);
            final row = await db.tickets.create(
              id: .set(d.TicketId(20)),
              name: .set('explicit'),
              label: .set(null),
              state: .defaultValue(),
              createdAt: .set(instant),
            );
            expect(row.state, 'server');
            expect(row.label, isNull);
            expect(row.createdAt, instant);
            expect(
              [d.idCalls, d.nameCalls, d.stateCalls, d.nullCalls],
              [0, 0, 0, 0],
            );
            await expectLater(
              db.tickets.create(name: .defaultValue()),
              throwsA(
                isA<OrmException>().having(
                  (e) => e.code,
                  'code',
                  'MUTATION.DEFAULT',
                ),
              ),
            );
            expect(await db.tickets.count(), 1);
          },
        );

        test('prepared mutations, repeated compilation and conflicts retain one generated value', () async {
          final prepared = db.tickets.insert((row) => []);
          expect(
            [d.idCalls, d.nameCalls, d.stateCalls, d.nullCalls],
            [1, 1, 1, 1],
          );
          final first = prepared.compile();
          expect(prepared.compile().parameters, first.parameters);
          final conflict = prepared.onConflictDoNothing(
            target: (row) => [row.id],
          );
          expect(await conflict.execute(), 1);
          expect(await conflict.execute(), 0);
          expect(
            [d.idCalls, d.nameCalls, d.stateCalls, d.nullCalls],
            [1, 1, 1, 1],
          );
          expect((await db.tickets.single()).id, d.TicketId(1));
        });

        test('batch insert prepares defaults once per omitted row and preserves explicit values', () async {
          final batch = db.tickets.insertMany(
            [null, 20, null],
            (row, int? id) => [
              if (id != null) row.id.set(d.TicketId(id)),
              if (id != null) row.state.defaultValue(),
            ],
          );
          expect(
            [d.idCalls, d.nameCalls, d.stateCalls, d.nullCalls],
            [2, 3, 2, 3],
          );
          final statements = batch.compile();
          expect(
            batch.compile().map((s) => s.parameters).toList(),
            statements.map((s) => s.parameters).toList(),
          );
          final rows = await batch
              .returning((t) => (t.id, t.state).map((id, state) => (id, state)))
              .get();
          expect(rows, [
            (d.TicketId(1), 'client-1'),
            (d.TicketId(20), 'server'),
            (d.TicketId(2), 'client-2'),
          ]);
          expect(
            [d.idCalls, d.nameCalls, d.stateCalls, d.nullCalls],
            [2, 3, 2, 3],
          );
        });

        test(
          'updates and conflict updates do not reset omitted client values',
          () async {
            final row = await db.tickets.create();
            await db.tickets.byId(row.id).patch(name: .set('changed'));
            expect((await db.tickets.single()).state, 'client-1');
            expect(
              [d.idCalls, d.nameCalls, d.stateCalls, d.nullCalls],
              [1, 1, 1, 1],
            );
            await db.tickets
                .insert((t) => [t.id.set(row.id), t.name.set('incoming')])
                .onConflictUpdate(
                  target: (t) => [t.id],
                  set: (old, incoming) => [
                    old.name.setExpression(incoming.name),
                  ],
                )
                .execute();
            expect((await db.tickets.single()).name, 'incoming');
            expect((await db.tickets.single()).state, 'client-1');
            expect(d.stateCalls, 2); // The attempted INSERT prepared a value; UPDATE kept the stored state.
          },
        );

        test('factory errors issue no writes, and rollback does not reverse Dart side effects', () async {
          d.failName = true;
          expect(() => db.tickets.insert((t) => []), throwsStateError);
          expect(await db.tickets.count(), 0);
          d.failName = false;
          await expectLater(
            db.transaction((tx) async {
              await tx.tickets.create();
              throw StateError('rollback');
            }),
            throwsStateError,
          );
          expect(await db.tickets.count(), 0);
          final row = await db.tickets.create();
          expect(row.id, d.TicketId(3));
          expect(d.nameCalls, 3);
        });

        test('snapshots, migrations, catalogs and imports never store or run a client factory', () async {
          final original = SchemaSnapshot(appSchema);
          final restored = physical.schema;
          expect(
            restored.tables
                .expand((t) => t.columns)
                .every((c) => c.clientDefault == null),
            true,
          );
          expect(
            Migration.diff(
              '0002_no_sql_change',
              from: original,
              to: restored,
              dialect: db.dialect,
            ).steps.isEmpty,
            true,
          );
          expect((await verifySchema(db, original)).matches, true);
          final info = await inspectTable(db, 'tickets');
          expect(
            info.columns.where((c) => c.defaultSql != null).map((c) => c.name),
            ['state'],
          );
          final imported = await importSchema(db);
          expect(imported.dart, isNot(contains('ClientDefault')));
          expect(
            [d.idCalls, d.nameCalls, d.stateCalls, d.nullCalls],
            [0, 0, 0, 0],
          );
        });
        test('explicit DEFAULT can choose database identity instead of the client value', () async {
          final client = await db.sequences.create();
          expect(client.id, 1001);
          final server = await db.sequences.create(id: .defaultValue());
          expect(server.id, dialect == SqlDialect.sqlite ? 1002 : 1);
          expect(d.identityCalls, 1);
        });
      },
      skip:
          dialect == SqlDialect.postgres &&
              Platform.environment['ORM_TEST_POSTGRES'] == null
          ? 'Set ORM_TEST_POSTGRES.'
          : false,
    );
  }

  test('generation reads factory references without executing them and supports moved output', () async {
    d.reset();
    d.failName = true;
    final directory = await Directory('.dart_tool/orm-default-generation')
        .create(recursive: true);
    try {
      final path = '${directory.path}/generated.dart';
      await writeGeneratedSchema(
        'test/support/defaults/schema.dart',
        output: path,
      );
      final analysis = await Process.run(Platform.resolvedExecutable, [
        'analyze',
        path,
      ]);
      expect(
        analysis.exitCode,
        0,
        reason: '${analysis.stdout}\n${analysis.stderr}',
      );
      expect([d.idCalls, d.nameCalls, d.stateCalls, d.nullCalls], [0, 0, 0, 0]);
    } finally {
      d.reset();
      await directory.delete(recursive: true);
    }
  });
}
