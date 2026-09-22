@Tags(['core'])
library;

import 'package:orm/sql.dart';
import 'package:test/test.dart' hide allOf, anyOf;

import 'support/tables.dart';

void main() {
  for (final dialect in SqlDialect.values) {
    group(dialect.name, () {
      final builder = SqlBuilder(dialect);
      test('groups bind values in order and retain explicit parentheses', () {
        final command = builder
            .table(users)
            .where(
              (u) => allOf([
                anyOf([u.id.eq(.value(1)), u.email.eq(.value("' OR 1=1 --"))]),
                u.score.gte(.value(10)),
              ]),
            )
            .select((u) => u.id)
            .compile();
        expect(command.parameters, [1, "' OR 1=1 --", 10]);
        expect(command.sql, contains(' OR '));
        expect(command.sql, contains(') AND '));
        expect(command.sql, isNot(contains("' OR 1=1 --")));
      });
      test('empty groups bind booleans instead of producing invalid SQL', () {
        expect(
          builder.table(users).where((_) => allOf([])).compile().parameters,
          [dialect == SqlDialect.sqlite ? 1 : true],
        );
        expect(
          builder.table(users).where((_) => anyOf([])).compile().parameters,
          [dialect == SqlDialect.sqlite ? 0 : false],
        );
      });
      test(
        'group construction consumes lazy input once and freezes its members',
        () {
          var visited = 0;
          final values = [1, 2];
          final query = builder
              .table(users)
              .where(
                (u) => anyOf(
                  values.map((id) {
                    visited++;
                    return u.id.eq(.value(id));
                  }),
                ),
              );
          expect(visited, 2);
          values.add(3);
          expect(query.compile().parameters, [1, 2]);
          expect(query.compile().parameters, [1, 2]);
          expect(visited, 2);
        },
      );
      test('groups preserve scope, aggregate and window validation', () {
        final foreign = users.alias().fields;
        expect(
          () => builder
              .table(users)
              .where(
                (u) => allOf([u.id.eq(.value(1)), foreign.id.eq(.value(2))]),
              )
              .compile(),
          throwsA(
            isA<OrmException>().having((e) => e.code, 'code', 'QUERY.SCOPE'),
          ),
        );
        expect(
          () => builder
              .table(users)
              .where(
                (u) => anyOf([u.id.eq(.value(1)), u.id.count().gt(.value(0))]),
              )
              .compile(),
          throwsA(
            isA<OrmException>().having(
              (e) => e.code,
              'code',
              'QUERY.AGGREGATE',
            ),
          ),
        );
      });
    });
  }
}
