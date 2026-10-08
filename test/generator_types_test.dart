import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('generated field signatures accept complete workflows and reject invalid Dart calls', () async {
    final directory = await Directory('test').createTemp('.generator-types-');
    final file = File('${directory.path}/usage.dart');
    final databaseImport = p.relative(
      p.absolute('example/models.db.dart'),
      from: p.absolute(directory.path),
    );
    final modelImport = p.relative(
      p.absolute('example/models.dart'),
      from: p.absolute(directory.path),
    );
    final collection = AnalysisContextCollection(
      includedPaths: [file.absolute.path],
      sdkPath: p.dirname(p.dirname(Platform.resolvedExecutable)),
    );
    try {
      await file.writeAsString('''
import '$databaseImport';
import '$modelImport';
import 'package:orm/query.dart';
Future<void> valid(AppDatabase db) async {
  User user = await db.users.create(username: 'seven', age: 28, nickname: null);
  User? updated = await db.users.update(user.id, nickname: null);
  updated = await db.users.update(user.id, age: 29);
  User? row = await db.users.get(user.id);
  List<UserCard> cards = await db.users.where(username: startsWith('sev'), age: gte(18)).orderBy(id: asc).limit(20).select<UserCard>();
  String username = cards.first.username;
  int id = cards.first.id;
  Product? product = await db.products.where(stock: gte(2)).decrement(1, stock: 2);
  List<User> streamed = await db.transaction((session) => session.users.stream(fetchSize: 2).toList());
  print([updated, row, username, id, product, streamed]);
}
void main() {}
''');
      final valid = await collection
          .contextFor(file.absolute.path)
          .currentSession
          .getResolvedUnit(file.absolute.path);
      expect(valid, isA<ResolvedUnitResult>());
      expect((valid as ResolvedUnitResult).diagnostics, isEmpty);
      final validCompilation = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'kernel',
        file.path,
        '--output',
        '${directory.path}/usage.dill',
      ]);
      expect(
        validCompilation.exitCode,
        0,
        reason: '${validCompilation.stdout}\n${validCompilation.stderr}',
      );
      await file.writeAsString('''
import '$databaseImport';
import 'package:orm/query.dart';
void invalid(AppDatabase db) {
  db.users.create(age: 2);
  db.users.create(username: null, age: 2);
  db.users.create(username: 'x', age: 'old');
  db.users.update(1, username: null);
  db.users.update(1, missing: true);
  db.users.where(age: startsWith('x'));
  db.users.where(username: eq(12));
  db.users.get('1');
  db.products.decrement(1, stock: null);
  db.orders.increment(1, userId: 1);
  db.users.create(username: 'x', age: 1, avatar: [1, 2]);
}
void main() {}
''');
      collection.contextFor(file.absolute.path).changeFile(file.absolute.path);
      await collection.contextFor(file.absolute.path).applyPendingFileChanges();
      final invalid =
          await collection
                  .contextFor(file.absolute.path)
                  .currentSession
                  .getResolvedUnit(file.absolute.path)
              as ResolvedUnitResult;
      final errors = invalid.diagnostics
          .where((diagnostic) => diagnostic.severity.name == 'error')
          .toList();
      expect(errors, hasLength(11), reason: errors.join('\n'));
      final codes = errors
          .map((diagnostic) => diagnostic.diagnosticCode.lowerCaseName)
          .toSet();
      expect(
        codes,
        containsAll([
          'argument_type_not_assignable',
          'undefined_named_parameter',
          'missing_required_argument',
        ]),
      );
      final invalidCompilation = await Process.run(
        Platform.resolvedExecutable,
        [
          'compile',
          'kernel',
          file.path,
          '--output',
          '${directory.path}/invalid.dill',
        ],
      );
      expect(invalidCompilation.exitCode, isNot(0));
      expect(invalidCompilation.stderr.toString(), contains('Error:'));
    } finally {
      await collection.dispose();
      await directory.delete(recursive: true);
    }
  });
}
