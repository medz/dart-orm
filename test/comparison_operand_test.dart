@Tags(['core'])
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:orm/sql.dart';
import 'package:test/test.dart' hide allOf, anyOf;

import 'support/codecs/schema.orm.dart';
import 'support/codecs/types.dart';
import 'support/tables.dart';

void main() {
  test(
    'comparison operands retain value, field, nullable and domain types',
    () async {
      final directory = await Directory('.dart_tool/orm-operand-types')
          .create(recursive: true);
      final file = File('${directory.path}/consumer.dart').absolute;
      final invalid = [
        for (final method in ['eq', 'ne', 'gt', 'gte', 'lt', 'lte']) ...[
          'u.id.$method(1);',
          "u.id.$method(.value('wrong'));",
          'u.id.$method(u.email);',
          'u.id.$method(nullableInt);',
          'u.id.$method(.value(null));',
        ],
        'u.id.equals(u.score);',
        "p.email.eq(.value('wrong'));",
        'p.email.eq(u.email);',
        'p.id.eq(u.id);',
        'p.email.eq(p.alternate);',
      ];
      final valid = '''
import 'package:orm/sql.dart';
import '../../test/support/tables.dart';
import '../../test/support/codecs/schema.orm.dart';
import '../../test/support/codecs/types.dart';
void valid(UserFields u, PersonFields p, Expr<int?> nullableInt) {
  const Operand<int> minimum = .value(1);
  final Operand<int> field = u.id;
  u.id.eq(minimum);
  u.id.ne(field);
  u.id.gt(u.score);
  u.id.gte(.value(2));
  u.id.lt(u.score);
  u.id.lte(.value(2));
  nullableInt.eq(.value(null));
  nullableInt.ne(.value(null));
  nullableInt.gt(.value(null));
  nullableInt.gte(u.id);
  nullableInt.lt(nullableInt);
  nullableInt.lte(.value(2));
  p.id.eq(.value(const PersonId(1)));
  p.email.eq(.value(const Email('a@example.com')));
  p.email.eq(p.email);
  p.previousMembership.eq(p.membership);
  p.membership.gt(.value(Membership.pending));
}
void invalid(UserFields u, PersonFields p, Expr<int?> nullableInt) {
''';
      await file.writeAsString('$valid${invalid.join('\n')}\n}\n');
      final firstInvalidLine = '\n'.allMatches(valid).length + 1;
      final contexts = AnalysisContextCollection(includedPaths: [file.path]);
      try {
        final result =
            await contexts
                    .contextFor(file.path)
                    .currentSession
                    .getResolvedUnit(file.path)
                as ResolvedUnitResult;
        final errors = result.diagnostics
            .where((e) => e.severity.name.toLowerCase() == 'error')
            .toList();
        expect(errors, hasLength(invalid.length));
        for (var i = 0; i < invalid.length; i++) {
          expect(
            errors.any(
              (e) =>
                  result.lineInfo.getLocation(e.offset).lineNumber ==
                  firstInvalidLine + i,
            ),
            isTrue,
            reason: invalid[i],
          );
        }
      } finally {
        await contexts.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  for (final dialect in SqlDialect.values) {
    final builder = SqlBuilder(dialect);
    test(
      '${dialect.name} literal operands use the receiving domain and enum codecs',
      () {
        const email = Operand.value(Email('a@example.com'));
        final query = builder
            .table(personTable)
            .where(
              (p) => allOf([
                p.id.eq(.value(const PersonId(42))),
                p.email.eq(email),
                p.membership.ne(.value(Membership.pending)),
                p.previousMembership.eq(.value(null)),
              ]),
            );
        final command = query.compile();
        expect(command.parameters, [42, 'a@example.com', 'pending-payment']);
        expect(command.sql, contains('IS NULL'));
        expect(command.sql, isNot(contains('a@example.com')));
        expect(
          () => builder
              .table(personTable)
              .where((p) => p.email.eq(.value(const Email('invalid')))),
          throwsFormatException,
        );
      },
    );

    test(
      '${dialect.name} field operands bind no values and preserve scope checks',
      () {
        final command = builder
            .table(users)
            .select(
              (u) => (
                u.score.eq(u.id),
                u.score.ne(u.id),
                u.score.gt(u.id),
                u.score.gte(u.id),
                u.score.lt(u.id),
                u.score.lte(u.id),
              ).row,
            )
            .compile();
        expect(command.parameters, isEmpty);
        final foreign = users.alias();
        expect(
          () => builder
              .table(users)
              .where((u) => u.score.gt(foreign.fields.score))
              .compile(),
          throwsA(
            isA<OrmException>().having((e) => e.code, 'code', 'QUERY.SCOPE'),
          ),
        );
      },
    );

    test('${dialect.name} null literals differ from null SQL expressions', () {
      final command = builder
          .table(users)
          .select(
            (u) => (
              u.nickname.eq(.value(null)),
              u.nickname.ne(.value(null)),
              u.nickname.eq(value(null, Codecs.text.nullable())),
              u.nickname.ne(value(null, Codecs.text.nullable())),
              u.nickname.gt(.value(null)),
            ).row,
          )
          .compile();
      expect(command.parameters, [null, null, null]);
      expect('IS NULL'.allMatches(command.sql), hasLength(1));
      expect('IS NOT NULL'.allMatches(command.sql), hasLength(1));
    });
  }
}
