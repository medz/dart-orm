@Tags(['core'])
library;

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
final entry = model('entries', (
  id: integer(), source: integer(),
  computed: integer().nullable().computed('source + 1', postgres: 'source + 2', mysql: 'source + 3', mariadb: 'source + 4'),
), primaryKey: (e) => e.id, checks: [check('source >= 1', name: 'valid', postgres: 'source >= 2', mysql: 'source >= 3', mariadb: 'source >= 4')]);
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
}
