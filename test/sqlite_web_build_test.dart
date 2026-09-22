@Tags(['core'])
library;

import 'dart:io';

import 'package:test/test.dart';

import '../tool/build_sqlite_web.dart';

void main() {
  test(
    'worker inputs include both protocol endpoints and shared execution',
    () async {
      final paths = await sqliteWebSourcePaths();
      expect(
        paths,
        containsAll([
          'lib/sqlite_web_worker.dart',
          'lib/src/sqlite/web_worker.dart',
          'lib/src/sqlite/web.dart',
          'lib/src/sqlite/web_client.dart',
          'lib/src/sqlite/web_wire.dart',
          'lib/src/sqlite/execution.dart',
          'lib/src/sqlite/decimal.dart',
          'lib/src/values/codec.dart',
          'lib/src/driver/driver.dart',
        ]),
      );
      expect(paths, isNot(contains('lib/src/sqlite/web_build.dart')));
      expect(
        paths.where(
          (p) =>
              p.contains('/cli/') ||
              p.contains('/generate/') ||
              p.contains('/postgres/') ||
              p.contains('/native'),
        ),
        isEmpty,
      );
    },
  );

  test('dependency traversal follows exports, package imports and conditional URIs', () async {
    final root = await Directory.systemTemp.createTemp('orm-web-inputs-');
    addTearDown(() => root.delete(recursive: true));
    for (final entry in {
      'lib/sqlite_web_worker.dart': "export 'src/worker.dart';",
      'lib/src/worker.dart': "import 'package:orm/src/shared.dart'; import 'package:web/web.dart';",
      'lib/src/shared.dart': "export '../sqlite_web_worker.dart';",
      'lib/src/sqlite/web.dart': "import 'fallback.dart' if (dart.library.js_interop) 'browser.dart'; import 'web_build.dart';",
      'lib/src/sqlite/fallback.dart': '',
      'lib/src/sqlite/browser.dart': "import '../shared.dart';",
      'lib/src/cli/runner.dart': 'This unrelated source need not even parse.',
    }.entries) {
      final file = File('${root.path}/${entry.key}');
      await file.parent.create(recursive: true);
      await file.writeAsString(entry.value);
    }
    expect(await sqliteWebSourcePaths(root: root.path), [
      'lib/sqlite_web_worker.dart',
      'lib/src/shared.dart',
      'lib/src/sqlite/browser.dart',
      'lib/src/sqlite/fallback.dart',
      'lib/src/sqlite/web.dart',
      'lib/src/worker.dart',
    ]);
  });
}
