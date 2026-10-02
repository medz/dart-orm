@Tags(['core'])
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:test/test.dart';

void main() {
  test('read results, typed patches and flat named projections enforce their boundaries', () async {
    final directory = await Directory('.dart_tool')
        .createTemp('model-query-types-');
    final file = File('${directory.path}/consumer.dart');
    final generated = File('test/support/api_shape/models.orm.dart')
        .absolute
        .uri;
    final valid = [
      'db.user.where((u) => u.id.eq(.value(1))).update(userPatch(name: "Ada"));',
      'db.user.plan.insert(userInsert(email: "a", name: "Ada")).prepare().compile();',
      'final Future<int> changed = db.user.byId(1).patch(nickname: null);',
      'final Future<int> updated = db.user.byId(1).update(userPatch(name: "Ada"));',
      'final Future<int> deleted = db.user.byId(1).delete();',
      'final Future<int> inserted = db.user.insert(userInsert(email: "a", name: "Ada"));',
      'final Future<int> batched = db.user.insertMany([userInsert(email: "a", name: "Ada")]);',
      'final Write<User, UserFields> plan = db.user.byId(1).plan.update(userPatch(name: "Ada"));',
      'final Future<int> Function({String? nickname}) clear = db.user.byId(1).patch.call;',
      'db.user.select((u) => userCard.sql(id: u.id, name: u.name)).asCte("people").where((p) => p.id.eq(.value(1)));',
      'db.user.select((u) => userCard(id: u.id, name: u.name));',
      'db.table(userTable).where((u) => u.id.eq(.value(1))).update((u) => [u.name.set("Ada")]);',
    ];
    final invalid = [
      'db.user.select((u) => u.name).patch(name: "read only");',
      'db.user.map((u) => u.name).plan.update(userPatch(name: "read only"));',
      'db.user.byId(1).plan.insert(userInsert(email: "a", name: "filtered"));',
      'db.user.byId(1).prepareUpdate(userPatch(name: "no second path"));',
      'db.user.update(userPatch(name: "Ada")).returning();',
      'db.user.byId(1).patch(name: null);',
      'db.user.byId(1).patch(stamp: "wrong type");',
      'db.user.select((u) => userCard(id: u.id, name: u.name)).delete();',
      'db.user.map((u) => u.name).update(userPatch(name: "x"));',
      'db.user.distinct().delete();',
      'db.user.groupBy((u) => [u.name]).delete();',
      'db.user.select((u) => u.id).unionAll(db.user.select((u) => u.id)).delete();',
      'db.user.update(teamPatch(name: "x"));',
      'userPatch(name: null);',
      'userInsert(name: "missing email");',
      'db.user.where((u) => u.id.eq(.value(1))).insert(userInsert(email: "a", name: "b"));',
      'db.user.select((u) => userCard.sql(id: u.id.map((v) => v), name: u.name));',
      'db.team.select((t) => teamView.sql(id: t.id, name: t.name, owner: t.owner.one(), members: t.members.many()));',
    ];
    final prefix =
        "import 'package:orm/driver.dart';\nimport 'package:orm/orm.dart';\nimport 'package:orm/sql.dart';\nimport '$generated';\nvoid check(Database<Backend> db) {\n";
    await file.writeAsString(
      '$prefix${[...valid, ...invalid].join('\n')}\n}\n',
    );
    final path = file.absolute.path;
    final contexts = AnalysisContextCollection(includedPaths: [path]);
    try {
      final result =
          await contexts.contextFor(path).currentSession.getResolvedUnit(path)
              as ResolvedUnitResult;
      final errors = result.diagnostics
          .where((d) => d.severity.name.toLowerCase() == 'error')
          .toList();
      final first = '\n'.allMatches(prefix).length + 1;
      for (var i = 0; i < valid.length; i++) {
        expect(
          errors.where(
            (d) =>
                result.lineInfo.getLocation(d.offset).lineNumber == first + i,
          ),
          isEmpty,
          reason: valid[i],
        );
      }
      for (var i = 0; i < invalid.length; i++) {
        expect(
          errors.where(
            (d) =>
                result.lineInfo.getLocation(d.offset).lineNumber ==
                first + valid.length + i,
          ),
          isNotEmpty,
          reason: invalid[i],
        );
      }
      expect(
        errors.every(
          (d) =>
              result.lineInfo.getLocation(d.offset).lineNumber >=
              first + valid.length,
        ),
        isTrue,
        reason: errors.join('\n'),
      );
    } finally {
      await contexts.dispose();
      await directory.delete(recursive: true);
    }
  });
}
