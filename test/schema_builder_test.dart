@Tags(['core'])
library;

import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:orm/builder.dart';
import 'package:test/test.dart';

import '../tool/src/build_fixture.dart';
import 'support/cli.dart';

void main() {
  test(
    'package builder collects namespaces without a root Dart file',
    () async {
      final files = TestReaderWriter(rootPackage: 'orm', flattenOutput: true);
      await files.testing.loadIsolateSources();
      final result = await testBuilder(
        ormBuilder(
          BuilderOptions({
            'schema': 'lib/fixture/./schema.dart',
            'database': 'postgres',
          }),
        ),
        {
          'orm|lib/fixture/schema/auth/users.dart': "import 'package:orm/schema.dart'; final user = model('users', (id: identity(),));",
          'orm|lib/fixture/schema/public/users.dart': "import 'package:orm/schema.dart'; final user = model('users', (id: identity(),));",
        },
        rootPackage: 'orm',
        readerWriter: files,
        flattenOutput: true,
      );
      expect(result.succeeded, true, reason: result.errors.toString());
      final client = files.testing.readString(
        AssetId('orm', 'lib/fixture/schema.orm.dart'),
      );
      expect(client, contains('final class AuthUser('));
      expect(client, contains('final class PublicUser('));
    },
  );

  test('real directory build/watch tracks addition, removal, imports and CLI parity', () async {
    final fixture = await BuildFixture.create(ormPath: Directory.current.path);
    BuildWatch? watcher;
    try {
      await fixture.file('lib/schema.dart').delete();
      await fixture.write('build.yaml', '''
targets:
  \$default:
    builders:
      orm:orm:
        enabled: true
        options:
          schema: lib/fixture/schema
          database: postgres
''');
      await fixture.write(
        'lib/fixture/schema/public/users.dart',
        "import 'package:orm/schema.dart'; final user = model('users', (id: identity(),));",
      );
      await fixture.run(['run', 'build_runner', 'build']);
      final client = fixture.file('lib/fixture/schema.orm.dart');
      final snapshot = fixture.file('lib/fixture/schema.snapshot.dart');
      expect(await client.readAsString(), contains('get user =>'));
      final generated = await client.readAsString(),
          frozen = await snapshot.readAsString();
      final result = await runCli([
        'generate',
        fixture.file('lib/fixture/schema').path,
        '--database',
        'postgres',
      ]);
      expect(result.exitCode, 0, reason: result.stderr);
      expect(await client.readAsString(), generated);
      expect(await snapshot.readAsString(), frozen);
      watcher = await fixture.watch();
      await watcher.next();
      await fixture.write(
        'lib/fixture/schema/auth/users.dart',
        "import 'package:orm/schema.dart'; final user = model('users', (id: identity(),));",
      );
      await watcher.next();
      expect(await client.readAsString(), contains('AuthUser'));
      expect(await client.readAsString(), contains('PublicUser'));
      final beforeMove = await snapshot.readAsString();
      await fixture
          .file('lib/fixture/schema/auth/users.dart')
          .rename(fixture.file('lib/fixture/schema/auth/accounts.dart').path);
      await watcher.next();
      expect(await snapshot.readAsString(), beforeMove);
      await fixture.file('lib/fixture/schema/auth/accounts.dart').delete();
      await watcher.next();
      expect(await client.readAsString(), isNot(contains('AuthUser')));
      expect(await client.readAsString(), contains('get user =>'));
      await fixture.write('lib/unrelated.dart', 'const unused = 1;');
      await watcher.quiet();
      await watcher.close();
      watcher = null;
      await fixture.run(['analyze', 'lib/fixture/schema.orm.dart']);
    } finally {
      await watcher?.close();
      await fixture.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
