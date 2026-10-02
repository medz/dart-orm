@Tags(['sqlite'])
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';

import '../tool/src/build_fixture.dart';

void main() {
  test('generated selections retain exact inference across libraries, kernel and AOT', () async {
    final fixture = await BuildFixture.create(ormPath: Directory.current.path);
    try {
      for (final name in ['models', 'cards', 'roles']) {
        await fixture.write(
          'lib/${name == 'models' ? 'schema' : name}.dart',
          await File('test/support/api_shape/$name.dart').readAsString(),
        );
      }
      await fixture.write('analysis_options.yaml', '''
analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
''');
      await fixture.write('lib/helpers.dart', _helpers);
      await fixture.write('lib/api.dart', '''
export 'package:orm/orm.dart';
export 'package:orm/sql.dart';
export 'schema.orm.dart';
export 'helpers.dart';
''');
      await fixture.write('bin/selection.dart', _consumer);
      await fixture.run(['run', 'build_runner', 'build']);
      await fixture.run(['analyze']);
      final path = fixture.file('bin/selection.dart').path;
      final contexts = AnalysisContextCollection(
        includedPaths: [fixture.directory.path],
      );
      try {
        final unit =
            await contexts.contextFor(path).currentSession.getResolvedUnit(path)
                as ResolvedUnitResult;
        final inferred = _InferredTypes();
        unit.unit.accept(inferred);
        final helperPath = fixture.file('lib/helpers.dart').path;
        final helpers =
            await contexts
                    .contextFor(helperPath)
                    .currentSession
                    .getResolvedUnit(helperPath)
                as ResolvedUnitResult;
        helpers.unit.accept(inferred);
        for (final entry in _expectedTypes.entries) {
          expect(inferred.types[entry.key], entry.value, reason: entry.key);
        }
      } finally {
        await contexts.dispose();
      }
      expect(
        (await fixture.run(['run', 'orm_build_fixture:selection'])).output,
        contains('generated-selection-ok'),
      );
      await fixture.run([
        'build',
        'cli',
        '--target',
        'bin/selection.dart',
        '--output',
        'deployment',
      ]);
      final aot = await Process.run(
        '${fixture.directory.path}/deployment/bundle/bin/selection',
        [],
        workingDirectory: fixture.directory.path,
      );
      expect(aot.exitCode, 0, reason: '${aot.stdout}\n${aot.stderr}');
      expect(aot.stdout, contains('generated-selection-ok'));

      // Compile every negative independently: one earlier error must not hide
      // another case or mask analyzer/kernel disagreement about inference.
      final invalid = [..._invalid, 'db.user.select((u) => u.id);'];
      for (var i = 0; i < invalid.length; i++) {
        await fixture.write('negative/case_$i.dart', '''
import 'package:orm/driver.dart';
${i == _invalid.length ? "import 'package:orm/orm.dart';\nimport '../lib/schema.orm.dart';" : "import '../lib/api.dart';"}
void bad(Database<Backend> db) { ${invalid[i]} }
void main() {}
''');
      }
      final negatives = AnalysisContextCollection(
        includedPaths: [fixture.file('negative').path],
      );
      try {
        for (var i = 0; i < invalid.length; i++) {
          final path = fixture.file('negative/case_$i.dart').path;
          final unit =
              await negatives
                      .contextFor(path)
                      .currentSession
                      .getResolvedUnit(path)
                  as ResolvedUnitResult;
          expect(
            unit.diagnostics.where(
              (d) => d.severity.name.toLowerCase() == 'error',
            ),
            isNotEmpty,
            reason: 'analyzer accepted: ${invalid[i]}',
          );
          if (i == _invalid.length) {
            expect(
              unit.diagnostics.any(
                (d) =>
                    d.diagnosticCode.lowerCaseName == 'undefined_method' &&
                    d.message.contains('select'),
              ),
              isTrue,
              reason:
                  'orm.dart and generated clients do not export SelectQuery.',
            );
          }
          final kernel = await Process.run(Platform.resolvedExecutable, [
            'compile',
            'kernel',
            'negative/case_$i.dart',
            '-o',
            'negative.dill',
          ], workingDirectory: fixture.directory.path);
          expect(
            kernel.exitCode,
            isNot(0),
            reason: 'kernel accepted: ${invalid[i]}',
          );
          expect(
            '${kernel.stdout}\n${kernel.stderr}',
            contains('negative/case_$i.dart:'),
            reason:
                'Kernel must reject the consumer, not fail for infrastructure.',
          );
        }
      } finally {
        await negatives.dispose();
      }
    } finally {
      await fixture.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}

final class _InferredTypes extends RecursiveAstVisitor<void> {
  final types = <String, String>{};
  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    types[node.name.lexeme] = node.declaredFragment!.element.type
        .getDisplayString();
    super.visitVariableDeclaration(node);
  }
}

const _expectedTypes = {
  'scalar': 'SelectedQuery<String, UserFields, Expr<String>>',
  'nullable': 'SelectedQuery<String?, UserFields, Field<String?>>',
  'ordinary': 'SelectedQuery<UserCard, UserFields, Selection<UserCard>>',
  'flat': 'SelectedQuery<UserCard, UserFields, Projection<UserCard, UserCardFields>>',
  'cte': 'DerivedQuery<UserCard, UserCardFields, Projection<UserCard, UserCardFields>>',
  'set': 'SelectedQuery<UserCard, UserCardFields, Projection<UserCard, UserCardFields>>',
  'nested': 'SelectedQuery<TeamView, TeamFields, Selection<TeamView>>',
  'related': 'Relation<UserCard, UserFields>',
};

const _helpers = r'''
import 'package:orm/sql.dart';
import 'schema.orm.dart';

Selection<UserCard> person(UserFields u) => userCard(id: u.id, name: u.name);
Projection<UserCard, UserCardFields> personSql(UserFields u) =>
    userCard.sql(id: u.id, name: u.name);
Selection<TeamView> teamPage(TeamFields t) {
  final related = t.owner.select(person);
  if (_typeOf(related) != Relation<UserCard, UserFields>) {
    throw StateError('relation inference');
  }
  return teamView(
    id: t.id, name: t.name, owner: related.one(),
    members: t.members.orderBy((m) => [m.userId.asc()]).select((m) =>
      memberCard(user: m.user.select(person).required(), role: m.role)).many(),
  );
}
Type _typeOf<T>(T value) => T;

final alternateId = Slot<int>('id');
final alternateName = Slot<String>('name');
final class AlternateFields extends ProjectionOutput {
  AlternateFields(ProjectionFields fields)
      : id = fields.read(alternateId), name = fields.read(alternateName), super(fields.table);
  final Expr<int> id;
  final Expr<String> name;
}
final alternateCard = ProjectionType<UserCard, AlternateFields>(
  slots: [alternateId, alternateName],
  assemble: (values) => UserCard(id: values[0] as int, name: values[1] as String),
  fields: AlternateFields.new,
);
Projection<UserCard, AlternateFields> alternateSql(UserFields u) =>
    alternateCard.bind([alternateId.bind(u.id), alternateName.bind(u.name)]);
''';

const _consumer = r'''
import 'dart:async';
import 'package:orm/sqlite.dart';
import 'package:orm/values.dart';
// Extensions reach this consumer through its application barrel.
import '../lib/api.dart';

Type typeOf<T>(T value) => T;
void check(bool condition, String label) { if (!condition) throw StateError(label); }
Future<void> rejects(String code, FutureOr<Object?> Function() action) async {
  try { await action(); } on OrmException catch (e) {
    check(e.code == code, '$code: ${e.code}'); return;
  }
  throw StateError('Expected $code');
}
Future<void> main() async {
  final events = <QueryEvent>[];
  final db = Database.fromSql(await sqlite(const SqliteOptions.memory(), onQuery: events.add));
  try {
    for (final ddl in [
      'CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT NOT NULL, name TEXT NOT NULL, nickname TEXT, stamp INTEGER NOT NULL)',
      'CREATE TABLE teams (id INTEGER PRIMARY KEY, name TEXT NOT NULL, owner_id INTEGER REFERENCES users(id))',
      "CREATE TABLE memberships (team_id INTEGER REFERENCES teams(id), user_id INTEGER REFERENCES users(id), role TEXT NOT NULL DEFAULT 'member', PRIMARY KEY(team_id,user_id))",
    ]) { await db.sql.raw(Sql(ddl)); }
    final ada = await db.user.create(email: 'ada@example.test', name: 'Ada');
    final core = await db.team.create(name: 'Core', ownerId: ada.id);
    await db.team.create(name: 'Empty');
    await db.membership.create(teamId: core.id, userId: ada.id);
    final scalar = db.user.select((u) => u.name.lower());
    final nullable = db.user.byId(ada.id).select((u) => u.nickname);
    final ordinary = db.user.where((u) => u.id.eq(.value(ada.id))).select(person);
    final flat = db.user.select(personSql).where((u) => u.id.eq(.value(ada.id)))
        .orderBy((u) => [u.id.asc()]).take(2).skip(0).distinct();
    final cte = flat.asCte('people');
    final set = cte.unionAll(db.user.select(personSql));
    final nested = db.team.orderBy((t) => [t.id.asc()]).select(teamPage);
    check(typeOf(scalar) == SelectedQuery<String, UserFields, Expr<String>>, 'scalar type');
    check(typeOf(nullable) == SelectedQuery<String?, UserFields, Field<String?>>, 'nullable type');
    check(typeOf(ordinary) == SelectedQuery<UserCard, UserFields, Selection<UserCard>>, 'ordinary type');
    check(typeOf(flat) == SelectedQuery<UserCard, UserFields, Projection<UserCard, UserCardFields>>, 'flat type');
    check(typeOf(cte) == DerivedQuery<UserCard, UserCardFields, Projection<UserCard, UserCardFields>>, 'CTE type');
    check(typeOf(set) == SelectedQuery<UserCard, UserCardFields, Projection<UserCard, UserCardFields>>, 'set type');
    check(typeOf(nested) == SelectedQuery<TeamView, TeamFields, Selection<TeamView>>, 'nested type');
    check(await scalar.single() == 'ada', 'scalar decode');
    check(await nullable.single() == null, 'nullable decode');
    check((await ordinary.single()).name == 'Ada', 'ordinary helper');
    check((await cte.where((p) => p.name.eq(.value('Ada'))).single()).id == ada.id, 'named CTE');
    check((await set.where((p) => p.id.eq(.value(ada.id))).get()).length == 2, 'named union');
    events.clear();
    final teams = await nested.get();
    check(teams.first.owner?.name == 'Ada' && teams.first.members.single.user.id == ada.id, 'nested helpers');
    check(teams.last.owner == null && teams.last.members.isEmpty, 'empty relations');
    check(events.length == 2, 'observable relation query count');

    // Both a contextually instantiated and a generic extension tear-off.
    final SelectedQuery<UserCard, UserFields, Selection<UserCard>> Function(
      Selection<UserCard> Function(UserFields)) choose = db.user.select;
    final chooseGeneric = db.user.select;
    check(typeOf(chooseGeneric(personSql)) == SelectedQuery<UserCard, UserFields, Projection<UserCard, UserCardFields>>, 'generic tear-off type');
    check((await choose(person).single()).id == ada.id, 'typed tear-off');
    check((await chooseGeneric(personSql).asCte('chosen').single()).name == 'Ada', 'generic tear-off');

    // Query, TableSet/TableQuery, ModelTable/ModelQuery, SelectedQuery and
    // DerivedQuery all inherit the same extension without a shadowing member.
    final Query<User, UserFields> base = db.user;
    final TableSet<User, UserFields> table = db.table(userTable);
    final TableQuery<User, UserFields> filtered = table.where((u) => u.id.eq(.value(ada.id)));
    check((await base.select(person).single()).id == ada.id, 'Query');
    check((await table.select(person).single()).id == ada.id, 'TableSet');
    check((await filtered.select(person).single()).id == ada.id, 'TableQuery');
    check(await ordinary.select((u) => u.name).single() == 'Ada', 'SelectedQuery reselection');
    check(await cte.select((p) => p.name).single() == 'Ada', 'DerivedQuery reselection');
    final alias = userTable.alias();
    final joined = db.user.select(personSql).leftJoin(alias, on: (u, a) => u.id.eq(a.id));
    check((await joined.asCte('joined').single()).id == ada.id, 'join retains projection');
    final grouped = db.user.select(personSql).groupBy((u) => [u.id, u.name]).having((u) => u.id.count().gt(.value(0)));
    check((await grouped.asCte('grouped').single()).id == ada.id, 'group retains projection');
    check((await ordinary.asCte('plain').where((p) => p.ref((u) => u.id).eq(.value(ada.id))).single()).id == ada.id, 'generic CTE references');
    check((await flat.map((p) => p.name).single()) == 'Ada', 'Dart mapping');
    final rebound = SqlBuilder(.sqlite).user.select(personSql).bind(db);
    check((await rebound.asCte('bound').single()).id == ada.id, 'binding retains projection');
    check((await db.user.byId(ada.id).plan.update(userPatch(name: 'Updated')).returning().select(person).single()).name == 'Updated', 'RETURNING helper');
    await db.transaction((tx) async {
      check((await tx.user.select(personSql).asCte('tx_people').single()).id == ada.id, 'transaction binding');
    });

    // A DTO-valued SQL cell with an explicit codec is a valid flat slot.
    // Its Dart type alone cannot distinguish it from a loaded relationship.
    final cardsCodec = Codecs.text.map<List<MemberCard>>(
      (text) => [MemberCard(user: UserCard(id: ada.id, name: text), role: Role.member)],
      (cards) => cards.single.user.name,
    );
    final ownerCodec = Codecs.text.map<UserCard>((text) => UserCard(id: ada.id, name: text), (card) => card.name).nullable();
    final boxed = db.team.where((t) => t.id.eq(.value(core.id))).select((t) => teamView.sql(
      id: t.id, name: t.name,
      owner: value(UserCard(id: ada.id, name: 'Owner cell'), ownerCodec),
      members: value([MemberCard(user: UserCard(id: ada.id, name: 'List cell'), role: Role.member)], cardsCodec),
    )).asCte('boxed');
    final box = await boxed.single();
    check(box.owner?.name == 'Owner cell' && box.members.single.user.name == 'List cell', 'codec-backed DTO and list cells');

    events.clear();
    // Covariance can hide concrete field types, never descriptor identity.
    final SelectedQuery<UserCard, UserFields, Projection<UserCard, ProjectionOutput>> wide = flat;
    await rejects('QUERY.UNION_CONTRACT', () => wide.union(db.user.select(alternateSql)));
    final custom = Codecs.text.map((v) => v, (String v) => v);
    await rejects('QUERY.UNION_CODEC', () => flat.union(db.user.select((u) => userCard.sql(id: u.id, name: value('Ada', custom)))));
    final absent = userTable.alias();
    await rejects('QUERY.NULLABILITY', () => db.team.leftJoin(absent, on: (t, u) => t.ownerId.eq(u.id)).select((t) => personSql(absent.fields)).asCte('unsafe'));
    final outside = userTable.alias();
    await rejects('QUERY.SCOPE', () => db.user.select((u) => personSql(outside.fields)).compile());
    await rejects('MUTATION.RELATION', () => db.team.byId(core.id).plan.update(teamPatch(name: 'Bad')).returning().select(teamPage).get());
    check(events.isEmpty, 'invalid SQL boundaries send no statements');
    late Query<UserCard, UserCardFields> expired;
    await db.session((session) async {
      await rejects('QUERY.UNION_SESSION', () => flat.union(session.user.select(personSql)));
      expired = session.user.select(personSql).asCte('expired');
    });
    await rejects('SESSION.CLOSED', expired.get);
    check(await db.user.count() == 1, 'root remains usable');
    print('generated-selection-ok');
  } finally { await db.close(); }
}
''';

const _invalid = [
  'db.user.select(person).asCte("p").where((p) => p.name.eq(.value("x")));',
  'db.team.select(teamPage).asCte("p").where((p) => p.name.eq(.value("x")));',
  'Selection<UserCard> erased(UserFields u) => personSql(u); db.user.select(erased).asCte("p").where((p) => p.name.eq(.value("x")));',
  'db.user.select(personSql).map((p) => p).asCte("p").where((p) => p.name.eq(.value("x")));',
  'db.user.select((u) => userCard.sql(id: u.id.map((id) => id), name: u.name));',
  'db.team.select((t) => teamView.sql(id: t.id, name: t.name, owner: t.owner.select(person).one(), members: t.members.many()));',
  'db.user.select(personSql).unionAll(db.user.select(person));',
  'db.user.select(personSql).unionAll(db.user.select((u) => u.name));',
  'db.user.select(personSql).unionAll(db.user.select(alternateSql));',
  'db.user.select((u) => u.id).get().then((rows) => rows.single.missing);',
  'db.user.select((u) => u.nickname).get().then((rows) => rows.single.length);',
  'db.user.select(person).update(userPatch(name: "x"));',
  'db.user.plan.update(userPatch(name: "x")).returning().select(person).asCte("p");',
  'db.team.select((t) { final Expr<List<UserCard>> bad = t.members.select((m) => m.user.select(person).required()).many(); return bad; });',
  'db.user.select(personSql).where((p) => p.missing.eq(.value(1)));',
  'db.user.select(personSql).asCte("p").where((p) => p.email.eq(.value("x")));',
  'db.user.select((u) => u.name.lower()).single().then((v) => v.nonexistent());',
  'final choose = db.user.select; choose(person).single().then((v) => v.missing);',
  'db.team.select((t) => t.owner.select(person).one()).single().then((v) => v.name);',
  'db.user.select(personSql).take(1).skip(0).distinct().asCte("p").where((p) => p.id.eq(.value("wrong")));',
  'db.user.select(personSql).bind(db).asCte("p").where((p) => p.name.eq(.value(1)));',
];
