import 'package:orm/driver.dart';
import 'package:orm/orm.dart';
import 'package:orm/sql.dart';

import 'schema.orm.dart';

/// Directory-owned fields; email is this source's stable external key.
typedef DirectoryEmployee = ({String email, String name, int departmentId});

/// Synchronizes names and departments inside the caller's transaction.
///
/// Existing IDs, creation times, active flags and manager links stay unchanged.
/// Newly inserted employees receive their declared defaults. Input keys must not
/// conflict with one another under the database's unique-key rules if results
/// must be independent of statement chunking; this function does not attempt to
/// reproduce those rules in Dart. Returned rows have no input-order guarantee.
/// Let failures escape the transaction callback to roll back the whole import.
Future<List<Employee>> syncDirectory(
  Database<Backend> tx,
  Iterable<DirectoryEmployee> entries,
) async {
  if (!tx.inTransaction) {
    throw StateError('syncDirectory needs an explicit transaction.');
  }
  final BatchInsert<EmployeeFields> batch = tx.employee.plan
      .insertMany([
        for (final row in entries)
          employeeInsert(
            email: row.email,
            name: row.name,
            departmentId: row.departmentId,
          ),
      ])
      .prepare()
      .onConflictUpdate(
        target: (e) => [e.email],
        set: (existing, incoming) => [
          existing.name.setExpression(incoming.name),
          existing.departmentId.setExpression(incoming.departmentId),
        ],
      );
  final BatchReturning<Employee> returning = batch.returning(
    employeeTable.selectRow,
  );
  return returning.get();
}
