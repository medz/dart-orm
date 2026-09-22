@Tags(['core'])
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:test/test.dart';

void main() {
  test(
    'groups accept only predicates and replace binary composition aliases',
    () async {
      final directory = await Directory('.dart_tool/orm-predicate-types')
          .create(recursive: true);
      final file = File('${directory.path}/consumer.dart').absolute;
      final invalid = [
        'allOf([u.id]);',
        'anyOf([true]);',
        'u.id.eq(.value(1)).and(u.id.eq(.value(2)));',
        'u.id.eq(.value(1)).or(u.id.eq(.value(2)));',
      ];
      await file.writeAsString('''
import 'package:orm/sql.dart';
import '../../test/support/tables.dart';
Expr<bool?> valid(UserFields u) => allOf([anyOf([u.id.eq(.value(1))]).not()]);
void invalid(UserFields u) {
${invalid.join('\n')}
}
''');
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
              (e) => result.lineInfo.getLocation(e.offset).lineNumber == i + 5,
            ),
            true,
            reason: invalid[i],
          );
        }
      } finally {
        await contexts.dispose();
        await directory.delete(recursive: true);
      }
    },
  );
}
