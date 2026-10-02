@Tags(['core'])
library;

import 'dart:io';

import 'package:orm/driver.dart' show SqlDialect;
import 'package:orm/generate.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  setUp(
    () async =>
        root = await Directory('.dart_tool').createTemp('model-metadata-'),
  );
  tearDown(() => root.delete(recursive: true));
  Future<GeneratedSchema> generate(String source) async {
    final file = File('${root.path}/models.dart');
    await file.writeAsString(
      "import 'package:orm/schema.dart';\nimport 'package:orm/values.dart';\n$source",
    );
    return generateSchema(file.path);
  }

  test('enum labels and database constants share an encoding', () async {
    final result = await generate('''
enum Status { waiting, done }
@Model(table: 'jobs')
final class Job({@Id(generated:true) required final int id,
 @Column(labels:{Status.waiting:'pending',Status.done:'complete'})
 @DatabaseDefault(Status.waiting) required final Status status});
''');
    expect(result.dart, contains('models.Status.waiting: "pending"'));
    expect(result.snapshot.tables.single.columns.last.defaultSql, "'pending'");
  });

  test(
    'explicit NULL database defaults suppress constructor fallbacks',
    () async {
      for (final dialect in SqlDialect.values) {
        final file = File('${root.path}/models.dart');
        await file.writeAsString('''
import 'package:orm/schema.dart';
@Model() final class User({
  @Id(generated: true) required final int id,
  @DatabaseDefault(null) final int? score = 7,
  @DatabaseDefault.sql('NULL') final String? note = 'constructor',
});
''');
        final result = await generateSchema(file.path, dialect: dialect);
        expect(
          result.snapshot.tables.single.columns
              .skip(1)
              .map((c) => c.defaultSql),
          ['NULL', 'NULL'],
        );
        expect(result.dart, isNot(contains('clientDefault:')));
        expect(result.snapshotDart, isNot(contains('constructor')));
      }
      await expectLater(
        generate('''
@Model() final class User({@DatabaseDefault(null) final int score = 7});
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

  test(
    'source methods and imported constants survive normal generation',
    () async {
      await File('${root.path}/constants.dart')
          .writeAsString("const label = \"O'Brien\";");
      final result = await generate('''
import 'constants.dart';
@Model(table:'people')
final class Person({@Id(generated:true) required final int id, final String name = label}) {
 String greet() => name.toUpperCase();
}
''');
      expect(result.dart, contains('Table<models.Person, PersonFields>'));
      expect(result.dart, isNot(contains('final class Person(')));
      expect(result.snapshot.tables.single.columns.last.defaultSql, isNull);
    },
  );

  test('misplaced and contradictory metadata fail at its source', () async {
    for (final source in [
      '@Model() @Id() final class User({required final int id});',
      'class Base { Base(); } @Model() class User extends Base { final int id; User({required this.id}); }',
      '@Model() class User { int id; User({required this.id}) { id += 1; } }',
      '@Model() class User { final int id; User({required this.id}); User.named({@Id() required this.id}); }',
      '@Model() class User({required final int id}) { void f(@Id() int other) {} }',
      "@Model() final class User({@Index(['id'],name:'idx') required final int id});",
      '@Model() final class User({required final int value, @Ignore() @Id() final int id=0});',
      "@Model(table:'') final class User({required final int id});",
      "@Model() final class User({@Column(name:'') required final int id});",
    ]) {
      await expectLater(
        generate(source),
        throwsA(
          isA<GenerationException>().having(
            (e) => e.line,
            'source line',
            isNotNull,
          ),
        ),
      );
    }
  });

  test('extension constants preserve their static DTO identity', () async {
    final result = await generate('''
extension type const UserId(int value) {}
UserId decodeId(Object? value) => UserId(value as int);
int encodeId(UserId value) => value.value;
const idCodec = Codec<UserId>.integer(decodeId, encodeId);
const publicId = UserId(2);
@Model()
final class User({
 @Id() @Column(codec: idCodec) final UserId id = const UserId(1),
 @Column(codec: idCodec) final UserId other = publicId,
});
''');
    expect(result.dart, contains('const models.UserId(1)'));
    expect(result.dart, contains('models.publicId'));
    final output = File('${root.path}/models.orm.dart');
    await output.writeAsString(result.dart);
    final analysis = await Process.run(Platform.resolvedExecutable, [
      'analyze',
      output.path,
    ]);
    expect(
      analysis.exitCode,
      0,
      reason: '${analysis.stdout}\n${analysis.stderr}',
    );
  });

  test(
    'existing generated imports cannot hide a first-generation cycle',
    () async {
      await File('${root.path}/previous.orm.dart')
          .writeAsString('const unrelated=1;');
      await expectLater(
        generate('''
import 'previous.orm.dart';
@Model() final class User({required final int id});
'''),
        throwsA(
          isA<GenerationException>().having(
            (error) => error.code,
            'code',
            'SCHEMA.DEPENDENCY',
          ),
        ),
      );
    },
  );

  test(
    'business method parameter names cannot replace constructor defaults',
    () async {
      final generated = await generate('''
@Model() class User {
  final int id;
  int business({int id=99}) => id;
  const User({this.id=7});
}
''');
      expect(generated.dart, contains('clientDefault: () => 7'));
      expect(generated.dart, isNot(contains('() => 99')));
    },
  );

  test('database constants never bypass an application codec', () async {
    await expectLater(
      generate('''
int decodeCount(Object? value) => int.parse((value as String).substring(1));
String encodeCount(int value) => 'n\$value';
const countCodec = Codec<int>.text(decodeCount, encodeCount);
@Model() final class User({@Column(codec: countCodec) @DatabaseDefault(7) required final int count});
'''),
      throwsA(
        isA<GenerationException>().having(
          (error) => error.code,
          'code',
          'SCHEMA.DEFAULT',
        ),
      ),
    );
  });

  test('computed defaults and invalid enum encodings fail before writing', () async {
    for (final source in [
      "@Model() final class User({@Computed('1') final int id = 1});",
      "enum Status { a,b } @Model() final class User({@Column(labels:{Status.a:'a'}) required final Status status});",
      "enum Status { a,b } @Model() final class User({@Column(labels:{Status.a:'same',Status.b:'same'}) required final Status status});",
      "@Model() final class User({@Column(labels:{}) required final int id});",
    ]) {
      await expectLater(generate(source), throwsA(isA<GenerationException>()));
    }
  });
}
