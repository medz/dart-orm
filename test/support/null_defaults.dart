import 'package:orm/migrate.dart';
import 'package:orm/runtime.dart';
import 'package:test/test.dart';

TableSchema _nullDefaults(
  SqlDialect dialect, {
  bool omitNullDefaults = false,
  String numberDefault = '7',
  String textDefault = "'NULL'",
}) {
  final sql = omitNullDefaults ? null : 'NULL';
  return TableSchema(
    'null_defaults',
    columns: [
      Column('id', Codecs.integer),
      for (final bits in [16, 32, 64])
        Column(
          'int$bits',
          Codecs.integer.nullable(),
          nullable: true,
          integerBits: bits,
          defaultSql: sql,
        ),
      Column('label', Codecs.text.nullable(), nullable: true, defaultSql: sql),
      Column(
        'enabled',
        Codecs.boolean.nullable(),
        nullable: true,
        defaultSql: sql,
      ),
      Column('bytes', Codecs.bytes.nullable(), nullable: true, defaultSql: sql),
      Column(
        'document',
        Codecs.json.nullable(),
        nullable: true,
        defaultSql: sql,
      ),
      Column(
        'amount',
        Codecs.decimal.nullable(),
        nullable: true,
        defaultSql: sql,
        decimalPrecision: 12,
        decimalScale: 2,
      ),
      Column('date', Codecs.date.nullable(), nullable: true, defaultSql: sql),
      Column(
        'time',
        Codecs.time.nullable(),
        nullable: true,
        defaultSql: sql,
        temporalPrecision: 3,
      ),
      Column(
        'local',
        Codecs.localDateTime.nullable(),
        nullable: true,
        defaultSql: sql,
        temporalPrecision: 3,
      ),
      Column(
        'instant',
        Codecs.dateTime.nullable(),
        nullable: true,
        defaultSql: sql,
        temporalPrecision: 3,
      ),
      Column(
        'cast_value',
        Codecs.integer.nullable(),
        nullable: true,
        defaultSql: omitNullDefaults
            ? null
            : 'CAST(NULL AS ${dialect == SqlDialect.mysql || dialect == SqlDialect.mariadb ? 'SIGNED' : 'BIGINT'})',
      ),
      if (dialect == SqlDialect.postgres)
        Column(
          'pg_cast',
          Codecs.integer.nullable(),
          nullable: true,
          defaultSql: omitNullDefaults ? null : '(NULL)::integer',
        ),
      Column(
        'number_value',
        Codecs.integer.nullable(),
        nullable: true,
        defaultSql: numberDefault,
      ),
      Column(
        'text_value',
        Codecs.text.nullable(),
        nullable: true,
        defaultSql: textDefault,
      ),
    ],
    primaryKey: ['id'],
  );
}

/// Exercises live catalogs without changing frozen defaults or checksums.
Future<void> checkNullDefaults(SqlDatabase<Backend> db) async {
  final table = _nullDefaults(db.dialect);
  final migration = Migration.create('0001_null_defaults', [
    table,
  ], dialect: db.dialect);
  final frozenSource = migrationSource(migration);
  final checksum = migration.checksum;
  await Migrator(db).apply([migration]);
  expect((await verifySchema(db, migration.snapshot!)).differences, isEmpty);

  final withoutNull = SchemaSnapshot([
    _nullDefaults(db.dialect, omitNullDefaults: true),
  ]);
  expect(
    (await verifySchema(db, withoutNull)).differences,
    isEmpty,
    reason: 'A nullable built-in NULL default and no default insert the same SQL NULL.',
  );
  await db.execute(SqlCommand('INSERT INTO "null_defaults" ("id") VALUES (1)'));
  final nullColumns = table.columns.where(
    (c) => !['id', 'number_value', 'text_value'].contains(c.name),
  );
  final nullRows = await db.execute(
    SqlCommand(
      'SELECT COUNT(*) FROM "null_defaults" WHERE ${nullColumns.map((c) => '"${c.name}" IS NULL').join(' AND ')}',
    ),
  );
  expect(nullRows.rows.single.single, 1);

  final changed = SchemaSnapshot([
    _nullDefaults(db.dialect, numberDefault: 'NULL', textDefault: 'NULL'),
  ]);
  expect(
    (await verifySchema(db, changed)).differences,
    unorderedEquals([
      'null_defaults.number_value default differs',
      'null_defaults.text_value default differs',
    ]),
    reason: 'Do not hide non-NULL values or the string literal NULL.',
  );
  expect(migration.checksum, checksum);
  expect(migrationSource(migration), frozenSource);
  expect((await Migrator(db).requireVersion([migration])).checksum, checksum);
  expect(migration.snapshot!.tables.single.columns[1].defaultSql, 'NULL');
}
