@Tags(['database', 'mysql-suite'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:orm/mysql.dart';
import 'package:orm/mariadb.dart';
import 'package:test/test.dart';

void main() {
  for (final engine in ['mysql', 'mariadb']) {
    final variable = 'ORM_TEST_${engine.toUpperCase()}';
    final address = Platform.environment[variable];
    final tls = MysqlTls.values.byName(
      Platform.environment['${variable}_TLS'] ?? 'verifyFull',
    );
    group(
      engine,
      () {
        late Database<Backend> db;
        final idColumn = Column('id', Codecs.integer);
        final nameColumn = Column('name', Codecs.text);
        final table = TableSchema(
          'orm_raw_sql',
          columns: [idColumn, nameColumn],
        );
        final shape = (
          idColumn.result(),
          nameColumn.result(),
        ).map((id, name) => (id: id, name: name));
        final all = Sql('SELECT id, name FROM orm_raw_sql ORDER BY id')
            .returns(shape);
        setUp(() async {
          db = engine == 'mysql'
              ? await mysql(MysqlOptions(url: Uri.parse(address!), tls: tls))
              : await mariadb(
                  MariadbOptions(url: Uri.parse(address!), tls: tls),
                );
          await db.raw(Sql('DROP TABLE IF EXISTS orm_raw_sql'));
          await db.raw(
            Sql(
              'CREATE TABLE orm_raw_sql(id BIGINT PRIMARY KEY, name TEXT NOT NULL)',
            ),
          );
          await db.raw(Sql("INSERT INTO orm_raw_sql VALUES(1,'a'),(2,'b')"));
        });
        tearDown(() async {
          await db.raw(Sql('DROP TABLE IF EXISTS orm_raw_sql'));
          await db.close();
        });
        test(
          'typed fragments, empty metadata, stream capability and checks',
          () async {
            final q = Sql.join([
              Sql(
                'SELECT id, name FROM orm_raw_sql WHERE id=:id',
                parameters: {'id': 1},
              ),
              Sql(
                'SELECT id, name FROM orm_raw_sql WHERE id=:id',
                parameters: {'id': 2},
              ),
            ], separator: ' UNION ALL ').returns(shape);
            expect(await db.query(q), [(id: 1, name: 'a'), (id: 2, name: 'b')]);
            expect((await checkSqlQuery(db.sql, q)).structureChecked, true);
            expect(
              () => db.streamSql(all, batchSize: 1),
              throwsA(
                isA<OrmException>().having(
                  (e) => e.code,
                  'code',
                  'CAPABILITY.STREAM',
                ),
              ),
            );
            final invalid = Sql('SELECT id FROM orm_raw_sql WHERE 1=0')
                .returns(shape);
            await expectLater(db.query(invalid), throwsA(isA<OrmException>()));
          },
        );
        test(
          'codecs, positional repetition and driver type boundaries',
          () async {
            Future<void> echo<T>(T value, Codec<T> codec) async {
              final q = Sql(
                engine == 'mysql' && codec.sqlType == 'json'
                    ? 'SELECT CAST(:v AS CHAR) AS v'
                    : 'SELECT :v AS v',
                parameters: {'v': SqlValue(value, codec)},
              ).returns(ResultColumn('v', codec));
              final result = (await db.query(q)).single;
              expect(
                result is SqlJson ? result.value : result,
                value is SqlJson ? value.value : value,
              );
            }

            await echo(
              Decimal.parse('123456789012345.00000000001'),
              Codecs.decimal,
            );
            await echo(BigInt.parse('9007199254740993123'), Codecs.bigint);
            await echo(
              DateTime.utc(2024, 1, 2, 3, 4, 5, 6, 7),
              Codecs.dateTime,
            );
            await echo(LocalDate.parse('2024-01-02'), Codecs.date);
            await echo(LocalTime.parse('12:34:56.123456'), Codecs.time);
            await echo(
              LocalDateTime.parse('2024-01-02T12:34:56.123456'),
              Codecs.localDateTime,
            );
            // MySQL infers a bare parameter as text; BLOB column context keeps
            // binary metadata intact across the upstream driver protocol.
            await db.raw(Sql('ALTER TABLE orm_raw_sql ADD payload BLOB'));
            final bytes = Uint8List.fromList([0, 1, 255]);
            await db.raw(
              Sql(
                'UPDATE orm_raw_sql SET payload = :v WHERE id = 1',
                parameters: {'v': SqlValue(bytes, Codecs.bytes)},
              ),
            );
            expect(
              (await db.query(
                Sql('SELECT payload FROM orm_raw_sql WHERE id = 1')
                    .returns(ResultColumn('payload', Codecs.bytes)),
              )).single,
              bytes,
            );
            await echo(const SqlJson(null), Codecs.jsonDocument);
            await echo({
              'a': [1, null],
            }, Codecs.json);
            await echo(true, Codecs.boolean);
            await echo(3.5, Codecs.real);
            await echo<String?>(null, Codecs.text.nullable());
            expect(
              (await db.query(
                Sql(
                  'SELECT CAST(:n + :n AS SIGNED) AS n',
                  parameters: {'n': 3},
                ).returns(ResultColumn('n', Codecs.integer)),
              )).single,
              6,
            );
          },
        );
        test(
          'decode failure rolls back and watch follows committed writes',
          () async {
            await expectLater(
              db.transaction((tx) async {
                await tx.raw(
                  Sql("UPDATE orm_raw_sql SET name='pending' WHERE id=1"),
                  changedTables: [table],
                );
                try {
                  await tx.query(
                    Sql('SELECT id FROM orm_raw_sql WHERE 1=0').returns(shape),
                  );
                } on OrmException {
                  /* still must roll back */
                }
              }),
              throwsA(isA<OrmException>()),
            );
            expect((await db.query(all)).first.name, 'a');
            final snapshots = StreamIterator(db.watchSql(all, reads: [table]));
            try {
              expect(await snapshots.moveNext(), true);
              final next = snapshots.moveNext();
              await db.transaction(
                (tx) => tx.raw(
                  Sql("UPDATE orm_raw_sql SET name='committed' WHERE id=1"),
                  changedTables: [table],
                ),
              );
              expect(await next.timeout(const Duration(seconds: 3)), true);
              expect(snapshots.current.first.name, 'committed');
            } finally {
              await snapshots.cancel();
            }
          },
        );
      },
      tags: engine,
      skip: address == null ? 'Set $variable to a disposable database.' : false,
    );
  }
}
