@Tags(['core'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:orm/generate.dart';
import 'package:orm/src/generate/types.dart';
import 'package:test/test.dart';

import '../tool/src/conditional_default_consumer.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory('.dart_tool').createTemp('conditional-default-');
  });
  tearDown(() => root.delete(recursive: true));

  Future<void> write(String path, String source) async {
    final file = File('${root.path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString(source);
  }

  Future<GeneratedSchema> generate(
    String source, {
    String output = 'client.dart',
  }) async {
    await write('models.dart', source);
    final result = await generateSchema(
      '${root.path}/models.dart',
      outputPath: '${root.path}/$output',
    );
    await write(output, result.dart);
    return result;
  }

  const model = '''
import 'package:orm/schema.dart';
@Model()
final class Row({
  @Id() required final int id,
  @ClientDefault(h.next) required final String label,
  @ClientDefault(h.Labels.next) required final String staticLabel,
  @ClientDefault(h.empty<String>) required final String genericLabel,
  @ClientDefault(h.alias) required final String aliasLabel,
});
''';
  const helpers = '''
String next() => 'native';
class Labels { static String next() => 'native'; }
T empty<T>() => 'native' as T;
const alias = next;
''';

  test('fresh native consumer applies saved history and preserves defaults and DTO methods', () async {
    final fixture = await conditionalDefaultConsumer(
      Directory.current.absolute.path,
    );
    addTearDown(fixture.dispose);
    final before = await conditionalDefaultHashes(fixture);
    final report = await conditionalDefaultNative(fixture);
    expect(report['storedOmittedLabel'], 'native');
    expect(report['indirectExportDefault'], 'native');
    expect(report['fixedWrapperControl'], 'native');
    expect(await conditionalDefaultHashes(fixture), before);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    'build_runner and CLI preserve identical conditional factory routes',
    () async {
      final fixture = await conditionalDefaultConsumer(
        Directory.current.absolute.path,
      );
      addTearDown(fixture.dispose);
      final client = await fixture.file('lib/models.orm.dart').readAsString();
      final snapshot = await fixture
          .file('lib/models.snapshot.dart')
          .readAsString();
      await fixture.write('build.yaml', r'''
targets:
  $default:
    builders:
      orm:orm:
        enabled: true
        generate_for: [lib/models.dart]
        options:
          database: sqlite
''');
      await fixture.run([
        'run',
        'build_runner',
        'build',
        '--delete-conflicting-outputs',
      ]);
      expect(await fixture.file('lib/models.orm.dart').readAsString(), client);
      expect(
        await fixture.file('lib/models.snapshot.dart').readAsString(),
        snapshot,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('prefixed public facade retains indirect conditional exports for all factory forms', () async {
    await write('native.dart', helpers);
    await write('web.dart', helpers.replaceAll('native', 'web'));
    await write(
      'choice.dart',
      "export 'native.dart' if (dart.library.js_interop) 'web.dart';",
    );
    await write(
      'facade.dart',
      "export 'choice.dart' show next, Labels, empty, alias;",
    );
    final result = await generate(
      "import 'facade.dart' as h;\n$model",
      output: 'nested/client.dart',
    );
    expect(result.dart, contains('"../facade.dart"'));
    expect(result.dart, isNot(contains('"../native.dart"')));
    final analysis = await Process.run(Platform.resolvedExecutable, [
      'analyze',
      '${root.path}/nested/client.dart',
    ]);
    expect(
      analysis.exitCode,
      0,
      reason: '${analysis.stdout}\n${analysis.stderr}',
    );
  });

  test('direct conditional imports retain condition values and unprefixed names', () async {
    await write('native.dart', helpers);
    await write('web.dart', helpers.replaceAll('native', 'web'));
    final result = await generate(
      "import 'native.dart' if (dart.library.js_interop == 'true') 'web.dart';\n${model.replaceAll('h.', '')}",
    );
    expect(
      result.dart,
      contains("if (dart.library.js_interop == 'true') \"web.dart\""),
    );
    expect(result.dart, isNot(contains('import "native.dart" as types')));
  });

  test(
    'constructor tear-offs retain a prefixed conditional public entrypoint',
    () async {
      for (final platform in ['native', 'web']) {
        await write('$platform.dart', "export 'dart:core' show DateTime;");
      }
      final result = await generate('''
import 'package:orm/schema.dart';
import 'native.dart' if (dart.library.js_interop) 'web.dart' as clock;
@Model() final class Row({@Id() required final int id, @ClientDefault(clock.DateTime.now) required final DateTime createdAt});
''');
      expect(result.dart, contains('if (dart.library.js_interop) "web.dart"'));
      await write(
        'probe.dart',
        "import 'client.dart';\nvoid main() => print(rowSchema.columns.last.clientDefault!());",
      );
      final compile = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'js',
        '${root.path}/probe.dart',
        '-o',
        '${root.path}/probe.js',
      ]);
      expect(
        compile.exitCode,
        0,
        reason: '${compile.stdout}\n${compile.stderr}',
      );
    },
  );

  for (final conditional in [false, true]) {
    test(
      'local private aliases retain ${conditional ? 'conditional' : 'plain'} public imports',
      () async {
        await write('native.dart', helpers);
        await write('web.dart', helpers.replaceAll('native', 'web'));
        final result = await generate('''
import 'package:orm/schema.dart';
import 'native.dart' ${conditional ? "if (dart.library.js_interop) 'web.dart'" : ''} as h;
typedef _First = h.Labels;
typedef _Second = _First;
@Model() final class Row({@Id() required final int id, @ClientDefault(_Second.next) required final String label});
''');
        expect(result.dart, contains('show Labels;'));
        expect(result.dart, isNot(contains('_Second.next')));
        expect(result.dart, contains('factories0.Labels.next'));
        await write(
          'probe.dart',
          "import 'client.dart';\nvoid main() => print(rowSchema.columns.last.clientDefault!());",
        );
        final run = await Process.run(Platform.resolvedExecutable, [
          'run',
          '${root.path}/probe.dart',
        ]);
        expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
        expect('${run.stdout}'.trim(), 'native');
      },
    );
  }

  test(
    'public local aliases preserve their own conditional selection',
    () async {
      await write('native.dart', helpers);
      await write('web.dart', helpers.replaceAll('native', 'web'));
      final result = await generate('''
import 'package:orm/schema.dart';
import 'native.dart' if (dart.library.js_interop) 'web.dart' as h;
typedef Labels = h.Labels;
@Model() final class Row({@Id() required final int id, @ClientDefault(Labels.next) required final String label});
''');
      expect(result.dart, contains('models.Labels.next'));
      expect(result.dart, isNot(contains('import "native.dart"')));
    },
  );

  test('constructor aliases substitute nested and reordered generic arguments', () async {
    await write(
      'native.dart',
      'class Value<T> { Value(); }\ntypedef Public<A,B> = Value<Map<A,B>>;',
    );
    await write(
      'web.dart',
      'class Value<T> { Value(); }\ntypedef Public<A,B> = Value<Map<A,B>>;',
    );
    await write('models.dart', '''
import 'package:orm/schema.dart';
import 'native.dart' if (dart.library.js_interop) 'web.dart' as h;
typedef _One<A,B> = h.Public<B,List<A>>;
typedef _Two<T> = _One<T,int>;
typedef _Implicit = h.Value;
@ClientDefault(_Implicit.new) final Object implicit = Object();
@ClientDefault(_Two<String>.new) final Object value = Object();
''');
    final path = File('${root.path}/models.dart').absolute.path;
    final contexts = AnalysisContextCollection(
      includedPaths: [root.absolute.path],
    );
    try {
      final unit =
          await contexts.contextFor(path).currentSession.getResolvedUnit(path)
              as ResolvedUnitResult;
      final annotation = unit.unit.declarations
          .whereType<TopLevelVariableDeclaration>()
          .last
          .metadata
          .single;
      final expression =
          annotation.arguments!.arguments.single.argumentExpression
              as ConstructorReference;
      final signature = expression.staticType as FunctionType;
      final names = DartNames(unit.libraryElement.uri, (uri) => uri.toString());
      final reference = names.factoryReference(
        expression,
        expression.constructorName.element as ExecutableElement,
        signature,
        annotation,
      );
      expect(reference, 'factories0.Public<int, List<String>>.new');
      final implicitAnnotation = unit.unit.declarations
          .whereType<TopLevelVariableDeclaration>()
          .first
          .metadata
          .single;
      final implicitExpression =
          implicitAnnotation.arguments!.arguments.single.argumentExpression
              as ConstructorReference;
      final implicitReference = names.factoryReference(
        implicitExpression,
        implicitExpression.constructorName.element as ExecutableElement,
        implicitExpression.staticType as FunctionType,
        implicitAnnotation,
      );
      expect(implicitReference, 'factories1.Value<dynamic>.new');
      await write(
        'probe.dart',
        '${names.factoryImports.directives.join('\n')}\nvoid main() { print($reference()); print($implicitReference()); }',
      );
      final run = await Process.run(Platform.resolvedExecutable, [
        'run',
        '${root.path}/probe.dart',
      ]);
      expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
      expect('${run.stdout}', contains('Map<int, List<String>>'));
      expect('${run.stdout}', contains('Value<dynamic>'));
      final compile = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'js',
        '${root.path}/probe.dart',
        '-o',
        '${root.path}/probe.js',
      ]);
      expect(
        compile.exitCode,
        0,
        reason: '${compile.stdout}\n${compile.stderr}',
      );
    } finally {
      await contexts.dispose();
    }
  });

  test(
    'mixin-local factories follow the actual applied import prefix',
    () async {
      const fields = '''
import 'package:orm/schema.dart';
String next() => 'native';
mixin Fields {
  @Id() int id = 0;
  @ClientDefault(next) String label = '';
}
''';
      await write('native.dart', fields);
      await write('web.dart', fields.replaceAll('native', 'web'));
      final result = await generate('''
import 'package:orm/schema.dart';
import 'native.dart' as fixed;
import 'native.dart' if (dart.library.js_interop) 'web.dart' as selected;
@Model()
final class Row with selected.Fields {
  Row({required int id, required String label}) { this.id = id; this.label = label; }
}
''');
      expect(result.dart, contains('if (dart.library.js_interop) "web.dart"'));
      expect(result.dart, isNot(contains('import "native.dart" as types')));
    },
  );

  test('a private alias in a nonconditional mixin remains usable', () async {
    await write('fields.dart', '''
import 'package:orm/schema.dart';
class Labels { static String next() => 'plain'; }
typedef _First = Labels;
typedef _Second = _First;
mixin Fields { @Id() int id = 0; @ClientDefault(_Second.next) String label = ''; }
''');
    final result = await generate('''
import 'package:orm/schema.dart';
import 'fields.dart';
@Model() final class Row with Fields {
 Row({required int id, required String label}) { this.id = id; this.label = label; }
}
''');
    expect(result.dart, contains('show Labels;'));
    expect(result.dart, contains('factories0.Labels.next'));
  });

  test(
    'different unprefixed public routes produce a located diagnostic',
    () async {
      await write('native.dart', helpers);
      await write('web.dart', helpers.replaceAll('native', 'web'));
      await expectLater(
        generate('''
import 'package:orm/schema.dart';
import 'native.dart';
import 'native.dart' if (dart.library.js_interop) 'web.dart';
@Model() final class Row({@Id() required final int id, @ClientDefault(next) required final String label});
'''),
        throwsA(
          isA<GenerationException>()
              .having((e) => e.code, 'code', 'SCHEMA.DEFAULT')
              .having(
                (e) => e.message,
                'ambiguous entrypoint',
                contains('multiple public'),
              )
              .having((e) => e.line, 'source line', greaterThan(0))
              .having((e) => e.column, 'source column', greaterThan(0)),
        ),
      );
    },
  );

  for (final direct in [false, true]) {
    test(
      'duplicate plain ${direct ? 'direct and facade' : 'facade'} imports retain the same factory',
      () async {
        await write('native.dart', helpers);
        await write('first.dart', "export 'native.dart';");
        await write('second.dart', "export 'native.dart';");
        await generate(
          "import '${direct ? 'native' : 'first'}.dart';\nimport 'second.dart';\n${model.replaceAll('h.', '')}",
        );
        await write(
          'probe.dart',
          "import 'client.dart';\nvoid main() => print(rowSchema.columns.last.clientDefault!());",
        );
        final run = await Process.run(Platform.resolvedExecutable, [
          'run',
          '${root.path}/probe.dart',
        ]);
        expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
        expect('${run.stdout}'.trim(), 'native');
      },
    );
  }

  for (final indirect in [false, true]) {
    test(
      'branch-specific ${indirect ? 'indirect' : 'direct'} external factories cannot freeze a conditional mixin',
      () async {
        await write('helpers_native.dart', helpers);
        await write('helpers_web.dart', helpers.replaceAll('native', 'web'));
        for (final platform in ['native', 'web']) {
          await write(
            'facade_$platform.dart',
            "export 'helpers_$platform.dart';",
          );
          await write('fields_$platform.dart', '''
import 'package:orm/schema.dart';
import '${indirect ? 'facade' : 'helpers'}_$platform.dart' as h;
mixin Fields { @Id() int id = 0; @ClientDefault(h.next) String label = ''; }
''');
        }
        await expectLater(
          generate('''
import 'package:orm/schema.dart';
import 'fields_native.dart' if (dart.library.js_interop) 'fields_web.dart';
@Model() final class Row with Fields {
 Row({required int id, required String label}) { this.id = id; this.label = label; }
}
'''),
          throwsA(
            isA<GenerationException>().having(
              (e) => e.code,
              'code',
              'SCHEMA.DEFAULT',
            ),
          ),
        );
      },
    );
  }

  for (final indirect in [false, true]) {
    test(
      'shared core factory through ${indirect ? 'indirect export' : 'conditional import'} remains valid',
      () async {
        const fields = '''
import 'package:orm/schema.dart';
mixin Fields { @Id() int id = 0; @ClientDefault(DateTime.now) DateTime? createdAt; }
''';
        await write('fields_native.dart', fields);
        await write('fields_web.dart', fields);
        await write(
          'facade.dart',
          "export 'fields_native.dart' if (dart.library.js_interop) 'fields_web.dart'; export 'dart:typed_data';",
        );
        await generate('''
import 'package:orm/schema.dart';
import '${indirect ? 'facade.dart' : "fields_native.dart' if (dart.library.js_interop) 'fields_web.dart"}';
@Model() final class Row with Fields {
 Row({required int id, required DateTime? createdAt}) { this.id = id; this.createdAt = createdAt; }
}
''');
        await write(
          'probe.dart',
          "import 'client.dart';\nvoid main() => print(rowSchema.columns.last.clientDefault!());",
        );
        final compile = await Process.run(Platform.resolvedExecutable, [
          'compile',
          'js',
          '${root.path}/probe.dart',
          '-o',
          '${root.path}/probe.js',
        ]);
        expect(
          compile.exitCode,
          0,
          reason: '${compile.stdout}\n${compile.stderr}',
        );
      },
    );
  }

  test('conditional factory type arguments retain their own nested public routes', () async {
    for (final platform in ['native', 'web']) {
      await write(
        'helpers_$platform.dart',
        "class ${platform == 'native' ? 'Native' : 'Web'}Tag {}\ntypedef Token = ${platform == 'native' ? 'Native' : 'Web'}Tag;\nString generic<T>() => T.toString();\n",
      );
    }
    await write(
      'facade.dart',
      "export 'helpers_native.dart' if (dart.library.js_interop) 'helpers_web.dart';",
    );
    final result = await generate('''
import 'package:orm/schema.dart';
import 'facade.dart' as h;
typedef _One<T> = Map<h.Token, List<T?>>;
typedef _Two = _One<h.Token>;
@Model() final class Row({@Id() required final int id, @ClientDefault(h.generic<_Two>) required final String label});
''');
    expect(result.dart, contains('show Token;'));
    expect(result.dart, isNot(contains('import "helpers_native.dart"')));
    expect(
      result.dart,
      contains('Map<factories0.Token, List<factories0.Token?>>'),
    );
    await write(
      'probe.dart',
      "import 'client.dart';\nvoid main() => print(rowSchema.columns.last.clientDefault!());",
    );
    final compile = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'js',
      '${root.path}/probe.dart',
      '-o',
      '${root.path}/probe.js',
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
  });

  test(
    'conditional mixin counterpart annotations match each field independently',
    () async {
      await write('native.dart', '''
import 'package:orm/schema.dart';
String next() => 'native';
mixin Fields { @Id() int id = 0; @ClientDefault(next) String first = '', second = ''; }
''');
      await write('web.dart', '''
import 'package:orm/schema.dart';
String next() => 'web';
mixin Fields { @Id() int id = 0; @ClientDefault(next) String second = ''; @ClientDefault(next) String first = ''; }
''');
      final result = await generate('''
import 'package:orm/schema.dart';
import 'native.dart' if (dart.library.js_interop) 'web.dart';
@Model() final class Row with Fields {
 Row({required int id, required String first, required String second}) { this.id = id; this.first = first; this.second = second; }
}
''');
      expect(result.dart, contains('if (dart.library.js_interop) "web.dart"'));
    },
  );

  test(
    'inactive conditional mixin packages resolve through package config',
    () async {
      final configFile = File('.dart_tool/package_config.json').absolute;
      final config =
          jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
      final packages = config['packages'] as List<dynamic>;
      for (final entry in packages.cast<Map<String, dynamic>>()) {
        entry['rootUri'] = configFile.uri
            .resolve(entry['rootUri'] as String)
            .toString();
      }
      for (final platform in ['native', 'web']) {
        await write('pkg_$platform/lib/fields.dart', '''
import 'package:orm/schema.dart';
String next() => '$platform';
mixin Fields { @Id() int id = 0; @ClientDefault(next) String label = ''; }
''');
        packages.add({
          'name': 'fields_$platform',
          'rootUri': Directory('${root.path}/pkg_$platform').absolute.uri
              .toString(),
          'packageUri': 'lib/',
          'languageVersion': '3.13',
        });
      }
      await write('.dart_tool/package_config.json', jsonEncode(config));
      final result = await generate('''
import 'package:orm/schema.dart';
import 'package:fields_native/fields.dart' if (dart.library.js_interop) 'package:fields_web/fields.dart';
@Model() final class Row with Fields {
 Row({required int id, required String label}) { this.id = id; this.label = label; }
}
''');
      expect(
        result.dart,
        contains(
          'if (dart.library.js_interop) "package:fields_web/fields.dart"',
        ),
      );
    },
  );

  test('shared external argument types retain fixed routes across different branch prefixes', () async {
    await write(
      'shared.dart',
      'class Token {}\nString make<T>() => T.toString();',
    );
    for (final platform in ['native', 'web']) {
      final prefix = platform == 'native' ? 'h' : 'longh';
      await write('fields_$platform.dart', '''
import 'package:orm/schema.dart';
import 'shared.dart' as $prefix;
mixin Fields { @Id() int id = 0; @ClientDefault($prefix.make<$prefix.Token>) String label = ''; }
''');
    }
    await generate('''
import 'package:orm/schema.dart';
import 'fields_native.dart' if (dart.library.js_interop) 'fields_web.dart';
@Model() final class Row with Fields {
 Row({required int id, required String label}) { this.id = id; this.label = label; }
}
''');
  });

  test(
    'factory and argument can select different explicit conditional prefixes',
    () async {
      await write(
        'native.dart',
        'class Token {}\nString make<T>() => T.toString();',
      );
      await write(
        'web.dart',
        'class Token {}\nString make<T>() => T.toString();',
      );
      await write(
        'other_web.dart',
        'class OtherToken {}\ntypedef Token = OtherToken;',
      );
      await write(
        'factory.dart',
        "export 'native.dart' if (dart.library.js_interop) 'web.dart';",
      );
      await write(
        'argument.dart',
        "export 'native.dart' if (dart.library.js_interop) 'other_web.dart';",
      );
      final result = await generate('''
import 'package:orm/schema.dart';
import 'factory.dart' as f;
import 'argument.dart' as t;
@Model() final class Row({@Id() required final int id, @ClientDefault(f.make<t.Token>) required final String label});
''');
      expect(
        result.dart,
        contains('"argument.dart" as factories0 show Token;'),
      );
      expect(result.dart, contains('"factory.dart" as factories1 show make;'));
      expect(result.dart, contains('factories1.make<factories0.Token>'));
      expect(result.dart, isNot(contains('import "native.dart"')));
    },
  );

  test(
    'record argument fields retain conditional public type routes',
    () async {
      await write(
        'native.dart',
        'class Token {}\nString make<T>() => T.toString();',
      );
      await write(
        'web.dart',
        'class Token {}\nString make<T>() => T.toString();',
      );
      final result = await generate('''
import 'package:orm/schema.dart';
import 'native.dart' if (dart.library.js_interop) 'web.dart' as h;
@Model() final class Row({@Id() required final int id, @ClientDefault(h.make<(h.Token, {h.Token? value})>) required final String label});
''');
      expect(
        result.dart,
        contains('(factories0.Token, {factories0.Token? value})'),
      );
      expect(result.dart, isNot(contains('import "native.dart" as types')));
      await write(
        'probe.dart',
        "import 'client.dart';\nvoid main() => print(rowSchema.columns.last.clientDefault!());",
      );
      final compile = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'js',
        '${root.path}/probe.dart',
        '-o',
        '${root.path}/probe.js',
      ]);
      expect(
        compile.exitCode,
        0,
        reason: '${compile.stdout}\n${compile.stderr}',
      );
    },
  );

  for (final conditional in [false, true]) {
    test(
      '${conditional ? 'conditional' : 'plain'} inferred private-alias bounds have an explicit route boundary',
      () async {
        const types =
            'class Token {}\nclass Box<T extends Token> {}\nString make<T>() => T.toString();';
        await write('native.dart', types);
        await write('web.dart', types);
        final source =
            '''
import 'package:orm/schema.dart';
import 'native.dart' ${conditional ? "if (dart.library.js_interop) 'web.dart'" : ''} as h;
typedef _Box = h.Box;
@Model() final class Row({@Id() required final int id, @ClientDefault(h.make<_Box>) required final String label});
''';
        if (conditional) {
          await expectLater(
            generate(source),
            throwsA(
              isA<GenerationException>()
                  .having((e) => e.code, 'code', 'SCHEMA.DEFAULT')
                  .having(
                    (e) => e.message,
                    'route',
                    contains('inferred factory type'),
                  )
                  .having((e) => e.line, 'line', greaterThan(0)),
            ),
          );
          await generate(
            source.replaceFirst(
              'typedef _Box = h.Box;',
              'typedef _Box = h.Box<h.Token>;',
            ),
          );
        } else {
          await generate(source);
        }
      },
    );
  }

  test('shared wrapper imports may use different branch prefixes', () async {
    await write('shared.dart', "String next() => 'shared';");
    for (final platform in ['native', 'web']) {
      await write('fields_$platform.dart', '''
import 'package:orm/schema.dart';
import 'shared.dart' as $platform;
mixin Fields { @Id() int id = 0; @ClientDefault($platform.next) String label = ''; }
''');
    }
    await generate('''
import 'package:orm/schema.dart';
import 'fields_native.dart' if (dart.library.js_interop) 'fields_web.dart';
@Model() final class Row with Fields {
 Row({required int id, required String label}) { this.id = id; this.label = label; }
}
''');
  });

  for (final exposed in [false, true]) {
    test(
      'conditional mixin private aliases ${exposed ? 'retain their public target' : 'diagnose an unexposed target'}',
      () async {
        for (final platform in ['native', 'web']) {
          await write(
            'helpers_$platform.dart',
            helpers.replaceAll('native', platform),
          );
          await write('fields_$platform.dart', '''
import 'package:orm/schema.dart';
import 'helpers_$platform.dart' as ${platform == 'native' ? 'n' : 'longn'};
${exposed ? "export 'helpers_$platform.dart' show Labels;" : ''}
typedef _First = ${platform == 'native' ? 'n' : 'longn'}.Labels;
typedef _Second = _First;
mixin Fields { @Id() int id = 0; @ClientDefault(_Second.next) String label = ''; }
''');
        }
        final future = generate('''
import 'package:orm/schema.dart';
import 'fields_native.dart' if (dart.library.js_interop) 'fields_web.dart';
@Model() final class Row with Fields {
 Row({required int id, required String label}) { this.id = id; this.label = label; }
}
''');
        if (exposed) {
          final result = await future;
          expect(result.dart, contains('factories0.Labels.next'));
          expect(result.dart, isNot(contains('import "helpers_native.dart"')));
          await write(
            'probe.dart',
            "import 'client.dart';\nvoid main() => print(rowSchema.columns.last.clientDefault!());",
          );
          final compile = await Process.run(Platform.resolvedExecutable, [
            'compile',
            'js',
            '${root.path}/probe.dart',
            '-o',
            '${root.path}/probe.js',
          ]);
          expect(
            compile.exitCode,
            0,
            reason: '${compile.stdout}\n${compile.stderr}',
          );
        } else {
          await expectLater(
            future,
            throwsA(
              isA<GenerationException>().having(
                (e) => e.code,
                'code',
                'SCHEMA.DEFAULT',
              ),
            ),
          );
        }
      },
    );
  }

  test('different conditional private alias targets produce a located diagnostic', () async {
    for (final platform in ['native', 'web']) {
      await write(
        'helpers_$platform.dart',
        "class Labels { static String next() => '$platform'; } class Other { static String next() => 'other'; }",
      );
      await write('fields_$platform.dart', '''
import 'package:orm/schema.dart';
import 'helpers_$platform.dart' as h;
export 'helpers_$platform.dart' show Labels, Other;
typedef _Local = h.${platform == 'native' ? 'Labels' : 'Other'};
mixin Fields { @Id() int id = 0; @ClientDefault(_Local.next) String label = ''; }
''');
    }
    await expectLater(
      generate('''
import 'package:orm/schema.dart';
import 'fields_native.dart' if (dart.library.js_interop) 'fields_web.dart';
@Model() final class Row with Fields {
 Row({required int id, required String label}) { this.id = id; this.label = label; }
}
'''),
      throwsA(
        isA<GenerationException>()
            .having((e) => e.code, 'code', 'SCHEMA.DEFAULT')
            .having(
              (e) => e.message,
              'alias mapping',
              contains('alias type arguments'),
            )
            .having((e) => e.line, 'line', greaterThan(0)),
      ),
    );
  });

  test(
    'parenthesized factories preserve the same conditional public entrypoint',
    () async {
      await write('native.dart', helpers);
      await write('web.dart', helpers.replaceAll('native', 'web'));
      await write(
        'facade.dart',
        "export 'native.dart' if (dart.library.js_interop) 'web.dart';",
      );
      final wrapped = model.replaceAllMapped(
        RegExp(r'ClientDefault\(([^)]*)\)'),
        (match) => 'ClientDefault((${match[1]}))',
      );
      final result = await generate("import 'facade.dart' as h;\n$wrapped");
      expect(result.dart, contains('"facade.dart"'));
      expect(result.dart, isNot(contains('import "native.dart"')));
      final analyze = await Process.run(Platform.resolvedExecutable, [
        'analyze',
        '${root.path}/client.dart',
      ]);
      expect(
        analyze.exitCode,
        0,
        reason: '${analyze.stdout}\n${analyze.stderr}',
      );
    },
  );

  test('factory import paths escape dollar signs', () async {
    await write(r'dollar$path/native.dart', helpers);
    await write(r'dollar$path/web.dart', helpers.replaceAll('native', 'web'));
    await generate(
      "import 'dollar\\\$path/native.dart' if (dart.library.js_interop) 'dollar\\\$path/web.dart' as h;\n$model",
    );
    final result = await Process.run(Platform.resolvedExecutable, [
      'analyze',
      '${root.path}/client.dart',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('hidden conditional mixin factory fails instead of importing its defining library', () async {
    const fields = '''
import 'package:orm/schema.dart';
String next() => 'native';
mixin Fields { @Id() int id = 0; @ClientDefault(next) String label = ''; }
''';
    await write('native.dart', fields);
    await write('web.dart', fields.replaceAll('native', 'web'));
    await expectLater(
      generate('''
import 'package:orm/schema.dart';
import 'native.dart' if (dart.library.js_interop) 'web.dart' show Fields;
@Model()
final class Row with Fields {
 Row({required int id, required String label}) { this.id = id; this.label = label; }
}
'''),
      throwsA(
        isA<GenerationException>()
            .having((e) => e.code, 'code', 'SCHEMA.DEFAULT')
            .having(
              (e) => e.message,
              'public entrypoint',
              contains('does not expose'),
            ),
      ),
    );
  });

  test('hidden factories behind an annotated conditional export cannot bypass selection', () async {
    const fields = '''
import 'package:orm/schema.dart';
String next() => 'native';
mixin Fields { @Id() int id = 0; @ClientDefault(next) String label = ''; }
''';
    await write('native.dart', fields);
    await write('web.dart', fields.replaceAll('native', 'web'));
    await write(
      'facade.dart',
      "@Deprecated('use the public factory export')\nexport 'native.dart' if (dart.library.js_interop) 'web.dart' show Fields;",
    );
    await expectLater(
      generate('''
import 'package:orm/schema.dart';
import 'facade.dart';
@Model() final class Row with Fields {
 Row({required int id, required String label}) { this.id = id; this.label = label; }
}
'''),
      throwsA(
        isA<GenerationException>()
            .having((e) => e.code, 'code', 'SCHEMA.DEFAULT')
            .having(
              (e) => e.message,
              'public entrypoint',
              contains('does not expose'),
            ),
      ),
    );
  });

  test(
    'an incompatible inactive factory is rejected by target compilation',
    () async {
      await write('native.dart', "String next() => 'native';");
      await write('web.dart', 'int next() => 1;');
      await generate('''
import 'package:orm/schema.dart';
import 'native.dart' if (dart.library.js_interop) 'web.dart' as h;
@Model() final class Row({@Id() required final int id, @ClientDefault(h.next) required final String label});
''');
      await write(
        'probe.dart',
        "import 'client.dart';\nvoid main() => print(rowSchema.columns.last.clientDefault!());",
      );
      final compile = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'js',
        '${root.path}/probe.dart',
        '-o',
        '${root.path}/probe.js',
      ]);
      expect(compile.exitCode, isNot(0));
      expect(
        '${compile.stdout}\n${compile.stderr}',
        contains("can't be assigned"),
      );
    },
  );
}
