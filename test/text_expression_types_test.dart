@Tags(['core'])
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:test/test.dart';

void main() {
  test(
    'text operations retain nullability and reject non-text and null patterns',
    () async {
      final directory = await Directory('.dart_tool')
          .createTemp('orm-text-types-');
      final file = File('${directory.path}/types.dart').absolute;
      final valid = [
        'Expr<String> a = text.lower();',
        'Expr<String> b = text.upper();',
        'Expr<String?> c = nullable.lower();',
        'Expr<String?> d = nullable.upper();',
        "Expr<bool?> e = nullable.like('%');",
        "Expr<bool?> f = nullable.contains('%');",
        "Expr<bool?> g = nullable.startsWith('_');",
        "Expr<bool?> h = nullable.endsWith('!');",
      ];
      final invalid = [
        "number.like('%');",
        "number.contains('1');",
        "number.startsWith('1');",
        "number.endsWith('1');",
        'nullable.like(null);',
        'nullable.contains(null);',
        'nullable.startsWith(null);',
        'nullable.endsWith(null);',
        'Expr<String> i = nullable.lower();',
        'Expr<String> j = nullable.upper();',
      ];
      await file.writeAsString(
        "import 'package:orm/orm.dart';\n"
        'void check(Expr<int> number, Expr<String> text, Expr<String?> nullable) {\n'
        '${[...valid, ...invalid].join('\n')}\n}\n',
      );
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
        for (var index = 0; index < valid.length; index++) {
          expect(
            errors.where(
              (e) =>
                  result.lineInfo.getLocation(e.offset).lineNumber == index + 3,
            ),
            isEmpty,
            reason: valid[index],
          );
        }
        expect(errors, hasLength(invalid.length));
        for (var index = 0; index < invalid.length; index++) {
          expect(
            errors.any(
              (e) =>
                  result.lineInfo.getLocation(e.offset).lineNumber ==
                  index + valid.length + 3,
            ),
            isTrue,
            reason: invalid[index],
          );
        }
      } finally {
        await contexts.dispose();
        await directory.delete(recursive: true);
      }
    },
  );
}
