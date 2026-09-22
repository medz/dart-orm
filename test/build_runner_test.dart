@Tags(['core'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/src/build_fixture.dart';

void main() {
  test('real build_runner build/watch tracks imports, recovers errors and deletes stale outputs', () async {
    final fixture = await BuildFixture.create(ormPath: Directory.current.path);
    BuildWatch? watcher;
    try {
      await fixture.file('build.yaml').writeAsString('''
      orm:queries:
        enabled: true
        generate_for:
          - lib/queries.dart
''', mode: FileMode.append);
      await fixture.write('lib/queries.dart', '''
import 'package:orm/schema.dart';
import 'models.dart';
final namedRows = sqlQuery(result: (title: text(), status: enumeration(Status.values, labels: {Status.pending: pendingLabel, Status.ready: 'ready'})), parameters: (minimum: integer(),), sqlite: 'rows.sql');
''');
      const sql = 'SELECT title, status FROM rows_0 WHERE score >= :minimum';
      await fixture.write('lib/rows.sql', sql);
      final client = fixture.file('lib/schema.orm.dart');
      final snapshot = fixture.file('lib/schema.snapshot.dart');
      final queries = fixture.file('lib/queries.queries.dart');
      await fixture.write('bin/read_schema.dart', r'''
import 'dart:convert';
import '../lib/schema.snapshot.dart';
void main() => print('@@schema ${jsonEncode(schema.toJson())}');
''');
      Future<Map<String, Object?>> inspectSnapshot() async {
        final result = await fixture.run([
          'run',
          'orm_build_fixture:read_schema',
        ]);
        final line = result.output
            .split('\n')
            .firstWhere((l) => l.startsWith('@@schema '));
        return jsonDecode(line.substring('@@schema '.length))
            as Map<String, Object?>;
      }

      final first = await fixture.run(['run', 'build_runner', 'build']);
      expect(first.output, contains('wrote 3 outputs'));
      expect(await queries.readAsString(), contains('NamedRowsFields'));
      expect(await client.exists(), true);
      expect(await snapshot.exists(), true);
      final before = await client.stat();
      final unchanged = await fixture.run(['run', 'build_runner', 'build']);
      expect(unchanged.output, contains('wrote 0 outputs'));
      expect((await client.stat()).modified, before.modified);

      watcher = await fixture.watch();
      expect(await watcher.next(), contains('wrote 0 outputs'));
      await fixture.write(
        'lib/schema.dart',
        BuildFixture.schema(1, extra: true),
      );
      await watcher.next();
      expect(await client.readAsString(), contains('required bool enabled'));

      await fixture.write(
        'lib/models.dart',
        BuildFixture.domain(label: 'ready-now', defaultScore: 7),
      );
      await watcher.next();
      expect(await client.readAsString(), contains('"ready-now"'));
      expect(await queries.readAsString(), contains('"ready-now"'));
      final json = await inspectSnapshot();
      final tables = json['tables'] as List<Object?>;
      final columns =
          (tables.single as Map<String, Object?>)['columns'] as List<Object?>;
      expect(
        columns.cast<Map<String, Object?>>().singleWhere(
          (c) => c['name'] == 'score',
        )['default'],
        '7',
      );

      final stable = await client.stat();
      await fixture.write('lib/unrelated.dart', 'const unrelated = 2;\n');
      await watcher.quiet();
      expect((await client.stat()).modified, stable.modified);

      await fixture.write('lib/rows.sql', '$sql ORDER BY title');
      await watcher.next();
      expect(await queries.readAsString(), contains('ORDER BY title'));
      await fixture.write(
        'lib/rows.sql',
        'SELECT :unknown AS title, status FROM rows_0',
      );
      await watcher.next(success: false);
      await fixture.write('lib/rows.sql', sql);
      await watcher.next();
      expect(await queries.readAsString(), isNot(contains('ORDER BY title')));

      await fixture.write(
        'lib/schema.dart',
        BuildFixture.schema(1, extra: true, invalid: true),
      );
      await watcher.next(success: false);
      await fixture.write(
        'lib/schema.dart',
        BuildFixture.schema(1, extra: true),
      );
      await watcher.next();
      await fixture.run(['analyze', 'lib']);

      await fixture.file('lib/schema.dart').delete();
      await watcher.next();
      expect(await client.exists(), false);
      expect(await snapshot.exists(), false);
      await fixture.write('lib/schema.dart', BuildFixture.schema(1));
      await watcher.next();
      expect(await client.exists(), true);
      expect(await snapshot.exists(), true);
      await fixture.file('lib/queries.dart').delete();
      await watcher.next();
      expect(await queries.exists(), false);
      expect(await fixture.file('lib/queries.queries.json').exists(), false);
    } finally {
      await watcher?.close();
      await fixture.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
