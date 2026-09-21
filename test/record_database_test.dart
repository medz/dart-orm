import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import '../example/company/schema.orm.dart';
import '../example/company/schema.snapshot.dart' as physical;

void main() {
  runRecordTests(
    'sqlite',
    (observe) => sqlite(const SqliteOptions.memory(), onQuery: observe),
  );
  final url = Platform.environment['ORM_TEST_POSTGRES'];
  if (url != null) {
    const schema = 'orm_record_schema_tests';
    late Database<Postgres> admin;
    setUpAll(() async {
      admin = postgres(
        PostgresOptions(url: Uri.parse(url), tls: PostgresTls.disable),
      );
      await admin.execute(SqlCommand('CREATE SCHEMA "$schema"'));
    });
    tearDownAll(() async {
      await admin.execute(SqlCommand('DROP SCHEMA "$schema" CASCADE'));
      await admin.close();
    });
    runRecordTests(
      'postgres',
      (observe) async => postgres(
        PostgresOptions(
          url: Uri.parse(url),
          tls: PostgresTls.disable,
          schema: schema,
        ),
        onQuery: observe,
      ),
    );
  }
}

void runRecordTests(
  String name,
  Future<Database<Backend>> Function(void Function(QueryEvent)) open,
) {
  group('Record schema $name', () {
    late Database<Backend> db;
    final events = <QueryEvent>[];
    final constraintFailure = anyOf(
      isA<SqliteFailure>().having((e) => e.code, 'code', 19),
      isA<PostgresFailure>().having(
        (e) => e.code,
        'SQLSTATE',
        startsWith('23'),
      ),
    );
    final initial = Migration.create(
      '0001_initial',
      appSchema,
      dialect: SqlDialect.values.byName(name),
    );
    setUp(() async {
      db = await open(events.add);
      for (final table in [
        'project_members',
        'projects',
        'employees',
        'departments',
        '_orm_migrations',
      ]) {
        await db.execute(SqlCommand('DROP TABLE IF EXISTS "$table"'));
      }
      await Migrator(db.sql).apply([initial]);
      events.clear();
    });
    tearDown(() => db.close());

    Future<Employee> employee(
      String label,
      int departmentId, {
      int? managerId,
    }) => db.employee.create(
      name: label,
      email: '$label@example.com',
      departmentId: departmentId,
      managerId: managerId,
    );

    test(
      'generated rows, defaults, explicit relations and query counts',
      () async {
        final team = await db.department.create(name: 'Engineering');
        final manager = await employee('manager', team.id);
        final worker = await employee('worker', team.id, managerId: manager.id);
        expect(worker.active, true);
        expect(
          worker.createdAt
              .toUtc()
              .difference(DateTime.now().toUtc())
              .inSeconds
              .abs(),
          lessThan(10),
        );
        events.clear();
        expect(
          await db.employee
              .byId(worker.id)
              .select((e) => e.manager.select((m) => m.name).one())
              .single(),
          'manager',
        );
        expect(events.length, 1);
        expect(events.single.sql, contains('LEFT JOIN'));
        events.clear();
        expect(
          await db.employee
              .byId(manager.id)
              .select((e) => e.directReports.select((r) => r.name).many())
              .single(),
          ['worker'],
        );
        expect(events.length, 2);
        await db.employee.byId(worker.id).patch(name: .set('changed'));
        expect(
          (await db.employee.byId(worker.id).single()).managerId,
          manager.id,
        );
        await db.employee.byId(worker.id).patch(managerId: .set(null));
        expect((await db.employee.byId(worker.id).single()).managerId, isNull);
        final project = await db.project.create(
          name: 'Schema',
          ownerId: manager.id,
        );
        expect(project.status, ProjectStatus.draft);
        final member = await db.projectMember.create(
          projectId: project.id,
          employeeId: worker.id,
        );
        expect(member.role, MemberRole.member);
        expect(
          (await db.projectMember
                  .byId(projectId: project.id, employeeId: worker.id)
                  .single())
              .employeeId,
          worker.id,
        );
        await db.projectMember
            .byId(projectId: project.id, employeeId: worker.id)
            .patch(role: .set(MemberRole.maintainer));
        expect((await db.projectMember.single()).role, MemberRole.maintainer);
      },
    );

    test(
      'database enforces foreign keys, uniqueness and composite primary keys',
      () async {
        final team = await db.department.create(name: 'Engineering');
        final owner = await employee('owner', team.id);
        final project = await db.project.create(
          name: 'Schema',
          ownerId: owner.id,
        );
        await db.projectMember.create(
          projectId: project.id,
          employeeId: owner.id,
        );
        await expectLater(
          employee('owner', team.id),
          throwsA(constraintFailure),
        );
        await expectLater(employee('orphan', -1), throwsA(constraintFailure));
        await expectLater(
          db.projectMember.create(projectId: project.id, employeeId: owner.id),
          throwsA(constraintFailure),
        );
        expect(await db.employee.count(), 1);
        expect(await db.projectMember.count(), 1);
      },
    );

    test(
      'restrict, cascade and self-reference SET NULL reach the database',
      () async {
        final team = await db.department.create(name: 'Engineering');
        final manager = await employee('manager', team.id);
        final worker = await employee('worker', team.id, managerId: manager.id);
        final project = await db.project.create(
          name: 'Schema',
          ownerId: worker.id,
        );
        await db.projectMember.create(
          projectId: project.id,
          employeeId: worker.id,
        );
        await expectLater(
          db.department.byId(team.id).delete().execute(),
          throwsA(constraintFailure),
        );
        await expectLater(
          db.employee.byId(worker.id).delete().execute(),
          throwsA(constraintFailure),
        );
        await db.employee.byId(manager.id).delete().execute();
        expect((await db.employee.byId(worker.id).single()).managerId, isNull);
        await db.project.byId(project.id).delete().execute();
        expect(await db.projectMember.count(), 0);
        expect(await db.employee.count(), 1);
      },
    );

    test('generated creates respect transaction rollback', () async {
      await expectLater(
        db.transaction((tx) async {
          final team = await tx.department.create(name: 'rolled-back');
          await tx.employee.create(
            name: 'first',
            email: 'same@example.com',
            departmentId: team.id,
          );
          await tx.employee.create(
            name: 'second',
            email: 'same@example.com',
            departmentId: team.id,
          );
        }),
        throwsA(constraintFailure),
      );
      expect(await db.department.count(), 0);
      expect(await db.employee.count(), 0);
    });

    test(
      'frozen snapshot matches catalog and migration history is repeatable',
      () async {
        final verification = await verifySchema(db.sql, physical.schema);
        expect(verification.differences, isEmpty);
        expect(verification.unmanaged, isEmpty);
        expect(await Migrator(db.sql).apply([initial]), isEmpty);
        expect(
          (await Migrator(db.sql).history()).single.checksum,
          initial.checksum,
        );
      },
    );
  });
}
