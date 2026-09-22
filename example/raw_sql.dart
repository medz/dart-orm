import 'package:orm/migrate.dart';
import 'package:orm/sqlite.dart';

import 'schema.orm.dart';

final u = userTable.alias().fields;
final userRow = (
  u.id.result(),
  u.email.result(),
).map((id, email) => (id: id, email: email));

SqlQuery<({int id, String email})> userById(int id) => Sql(
  'SELECT email, id FROM users WHERE id = :id',
  parameters: {'id': u.id.bind(id)},
).returns(userRow);

Future<void> main() async {
  final db = await sqlite(const SqliteOptions.memory());
  try {
    for (final command in createSchema(appSchema, db.dialect)) {
      await db.execute(command);
    }
    final user = await db.user.create(email: 'ada@example.com');
    final query = userById(user.id);
    await checkSqlQuery(db.sql, query);
    print(await db.query(query));
    await db.transaction((tx) async {
      print(await tx.query(query));
    });
    await for (final row in db.streamSql(query, batchSize: 16)) {
      print(row.email);
    }
  } finally {
    await db.close();
  }
}
