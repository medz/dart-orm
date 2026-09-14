import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:test/test.dart';

void main() {
  test(
    'actual generated APIs reject wrong inputs, results and backend options',
    () async {
      final directory = await Directory('.dart_tool/orm-type-tests')
          .create(recursive: true);
      final file = File('${directory.path}/negative.dart').absolute;
      await file.writeAsString('''
import 'package:orm/orm.dart';
import '../../example/schema.orm.dart';
import '../../test/support/codecs/schema.orm.dart';
import '../../test/support/codecs/types.dart';
void wrong(Database<Sqlite> db) {
  db.users.create(email: 1);
  db.users.byId('wrong');
  db.users.byId(1).patch(email: const Change<String>.set(null));
  db.users.select((u) => u.email.eq(1));
  db.transaction((tx) async {}, options: const PostgresTransaction());
  final Query<int, UsersFields> bad = db.users.select((u) => u.email);
  db.users.seekAfter((u) => [u.id.cursor('wrong')]);
  print(bad);
  db.people.byId(1);
  db.people.byId(const PersonId(1)).patch(email: const Change.set('wrong'));
  db.people.byId(const PersonId(1)).patch(membership: const Change.set('active'));
  db.people.select((p) => p.id.eq(1));
  db.people.select((p) => p.email.eq('wrong'));
  db.people.byId(const PersonId(1)).patch(tags: const Change.set([1]));
  db.people.byId(const PersonId(1)).patch(details: const Change.set('raw-json'));
  final Stream<List<int>> wrongWatch = db.users.select((u) => u.email).watch();
  db.users.watch(reads: ['users']);
  print(wrongWatch);
  db.users.select((u) => u.id).union(db.users.select((u) => u.email));
  db.users.select((u) => (u.id, u.email).row).union(db.users.select((u) => (u.email, u.id).row));
  final Future<List<(String, int)>> wrongUnion = db.users.select((u) => (u.id, u.email).row).union(db.users.select((u) => (u.id, u.email).row)).get();
  print(wrongUnion);
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
        expect(errors.length, greaterThanOrEqualTo(19));
        expect(
          errors.every(
            (e) =>
                !e.diagnosticCode.lowerCaseName.contains('uri_does_not_exist'),
          ),
          true,
          reason: errors.join('\n'),
        );
        for (final line in [
          6,
          7,
          8,
          9,
          10,
          11,
          12,
          14,
          15,
          16,
          17,
          18,
          19,
          20,
          21,
          22,
          24,
          25,
          26,
        ]) {
          expect(
            errors.any(
              (e) => result.lineInfo.getLocation(e.offset).lineNumber == line,
            ),
            true,
            reason: 'Expected a type error on line $line: ${errors.join('\n')}',
          );
        }
      } finally {
        await contexts.dispose();
        await directory.delete(recursive: true);
      }
    },
  );
}
