@Tags(['core'])
library;

import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:orm/builder.dart';
import 'package:test/test.dart';

import '../tool/src/build_fixture.dart';
import 'support/cli.dart';

String _model(String name, String namespace) =>
    '''
import 'package:orm/schema.dart';
@Model(table: 'users', namespace: '$namespace')
class $name {
  @Id(generated: true) final int id;
  const $name({required this.id});
}
''';

void main() {
  test(
    'package builder collects recursive sources without a root Dart file',
    () async {
      final files = TestReaderWriter(rootPackage: 'orm', flattenOutput: true);
      await files.testing.loadIsolateSources();
      final result = await testBuilder(
        ormBuilder(
          BuilderOptions({
            'models': 'lib/fixture/./schema.dart',
            'database': 'postgres',
          }),
        ),
        {
          'orm|lib/fixture/schema/accounts/deep/users.dart': _model(
            'Account',
            'auth',
          ),
          'orm|lib/fixture/schema/users.dart': _model('User', 'public'),
        },
        rootPackage: 'orm',
        readerWriter: files,
        flattenOutput: true,
      );
      expect(result.succeeded, true, reason: result.errors.toString());
      final client = files.testing.readString(
        AssetId('orm', 'lib/fixture/schema.orm.dart'),
      );
      expect(client, contains('get account =>'));
      expect(client, contains('get user =>'));
      expect(client, isNot(contains('get auth =>')));
    },
  );

  test('real directory build/watch tracks addition, removal, movement and CLI parity', () async {
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
          models: lib/fixture/schema
          database: postgres
''');
      await fixture.write(
        'lib/fixture/schema/users.dart',
        _model('User', 'public'),
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
        'lib/fixture/schema/features/nested/accounts.dart',
        _model('Account', 'auth'),
      );
      await watcher.next();
      expect(await client.readAsString(), contains('get account =>'));
      final beforeMove = await snapshot.readAsString();
      await fixture
          .file('lib/fixture/schema/features/nested/accounts.dart')
          .rename(fixture.file('lib/fixture/schema/accounts.dart').path);
      await watcher.next();
      expect(await snapshot.readAsString(), beforeMove);
      await fixture.file('lib/fixture/schema/accounts.dart').delete();
      await watcher.next();
      expect(await client.readAsString(), isNot(contains('get account =>')));
      expect(await client.readAsString(), contains('get user =>'));
      await fixture.write('lib/unrelated.dart', 'const unused = 1;');
      await watcher.quiet();
      await fixture.file('lib/fixture/schema/users.dart').delete();
      await watcher.next();
      expect(await client.exists(), false);
      expect(await snapshot.exists(), false);
      await fixture.write(
        'lib/fixture/schema/users.dart',
        _model('User', 'public'),
      );
      await watcher.next();
      expect(await client.exists(), true);
      expect(await snapshot.exists(), true);
      await watcher.close();
      watcher = null;
      await fixture.run(['analyze', 'lib/fixture/schema.orm.dart']);
    } finally {
      await watcher?.close();
      await fixture.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
