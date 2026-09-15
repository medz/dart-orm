import 'package:orm/migrate.dart';
import 'package:orm/orm.dart';

final payload = TableSchema(
  'payload',
  columns: [
    Column('id', Codecs.integer),
    Column('source', Codecs.text.nullable(), nullable: true),
    Column('value', Codecs.text.nullable(), nullable: true),
    Column('touches', Codecs.integer, defaultSql: '0'),
  ],
  primaryKey: ['id'],
);
Migration initialFor(SqlDialect dialect) =>
    Migration.create('0001_initial', [payload], dialect: dialect);
Migration fill({
  required SqlDialect dialect,
  int batchSize = 3,
  String? doneWhen,
  Map<String, String>? set,
}) => Migration.steps(
  '0002_fill',
  [
    Backfill(
      payload,
      set: set ?? {'value': 'upper(source)', 'touches': 'touches + 1'},
      where: 'value IS NULL',
      batchSize: batchSize,
      doneWhen: doneWhen ?? 'SELECT NOT EXISTS(SELECT 1 FROM payload WHERE value IS NULL OR touches <> 1)',
    ),
  ],
  previous: initialFor(dialect).checksum,
  dialect: dialect,
);

Future<void> seed(Database<Backend> db, {int count = 8}) async {
  await Migrator(db).apply([initialFor(db.dialect)]);
  for (var i = 1; i <= count; i++) {
    await db.execute(
      SqlCommand(
        'INSERT INTO payload(id, source) VALUES (${db.dialect == SqlDialect.sqlite ? '?1, ?2' : r'$1, $2'})',
        [i, 'v$i'],
      ),
    );
  }
}
