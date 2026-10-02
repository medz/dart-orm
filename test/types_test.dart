@Tags(['core'])
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:test/test.dart';

void main() {
  test(
    'junction-table keys, enum payloads and nested results keep generated types',
    () => _checkTypes(
      imports: ['example/teams/schema.orm.dart'],
      valid: [
        'db.membership.byId(teamId: 1, userId: 1).patch(role: MembershipRole.owner);',
        'db.membership.create(teamId: 1, userId: 1, joinedAt: DateTime.now());',
        'final Future<List<List<Membership>>> rows = db.user.select((u) => u.memberships.many()).get();',
      ],
      invalid: [
        'db.membership.byId(1);',
        'db.membership.byId(teamId: 1);',
        "db.membership.create(teamId: 'wrong', userId: 1, joinedAt: DateTime.now());",
        "db.membership.byId(teamId: 1, userId: 1).patch(role: 'owner');",
        'db.user.select((u) => u.memberships.connect(1));',
        'final Future<List<String>> rows = db.user.select((u) => u.memberships.many()).get();',
      ],
    ),
  );
  test(
    'computed generated fields are statically readable and never writable',
    () => _checkTypes(
      imports: ['test/support/computed/schema.orm.dart'],
      valid: [
        "db.line.create(price: 1, quantity: 1, label: '');",
        'db.line.byId(1).patch(price: 2);',
        'final Future<List<int>> totals = db.line.select((r) => r.total).get();',
        'db.table(lineTable).update((r) => [r.price.set(1)]);',
      ],
      invalid: [
        "db.line.create(price: 1, quantity: 1, label: '', total: 1);",
        'db.line.byId(1).patch(total: 1);',
        'db.table(lineTable).update((r) => [r.total.set(1)]);',
        'db.table(lineTable).update((r) => [r.total.increment(1)]);',
        'db.table(lineTable).update((r) => [r.total.defaultValue()]);',
        'db.table(lineTable).update((r) => [r.total.setExpression(r.price)]);',
        'db.line.select((r) => r.total.eq(.value("wrong")));',
      ],
    ),
  );
  test(
    'client-default create parameters preserve domain, nullable and timestamp types',
    () => _checkTypes(
      imports: [
        'test/support/defaults/schema.orm.dart',
        'test/support/defaults/types.dart',
      ],
      valid: [
        'db.ticket.create();',
        "db.ticket.create(id: const TicketId(1), name: 'Name', label: 'value', createdAt: DateTime.now());",
        'db.ticket.create(label: null);',
      ],
      invalid: [
        'db.ticket.create(id: 1);',
        'db.ticket.create(name: null);',
        "db.ticket.create(createdAt: 'now');",
        'db.ticket.create(label: 1);',
      ],
    ),
  );
  test(
    'query-only relation APIs retain result types and expose no graph writes',
    () => _checkTypes(
      imports: ['test/support/unconstrained/schema.orm.dart'],
      valid: [
        'final Future<List<int?>> owners = db.entry.select((e) => e.ownerAccount.select((a) => a.id).one()).get();',
        'final Future<List<List<int>>> matches = db.entry.select((e) => e.matchingAccounts.select((a) => a.id).many()).get();',
      ],
      invalid: [
        'db.entry.select((e) => e.ownerAccount.update((a) => [a.id.set(1)]));',
        'db.entry.select((e) => e.ownerAccount.delete());',
        'db.entry.select((e) => e.ownerAccount.connect(1));',
        'final Future<List<int>> values = db.entry.select((e) => e.ownerAccount.select((a) => a.id).one()).get();',
        'final Future<List<String>> rows = db.entry.select((e) => e.matchingAccounts.select((a) => a.id).many()).get();',
      ],
    ),
  );
  test(
    'calendar APIs reject instants, strings and mixed temporal types',
    () => _checkTypes(
      imports: ['test/support/temporals/schema.orm.dart'],
      valid: [
        'db.appointment.create(day: LocalDate(2024, 1, 1));',
        'db.appointment.byId(1).patch(starts: LocalDateTime.parse("2024-01-01T12:00:00"));',
        'final Future<List<LocalDate>> days = db.appointment.select((a) => a.day).get();',
        'db.appointment.where((a) => a.time.eq(.value(LocalTime(12, 0))));',
      ],
      invalid: [
        'db.appointment.create(day: DateTime.utc(2024));',
        "db.appointment.byId(1).patch(starts: '2024-01-01');",
        'db.appointment.where((a) => a.time.eq(.value(LocalDate(2024, 1, 1))));',
        "db.appointment.where((a) => a.day.eq(.value('2024-01-01')));",
        'db.appointment.select((a) => a.day).union(db.appointment.select((a) => a.time));',
      ],
    ),
  );
  test(
    'actual generated APIs reject wrong inputs, results and backend options',
    () => _checkTypes(
      imports: [
        'example/schema.orm.dart',
        'test/support/codecs/schema.orm.dart',
        'test/support/codecs/types.dart',
      ],
      valid: [
        'db.user.byId(1).update(userPatch(email: "valid"));',
        'final Future<List<String>> emails = db.user.select((u) => u.email).get();',
        'db.person.byId(const PersonId(1)).update(personPatch(email: const Email("a@b"), membership: Membership.active));',
        'db.person.byId(const PersonId(1)).patch(tags: ["tag"], details: const SqlJson({"ok": true}));',
        'db.transaction((tx) async {}, options: const SqliteTransaction());',
        'final Stream<List<String>> watch = db.user.select((u) => u.email).watch();',
        'final Future<List<(int, String)>> union = db.user.select((u) => (u.id, u.email).row).union(db.user.select((u) => (u.id, u.email).row)).get();',
      ],
      invalid: [
        'db.user.create(email: 1);',
        "db.user.byId('wrong');",
        'db.user.byId(1).update(userPatch.values(email: .set(null)));',
        'db.user.select((u) => u.email.eq(.value(1)));',
        'db.transaction((tx) async {}, options: const PostgresTransaction());',
        'final Query<int, UserFields> bad = db.user.select((u) => u.email);',
        "db.user.seekAfter((u) => [u.id.cursor('wrong')]);",
        'db.person.byId(1);',
        "db.person.byId(const PersonId(1)).update(personPatch.values(email: .set('wrong')));",
        "db.person.byId(const PersonId(1)).update(personPatch.values(membership: .set('active')));",
        'db.person.select((p) => p.id.eq(.value(1)));',
        "db.person.select((p) => p.email.eq(.value('wrong')));",
        'db.person.byId(const PersonId(1)).update(personPatch.values(tags: .set([1])));',
        "db.person.byId(const PersonId(1)).update(personPatch.values(details: .set('raw-json')));",
        'final Stream<List<int>> wrongWatch = db.user.select((u) => u.email).watch();',
        "db.user.watch(reads: ['users']);",
        'db.user.select((u) => u.id).union(db.user.select((u) => u.email));',
        'db.user.select((u) => (u.id, u.email).row).union(db.user.select((u) => (u.email, u.id).row));',
        'final Future<List<(String, int)>> wrongUnion = db.user.select((u) => (u.id, u.email).row).union(db.user.select((u) => (u.id, u.email).row)).get();',
      ],
    ),
  );
}

