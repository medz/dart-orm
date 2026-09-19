import 'dart:io';

import 'package:orm/generate.dart';
import 'package:orm/migrate.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory('.dart_tool').createTemp('generator-dialects-');
  });
  tearDown(() => directory.delete(recursive: true));

  test('computed and check overrides retain all engines and freeze only the selected expression', () async {
    final source = File('${directory.path}/schema.dart');
    await source.writeAsString('''
import 'package:orm/schema.dart';
final class Entry(
  @Id() final int id,
  final int source,
  @Computed.sql('source + 1', postgres: 'source + 2', mysql: 'source + 3', mariadb: 'source + 4') final int? computed,
);
final entries = entity<Entry>();
final valid = entries.check('source >= 1', postgres: 'source >= 2', mysql: 'source >= 3', mariadb: 'source >= 4');
''');
    final result = await generateSchema(source.path);
    for (final (index, dialect) in SqlDialect.values.indexed) {
      final table = result.snapshot.forDialect(dialect).tables.single;
      expect(
        table.columns.last.computed!.expression(dialect),
        'source + ${index + 1}',
      );
      expect(table.checks.single.expression(dialect), 'source >= ${index + 1}');
    }
    expect(result.dart, contains('mysql: "source + 3"'));
    expect(result.dart, contains('mariadb: "source + 4"'));
    expect(result.dart, contains('mysql: "source >= 3"'));
    expect(result.dart, contains('mariadb: "source >= 4"'));
  });

  test(
    'all named SQL backends emit QueryContext bindings and complete manifests',
    () async {
      final source = File('${directory.path}/queries.dart');
      await source.writeAsString('''
import 'package:orm/schema.dart';
typedef Result = ({int value});
final result = sqlQuery<Result, ({int minimum})>(
  sqlite: 'query.sql',
  postgres: 'query.sql',
  mysql: 'query.sql',
  mariadb: 'query.sql',
);
final mysqlOnly = sqlQuery<Result, ({int minimum})>(mysql: 'query.sql');
final mariaOnly = sqlQuery<Result, ({int minimum})>(mariadb: 'query.sql');
''');
      await File('${directory.path}/query.sql')
          .writeAsString('SELECT :minimum AS value');
      final generated = await generateQueries(source.path);
      final queries = (generated.manifest['queries'] as List)
          .cast<Map<String, Object?>>();
      expect((queries.first['sql'] as Map).keys, [
        'sqlite',
        'postgres',
        'mysql',
        'mariadb',
      ]);
      expect((queries[1]['sql'] as Map).keys, ['mysql']);
      expect((queries[2]['sql'] as Map).keys, ['mariadb']);
      expect(generated.dart, contains("import 'package:orm/sql.dart'"));
      expect(generated.dart, contains('extension ResultSql on QueryContext'));
      expect(generated.dart, isNot(contains('Database<')));
      await writeGeneratedQueries(source.path);
      final analyzed = await Process.run(Platform.resolvedExecutable, [
        'analyze',
        '${directory.path}/queries.queries.dart',
      ]);
      expect(
        analyzed.exitCode,
        0,
        reason: '${analyzed.stdout}\n${analyzed.stderr}',
      );
      final consumer = File('${directory.path}/compile.dart');
      await consumer.writeAsString('''
import 'package:orm/sql.dart';
import 'queries.queries.dart';
void main() {
  for (final dialect in SqlDialect.values) {
    final sql = SqlBuilder(dialect).result(minimum: 4).compile();
    if (sql.parameters.length != 1 || sql.parameters.single != 4) {
      throw StateError('Named parameter did not bind exactly once.');
    }
  }
  try {
    SqlBuilder(SqlDialect.sqlite).mysqlOnly(minimum: 1);
    throw StateError('Unsupported backend was accepted.');
  } on OrmException catch (error) {
    if (error.code != 'QUERY.DIALECT') rethrow;
  }
}
''');
      final compiled = await Process.run(Platform.resolvedExecutable, [
        'run',
        consumer.path,
      ]);
      expect(
        compiled.exitCode,
        0,
        reason: '${compiled.stdout}\n${compiled.stderr}',
      );
    },
  );
}
