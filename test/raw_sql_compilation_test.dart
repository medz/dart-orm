@Tags(['core'])
library;

import 'dart:typed_data';

import 'package:orm/sql.dart';
import 'package:test/test.dart';

void main() {
  test(
    'template preserves quotes/comments and binds each protocol correctly',
    () {
      for (final dialect in SqlDialect.values) {
        final template = Sql(
          "SELECT :input AS n, ':ignored;''text' AS s, \"quoted:field\" -- :line\n"
          '/* :comment */ FROM data WHERE n = :input; -- trailing',
          parameters: {'input': SqlValue(3, Codecs.integer)},
        );
        final command = template.compile(
          Capabilities(dialect: dialect, maxParameters: 2),
        );
        expect(
          command.parameters,
          dialect == SqlDialect.mysql || dialect == SqlDialect.mariadb
              ? [3, 3]
              : [3],
        );
        expect(command.sql, contains("':ignored;''text'"));
        expect(command.sql, endsWith(' -- trailing'));
      }
      final pg = Sql(
        r'''SELECT :n::bigint, $tag$:ignored; '$tag$, E'\:ignored', payload ? 'key' /* nested /* :ignored */ end */''',
        parameters: {'n': 3},
      );
      expect(
        pg.compile(SqlBuilder(SqlDialect.postgres).capabilities).parameters,
        [3],
      );
      final sqlite = Sql(
        'SELECT :n, [name:ignored], `name:ignored`',
        parameters: {'n': 3},
      );
      expect(
        sqlite.compile(SqlBuilder(SqlDialect.sqlite).capabilities).parameters,
        [3],
      );
    },
  );

  test(
    'templates reject ambiguous bindings and incomplete or multiple statements',
    () {
      for (final dialect in SqlDialect.values) {
        for (final sql in [
          "SELECT 'unfinished",
          'SELECT 1 /* incomplete',
          'SELECT 1; SELECT 2',
          r'SELECT $1',
          '-- only a comment',
        ]) {
          expect(
            () => Sql(sql).compile(SqlBuilder(dialect).capabilities),
            throwsA(isA<OrmException>()),
            reason: sql,
          );
        }
        final caps = Capabilities(dialect: dialect, maxParameters: 0);
        expect(
          () => Sql('SELECT :n').compile(caps),
          throwsA(isA<OrmException>()),
        );
        expect(
          () => Sql('SELECT :n', parameters: {'n': 1}).compile(caps),
          throwsA(isA<OrmException>()),
        );
        expect(
          () => Sql(
            'SELECT :n',
            parameters: {'n': value(1, Codecs.integer).plus(2)},
          ),
          throwsArgumentError,
        );
      }
      for (final sql in ['SELECT ?1', 'SELECT @name']) {
        expect(
          () => Sql(sql).compile(SqlBuilder(SqlDialect.sqlite).capabilities),
          throwsA(isA<OrmException>()),
        );
      }
      expect(
        () =>
            Sql(r"SELECT '\'")
                .compile(SqlBuilder(SqlDialect.postgres).capabilities),
        throwsA(isA<OrmException>()),
      );
      expect(
        () =>
            Sql(r'SELECT $$unfinished')
                .compile(SqlBuilder(SqlDialect.postgres).capabilities),
        throwsA(isA<OrmException>()),
      );
    },
  );
  test(
    'composed statements reject early terminators and split quoted text',
    () {
      for (final dialect in SqlDialect.values) {
        final caps = SqlBuilder(dialect).capabilities;
        for (final parts in [
          ['SELECT 1;', 'SELECT 2'],
          ['SELECT 1;', 'UNION ALL SELECT 2'],
          ["SELECT '", "unsafe'"],
          ['SELECT 1 /*', '*/'],
        ]) {
          expect(
            () => Sql.parts(parts).compile(caps),
            throwsA(isA<OrmException>()),
          );
        }
        expect(
          Sql.parts(['SELECT', Sql.value(7), '-- final comment'])
              .compile(caps)
              .parameters,
          [7],
        );
        expect(
          Sql(
            'UPDATE data SET n = :n;',
            parameters: {'n': 1},
          ).compile(caps).sql,
          startsWith('UPDATE'),
        );
        expect(() => Sql('\u0001').compile(caps), throwsA(isA<OrmException>()));
      }
      for (final dialect in [SqlDialect.mysql, SqlDialect.mariadb]) {
        for (final text in [
          r"SELECT '\'",
          'SELECT 1 /*! + :hidden */',
          'SELECT 1 /*M! + 1 */',
        ]) {
          expect(
            () => Sql(text).compile(SqlBuilder(dialect).capabilities),
            throwsA(isA<OrmException>()),
          );
        }
      }
    },
  );

  test('values snapshot bytes and JSON and encode custom values only once', () {
    final bytes = Uint8List.fromList([1, 2]);
    final json = <String, Object?>{
      'a': [1],
    };
    var calls = 0;
    final codec = Codec<Uint8List>('blob', (v) => v as Uint8List, (v) {
      calls++;
      return v;
    });
    final query = Sql(
      'SELECT :a, :b',
      parameters: {
        'a': SqlValue(bytes, codec),
        'b': SqlValue(json, Codecs.json),
      },
    );
    bytes[0] = 9;
    (json['a'] as List).add(2);
    for (final dialect in SqlDialect.values) {
      final command = query.compile(SqlBuilder(dialect).capabilities);
      expect(command.parameters.first, [1, 2]);
      expect(command.parameters.last, '{"a":[1]}');
      expect(
        () => (command.parameters.first as Uint8List)[0] = 8,
        throwsUnsupportedError,
      );
    }
    expect(calls, 1);
    expect(() => Sql.value({'a': 1}), throwsArgumentError);
  });

  test('result compositions reject conflicting codecs and support six typed values', () {
    final a = ResultColumn('a', Codecs.integer);
    expect(
      () => (a, ResultColumn('a', Codecs.text)).map((a, b) => (a, b)),
      throwsA(isA<OrmException>()),
    );
    expect(
      () => (a, a.nullable()).map((a, b) => (a, b)),
      throwsA(isA<OrmException>()),
    );
    final repeated = (a, a).map((a, b) => a + b);
    expect(repeated.bind(['a'])([2]), 4);
    final shape = (
      a,
      a,
      a,
      a,
      a,
      a,
    ).map((a, b, c, d, e, f) => (a, b, c, d, e, f));
    final (int, int, int, int, int, int) row = shape.bind(['a'])([3]);
    expect(row, (3, 3, 3, 3, 3, 3));
    expect(() => a.bind(['a', 'a']), throwsA(isA<OrmException>()));
    expect(() => Sql.identifier(''), throwsArgumentError);
    expect(() => Sql.identifier('a\u0000b'), throwsArgumentError);
  });
}
