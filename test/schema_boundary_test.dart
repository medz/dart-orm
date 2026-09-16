import 'dart:io';

import 'package:orm/generate.dart';
import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

void main() {
  test(
    'schema rejects malformed names, keys and local FK definitions offline',
    () {
      final id = Column('id', Codecs.integer);
      for (final table in [
        TableSchema('', columns: [id]),
        TableSchema('bad\u0000name', columns: [id]),
        TableSchema('items', columns: [Column('', Codecs.integer)]),
        TableSchema('items', columns: [id], uniqueKeys: [[]]),
        TableSchema('items', columns: [id], primaryKey: ['id', 'id']),
        TableSchema(
          'items',
          columns: [Column('id', Codecs.integer.nullable(), nullable: true)],
          primaryKey: ['id'],
        ),
        TableSchema(
          'items',
          columns: [id],
          indexes: [
            const IndexSchema('items', ['id']),
          ],
        ),
        TableSchema(
          'items',
          columns: [id],
          foreignKeys: [
            const ForeignKey(['missing'], 'other', ['id']),
          ],
        ),
        TableSchema(
          'items',
          columns: [id],
          foreignKeys: [
            const ForeignKey(['id'], 'other', []),
          ],
        ),
      ]) {
        expect(() => SchemaSnapshot([table]), throwsA(isA<OrmException>()));
      }
      final long = SchemaSnapshot([
        TableSchema('界' * 22, columns: [id]),
      ]);
      expect(long.forDialect(.sqlite).tables, hasLength(1));
      expect(() => long.forDialect(.postgres), throwsA(isA<OrmException>()));
    },
  );

  test('identifier case is resolved for the selected database', () async {
    TableSchema table(String name) =>
        TableSchema(name, columns: [Column('id', Codecs.integer)]);
    for (final snapshot in [
      SchemaSnapshot([table('Items'), table('items')]),
      SchemaSnapshot([
        TableSchema(
          'items',
          columns: [Column('id', Codecs.integer), Column('ID', Codecs.integer)],
        ),
      ]),
      SchemaSnapshot([
        TableSchema(
          'items',
          columns: [Column('id', Codecs.integer)],
          checks: [
            const CheckSchema('valid', 'id > 0'),
            const CheckSchema('VALID', 'id < 10'),
          ],
        ),
      ]),
    ]) {
      expect(snapshot.forDialect(.postgres).tables, isNotEmpty);
      expect(() => snapshot.forDialect(.sqlite), throwsA(isA<OrmException>()));
    }
  });

  for (final dialect in SqlDialect.values) {
    test(
      'generated ${dialect.name} schema executes its native computed-key contract',
      () async {
        final url = Platform.environment['ORM_TEST_POSTGRES'];
        if (dialect == .postgres && url == null) return;
        final directory = await Directory('.dart_tool')
            .createTemp('schema-boundary-');
        final file = File('${directory.path}/schema.dart');
        await file.writeAsString(
          "import 'package:orm/schema.dart';\n${dialect == .sqlite ? '''
typedef Item = ({int id, @Unique() @Computed.sql('id + 1', storage: ComputedStorage.virtual) int value});
final items = entity<Item>();
''' : '''
typedef Item = ({int source, @Id() @Computed.sql('source + 1') int id});
final items = entity<Item>(table: 'Items');
final lower = items.check('source > 0', name: 'valid');
final upper = items.check('source < 10', name: 'VALID');
'''}",
        );
        final generated = await generateSchema(file.path);
        final Database<Backend> db = dialect == .sqlite
            ? await sqlite(const SqliteOptions.memory())
            : postgres(
                PostgresOptions(
                  url: Uri.parse(url!),
                  tls: .disable,
                  schema: 'orm_schema_boundary_tests',
                ),
              );
        try {
          if (dialect == .postgres) {
            await db.execute(
              SqlCommand(
                'DROP SCHEMA IF EXISTS orm_schema_boundary_tests CASCADE',
              ),
            );
            await db.execute(
              SqlCommand('CREATE SCHEMA orm_schema_boundary_tests'),
            );
          }
          await Migrator(db).apply([
            Migration.create(
              '0001_native',
              generated.snapshot.tables,
              dialect: dialect,
            ),
          ]);
          await db.execute(
            SqlCommand(
              dialect == .sqlite
                  ? 'INSERT INTO items (id) VALUES (1)'
                  : 'INSERT INTO "Items" (source) VALUES (1)',
            ),
          );
          final result = await db.execute(
            SqlCommand(
              dialect == .sqlite
                  ? 'SELECT value FROM items'
                  : 'SELECT id FROM "Items"',
            ),
          );
          expect(result.rows.single.single, 2);
          expect((await verifySchema(db, generated.snapshot)).matches, true);
          await db.execute(
            SqlCommand('CREATE TABLE on_query (id INTEGER NOT NULL)'),
          );
          final imported = await importSchema(db);
          expect(
            imported.hasBlockingIssues,
            false,
            reason: imported.issues.map((i) => i.code).join(', '),
          );
          expect(imported.entities['on_query'], isNot('onQuery'));
          final importedFile = File('${directory.path}/imported.dart');
          await importedFile.writeAsString(imported.dart);
          final regenerated = await generateSchema(importedFile.path);
          expect((await verifySchema(db, regenerated.snapshot)).matches, true);
        } finally {
          await db.close();
          await directory.delete(recursive: true);
        }
      },
      skip:
          dialect == .postgres &&
              Platform.environment['ORM_TEST_POSTGRES'] == null
          ? 'Set ORM_TEST_POSTGRES.'
          : false,
    );
  }
}
