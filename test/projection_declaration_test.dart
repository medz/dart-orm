@Tags(['core'])
library;

import 'dart:io';

import 'package:orm/generate.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory('.dart_tool')
        .createTemp('projection-declarations-');
  });
  tearDownAll(() => directory.delete(recursive: true));

  for (final entry in _invalid.entries) {
    test('rejects ${entry.key} at the projection declaration', () async {
      final (declaration, code, message) = entry.value;
      final source = File('${directory.path}/${entry.key}.dart');
      await source.writeAsString(
        "import 'package:orm/schema.dart';\n$declaration\n",
      );
      await expectLater(
        generateSchema(source.path),
        throwsA(
          isA<GenerationException>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.message, 'message', contains(message))
              .having(
                (e) => e.source?.path,
                'source',
                endsWith('/${entry.key}.dart'),
              )
              .having((e) => e.line, 'line', greaterThanOrEqualTo(2))
              .having((e) => e.column, 'column', greaterThan(0)),
        ),
      );
    });
  }
}

const _invalid = <String, (String, String, String)>{
  'model_collision': (
    "@Model(table: 'users') final class User({required final int id});\n"
        '@Projection() final class UserPatch({required final int id});',
    'SCHEMA.NAME',
    'UserPatch is ambiguous',
  ),
  'projection_collision': (
    '@Projection() final class Card({required final int id});\n'
        '@Projection() final class CardFields({required final int id});',
    'SCHEMA.NAME',
    'CardFields is ambiguous',
  ),
  'generic': (
    '@Projection() final class Card<T>({required final T id});',
    'SCHEMA.PROJECTION',
    'must be nongeneric',
  ),
  'positional_record': (
    '@Projection() typedef Card = (int, String);',
    'SCHEMA.PROJECTION',
    'nonnullable named record',
  ),
  'abstract_constructor': (
    '@Projection() abstract class Card { Card({required int id}); int get id; }',
    'SCHEMA.PROJECTION',
    'unnamed factory constructor',
  ),
  'positional_constructor': (
    '@Projection() final class Card { const Card(this.id); final int id; }',
    'SCHEMA.PROJECTION',
    'constructor with named parameters',
  ),
  'physical_annotation': (
    '@Projection() final class Card({@Id() required final int id});',
    'SCHEMA.ANNOTATION',
    'does not declare physical storage',
  ),
  'dynamic_field': (
    '@Projection() final class Card({required final dynamic id});',
    'SCHEMA.PROJECTION',
    'explicit concrete value type',
  ),
  'reserved_field': (
    '@Projection() final class Card({required final String table});',
    'SCHEMA.PROJECTION',
    'conflicts with the derived fields API',
  ),
};