Future<void> _checkTypes({
  required List<String> imports,
  required List<String> valid,
  required List<String> invalid,
}) async {
  final directory = await Directory('.dart_tool')
      .createTemp('generated-types-');
  final file = File('${directory.path}/consumer.dart').absolute;
  final prefix =
      '''
import 'package:orm/orm.dart';
import 'package:orm/sql.dart';
import 'package:orm/driver.dart';
import 'package:orm/sqlite.dart';
import 'package:orm/values.dart';
${imports.map((p) => "import '${File(p).absolute.uri}';").join('\n')}
void check(Database<Sqlite> db) {
''';
  // Individual blocks prevent reused test-local names from producing a false
  // rejection; positive controls establish that the current client is in scope.
  await file.writeAsString(
    '$prefix${[...valid, ...invalid].map((s) => '{ $s }').join('\n')}\n}\n',
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
        .where((d) => d.severity.name.toLowerCase() == 'error')
        .toList();
    final first = '\n'.allMatches(prefix).length + 1;
    final invalidFirst = first + valid.length;
    expect(
      errors.where(
        (d) => result.lineInfo.getLocation(d.offset).lineNumber < invalidFirst,
      ),
      isEmpty,
      reason:
          'Imports, current API names and positive controls must resolve: ${errors.join('\n')}',
    );
    for (var i = 0; i < invalid.length; i++) {
      expect(
        errors.where(
          (d) =>
              result.lineInfo.getLocation(d.offset).lineNumber ==
              invalidFirst + i,
        ),
        isNotEmpty,
        reason: invalid[i],
      );
    }
    expect(
      errors.every((d) {
        final line = result.lineInfo.getLocation(d.offset).lineNumber;
        return line >= invalidFirst && line < invalidFirst + invalid.length;
      }),
      isTrue,
      reason: errors.join('\n'),
    );
  } finally {
    await contexts.dispose();
    await directory.delete(recursive: true);
  }
}
