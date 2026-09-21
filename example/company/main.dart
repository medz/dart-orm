import 'package:orm/migrate.dart';
import 'package:orm/sqlite.dart';

import 'schema.orm.dart';

Future<void> main() async {
  final db = await sqlite(const SqliteOptions.memory());
  try {
    await Migrator(
      db.sql,
    ).apply([Migration.create('0001_company', appSchema, dialect: db.dialect)]);
    final worker = await db.transaction((tx) async {
      final team = await tx.department.create(name: 'Engineering');
      final manager = await tx.employee.create(
        name: 'Alice',
        email: 'alice@example.com',
        departmentId: team.id,
      );
      return tx.employee.create(
        name: 'Bob',
        email: 'bob@example.com',
        departmentId: team.id,
        managerId: manager.id,
      );
    });
    final String? managerName = await db.employee
        .byId(worker.id)
        .select((e) => e.manager.select((m) => m.name).one())
        .single();
    print('${worker.name} reports to $managerName');
  } finally {
    await db.close();
  }
}
