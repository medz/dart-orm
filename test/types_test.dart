import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:test/test.dart';

void main() {
  test('computed generated fields are statically readable and never writable', () async {
    final dir = await Directory('.dart_tool/orm-computed-types')
        .create(recursive: true);
    final file = File('${dir.path}/negative.dart').absolute;
    final invalid = [
      "db.lines.create(price: 1, quantity: 1, label: '', total: 1);",
      'db.lines.byId(1).patch(total: const Change.set(1));',
      'db.lines.update((r) => [r.total.set(1)]);',
      'db.lines.update((r) => [r.total.increment(1)]);',
      'db.lines.update((r) => [r.total.defaultValue()]);',
      'db.lines.update((r) => [r.total.setExpression(r.price)]);',
      'db.lines.select((r) => r.total.eq("wrong"));',
    ];
    await file.writeAsString(
      "import 'package:orm/orm.dart';\nimport '../../test/support/computed/schema.orm.dart';\nvoid wrong(Database<Sqlite> db) {\n${invalid.join('\n')}\n}\n",
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
      expect(
        errors.any(
          (e) => e.diagnosticCode.lowerCaseName.contains('uri_does_not_exist'),
        ),
        false,
      );
      for (var i = 0; i < invalid.length; i++) {
        expect(
          errors.any(
            (e) => result.lineInfo.getLocation(e.offset).lineNumber == i + 4,
          ),
          true,
          reason: invalid[i],
        );
      }
    } finally {
      await contexts.dispose();
      await dir.delete(recursive: true);
    }
  });
  test('client-default create parameters preserve domain, nullable and timestamp types', () async {
    final directory = await Directory('.dart_tool/orm-default-type-tests')
        .create(recursive: true);
    final file = File('${directory.path}/negative.dart').absolute;
    final invalid = [
      'db.tickets.create(id: const Change.set(1));',
      'db.tickets.create(name: const Change.set(null));',
      "db.tickets.create(createdAt: const Change.set('now'));",
      "db.tickets.create(label: 'value');",
    ];
    await file.writeAsString(
      "import 'package:orm/orm.dart';\nimport '../../test/support/defaults/schema.orm.dart';\nvoid wrong(Database<Sqlite> db) {\n${invalid.join('\n')}\n}\n",
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
      expect(
        errors.any(
          (e) => e.diagnosticCode.lowerCaseName.contains('uri_does_not_exist'),
        ),
        false,
      );
      for (var i = 0; i < invalid.length; i++) {
        expect(
          errors.any(
            (e) => result.lineInfo.getLocation(e.offset).lineNumber == i + 4,
          ),
          true,
          reason: invalid[i],
        );
      }
    } finally {
      await contexts.dispose();
      await directory.delete(recursive: true);
    }
  });
  test('query-only relation APIs retain result types and expose no graph writes', () async {
    final directory = await Directory('.dart_tool/orm-relation-type-tests')
        .create(recursive: true);
    final file = File('${directory.path}/negative.dart').absolute;
    final invalid = [
      'db.entries.select((e) => e.ownerAccount.update((a) => [a.id.set(1)]));',
      'db.entries.select((e) => e.ownerAccount.delete());',
      'db.entries.select((e) => e.ownerAccount.connect(1));',
      'final Future<List<int>> values = db.entries.select((e) => e.ownerAccount.select((a) => a.id).one()).get();',
      'final Future<List<String>> rows = db.entries.select((e) => e.matchingAccounts.select((a) => a.id).many()).get();',
    ];
    await file.writeAsString(
      "import 'package:orm/orm.dart';\nimport '../../test/support/unconstrained/schema.orm.dart';\nvoid wrong(Database<Sqlite> db) {\n${invalid.join('\n')}\n}\n",
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
      expect(
        errors.any(
          (e) => e.diagnosticCode.lowerCaseName.contains('uri_does_not_exist'),
        ),
        false,
      );
      for (var i = 0; i < invalid.length; i++) {
        expect(
          errors.any(
            (e) => result.lineInfo.getLocation(e.offset).lineNumber == i + 4,
          ),
          true,
          reason: invalid[i],
        );
      }
    } finally {
      await contexts.dispose();
      await directory.delete(recursive: true);
    }
  });

  test('calendar APIs reject instants, strings and mixed temporal types', () async {
    final directory = await Directory('.dart_tool/orm-temporal-type-tests')
        .create(recursive: true);
    final file = File('${directory.path}/negative.dart').absolute;
    final invalid = [
      "db.appointments.create(day: DateTime.utc(2024));",
      "db.appointments.byId(1).patch(starts: const Change.set('2024-01-01'));",
      "db.appointments.where((a) => a.time.eq(LocalDate(2024, 1, 1)));",
      "db.appointments.where((a) => a.day.eq('2024-01-01'));",
      "db.appointments.select((a) => a.day).union(db.appointments.select((a) => a.time));",
    ];
    await file.writeAsString(
      "import 'package:orm/orm.dart';\nimport '../../test/support/temporals/schema.orm.dart';\nvoid wrong(Database<Sqlite> db) {\n${invalid.join('\n')}\n}\n",
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
      expect(
        errors.any(
          (e) => e.diagnosticCode.lowerCaseName.contains('uri_does_not_exist'),
        ),
        false,
      );
      for (var i = 0; i < invalid.length; i++) {
        expect(
          errors.any(
            (e) => result.lineInfo.getLocation(e.offset).lineNumber == i + 4,
          ),
          true,
          reason: invalid[i],
        );
      }
    } finally {
      await contexts.dispose();
      await directory.delete(recursive: true);
    }
  });

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
