import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/src/build_fixture.dart';

void main() {
  test('real build_runner build/watch tracks imports, recovers errors and deletes stale outputs', () async {
    final fixture = await BuildFixture.create(ormPath: Directory.current.path);
    BuildWatch? watcher;
    try {
      final client = fixture.file('lib/schema.orm.dart');
      final snapshot = fixture.file('lib/schema.orm.json');
      final first = await fixture.run(['run', 'build_runner', 'build']);
      expect(first.output, contains('wrote 2 outputs'));
      expect(await client.exists(), true);
      expect(
        (jsonDecode(await snapshot.readAsString()) as Map)['tables'],
        hasLength(1),
      );
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
      final json =
          jsonDecode(await snapshot.readAsString()) as Map<String, Object?>;
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
    } finally {
      await watcher?.close();
      await fixture.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
