import 'dart:async';

import 'package:orm/driver.dart';
import 'package:orm/orm.dart';
import 'package:orm/sql.dart';
import 'package:orm/sqlite.dart';
import 'package:orm/values.dart';

import 'application.dart';
import 'models.dart' show samples;
import 'models.orm.dart';

final checked = <String>[];
void check(bool condition, String label) {
  if (!condition) throw StateError(label);
  checked.add(label);
}

Future<void> rejects(String code, Future<Object?> Function() action) async {
  try {
    await action();
  } on OrmException catch (e) {
    check(e.code == code, '$code: ${e.code}');
    return;
  }
  throw StateError('Expected $code');
}

Future<List<String>> runModelQueryScenarios() async {
  checked.clear();
  samples = 0;
  final events = <QueryEvent>[];
  var acquires = 0;
  final engine = await sqlite(
    const SqliteOptions.memory(),
    onQuery: events.add,
    onAcquire: (e) {
      if (!e.reusedConnection) acquires++;
    },
  );
  try {
    for (final ddl in [
      'CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT NOT NULL, name TEXT NOT NULL, nickname TEXT, stamp INTEGER NOT NULL)',
      'CREATE TABLE teams (id INTEGER PRIMARY KEY, name TEXT NOT NULL, owner_id INTEGER REFERENCES users(id))',
      "CREATE TABLE memberships (team_id INTEGER REFERENCES teams(id), user_id INTEGER REFERENCES users(id), role TEXT NOT NULL DEFAULT 'member', PRIMARY KEY(team_id,user_id))",
      'CREATE TABLE audit (user_id INTEGER PRIMARY KEY, action TEXT NOT NULL)',
    ]) {
      await engine.raw(Sql(ddl));
    }
    final db = Database.fromSql(engine);
    final ada = await db.user.create(
      email: 'ada@example.test',
      name: 'Ada',
      nickname: 'old',
    );
    final users = [
      ada,
      await db.user.create(email: 'alan@example.test', name: 'Alan'),
      await db.user.create(email: 'grace@example.test', name: 'Grace'),
      await db.user.create(email: 'bob@example.test', name: 'Bob'),
    ];
    final core = await db.team.create(name: 'Core', ownerId: ada.id);
    await db.team.create(name: 'Empty');
    await db.membership.insertMany([
      for (final u in users) membershipInsert(teamId: core.id, userId: u.id),
    ]);
    events.clear();
    acquires = 0;
    final page = membershipPage(db, search: 'a', page: 0, membersOffset: 1);
    final List<TeamView> teams = await page.get();
    check(
      teams.length == 1 && teams.single.name == 'Core',
      'related filter excludes Empty',
    );
    check(
      teams.single.owner?.name == 'Ada',
      'nullable owner partial projection',
    );
    check(
      teams.single.members.map((m) => m.user.name).join(',') == 'Alan,Grace',
      'per-parent stable pagination',
    );
    check(
      events.length == 2 && acquires == 1,
      'two relation statements on one lease',
    );
    final pageSql = events.map((e) => e.sql).toList();
    check(
      pageSql.every(
        (sql) => !sql.contains('email') && !sql.contains('nickname'),
      ),
      'partial projection omits private fields',
    );
    final plan = page.inspect();
    check(plan.loads.length == 1, 'relationship batch visible in plan');

    events.clear();
    acquires = 0;
    var expressions = 0;
    final policy = userPatch.values(
      stamp: .expression((u) {
        expressions++;
        return u.stamp.plus(10);
      }),
    );
    final UserCard changed = await changeMembership(
      db,
      userId: ada.id,
      teamId: core.id,
      profile: {'name': 'Requested', 'nickname': null},
      policy: policy,
      sessionPolicy: userPatch(name: 'Ada reviewed'),
    );
    check(
      changed.name == 'Ada reviewed' && expressions == 1,
      'composed patch with one surviving expression',
    );
    final transactionSql = events.map((e) => e.sql).toList();
    check(
      acquires == 1 &&
          transactionSql.first.startsWith('BEGIN') &&
          transactionSql.last == 'COMMIT',
      'transaction uses one lease and commits once',
    );
    final refreshed = await db.user.byId(ada.id).single();
    check(
      refreshed.nickname == null && refreshed.stamp == 11,
      'explicit null and expression persist',
    );
    try {
      await changeMembership(
        db,
        userId: ada.id,
        teamId: core.id,
        profile: {'name': 'must rollback'},
        policy: userPatch(),
        sessionPolicy: userPatch(),
      );
      throw StateError('expected audit unique constraint');
    } on SqliteFailure {
      /* Audit duplicate must roll back earlier writes. */
    }
    check(
      (await db.user.byId(ada.id).single()).name == 'Ada reviewed',
      'later SQL failure rolls back complete patch transaction',
    );

    // Capability probes use the same two models, not additional business APIs.
    final ModelQuery<User, UserFields, UserPatch> chain = db.user
        .where((u) => u.id.eq(.value(ada.id)))
        .orderBy((u) => [u.id.asc()])
        .take(2)
        .skip(0);
    final User read = await chain.single();
    check(read.id == ada.id, 'model chain retains full row type');
    await rejects(
      'MUTATION.QUERY',
      () => chain.update(userPatch(name: 'invalid')),
    );
    final alias = userTable.alias();
    final ModelQuery<Membership, MembershipFields, MembershipPatch> joined = db
        .membership
        .join(alias, on: (m, u) => m.userId.eq(u.id))
        .where((m) => m.teamId.eq(.value(core.id)));
    await rejects(
      'MUTATION.QUERY',
      () => joined.update(membershipPatch(role: Role.owner)),
    );
    check(
      (await joined.select((_) => person(alias.fields)).get()).length == 4,
      'alias join retains model fields and named result',
    );
    final left = userTable.alias();
    check(
      (await db.team
                  .leftJoin(left, on: (t, u) => t.ownerId.eq(u.id))
                  .orderBy((t) => [t.id.asc()])
                  .select((_) => left.optional(person(left.fields)))
                  .get())
              .last ==
          null,
      'left alias absence remains nullable',
    );

    final offline = SqlBuilder(.sqlite).user
        .where((u) => u.id.eq(.value(ada.id)));
    final ModelQuery<User, UserFields, UserPatch> bound = offline.bind(db);
    check(
      (await bound.single()).id == ada.id,
      'offline query binds preserving patch type',
    );
    final cursor = db.user.cursorToken((u) => [u.id.cursor(ada.id)]);
    final ModelQuery<User, UserFields, UserPatch> after = db.user.seekToken(
      cursor,
      orderBy: (u) => [u.id.asc()],
    );
    check(
      (await after.take(1).single()).name == 'Alan',
      'cursor retains generated model query',
    );
    final flat = db.user.select((u) => userCard.sql(id: u.id, name: u.name));
    check(
      (await flat
                  .unionAll(flat)
                  .asCte('people')
                  .where((p) => p.id.eq(.value(ada.id)))
                  .get())
              .length ==
          2,
      'flat named CTE and UNION retain output fields',
    );
    final List<UserCard> streamed = await db.user
        .orderBy((u) => [u.id.asc()])
        .take(2)
        .select(person)
        .stream(batchSize: 1)
        .toList();
    check(streamed.length == 2, 'stream after model and selection composition');

    final watch = StreamIterator(db.user.byId(ada.id).select(person).watch());
    try {
      check(
        await watch.moveNext().timeout(const Duration(seconds: 5)),
        'watch initial event',
      );
      final next = watch.moveNext().timeout(const Duration(seconds: 5));
      await db.user.byId(ada.id).update(userPatch(name: 'Watched'));
      check(
        await next && watch.current.single.name == 'Watched',
        'watch invalidation after typed write',
      );
    } finally {
      await watch.cancel();
    }

    final before = samples;
    final insert = db.user.plan.insert(
      userInsert(email: 'replay', name: 'Replay'),
    );
    final prepared = insert.prepare();
    check(
      samples == before + 1 && prepared.compile().parameters.isNotEmpty,
      'prepared core mutation freezes defaults and compiles',
    );
    await prepared.execute();
    await prepared.execute();
    check(
      samples == before + 1,
      'prepared mutation replay does not sample again',
    );
    await insert.execute();
    check(samples == before + 2, 'inert command samples per terminal');
    final upsert = db.user.plan
        .insert(userInsert(id: ada.id, email: 'ignored', name: 'Conflict'))
        .prepare()
        .onConflictUpdate(
          target: (u) => [u.id],
          set: (existing, incoming) => [
            existing.name.setExpression(incoming.name),
          ],
        );
    check(
      (await upsert.returning(person).single()).name == 'Conflict',
      'prepared native conflict and returning preserved',
    );
    final batch = db.user.plan.insertMany([
      userInsert(email: 'batch', name: 'Batch'),
    ]).prepare();
    check(
      (await batch.returning(person).get()).single.name == 'Batch',
      'prepared batch returning preserved',
    );

    events.clear();
    acquires = 0;
    final cancelled = CancellationToken()..cancel();
    final cancelledBefore = samples;
    await rejects(
      'OPERATION.CANCELLED',
      () => insert.execute(options: ExecutionOptions(cancellation: cancelled)),
    );
    await rejects(
      'OPERATION.CANCELLED',
      () => insert.row(options: ExecutionOptions(cancellation: cancelled)),
    );
    await rejects(
      'OPERATION.CANCELLED',
      () => insert.returning().single(
        options: ExecutionOptions(cancellation: cancelled),
      ),
    );
    await rejects(
      'OPERATION.CANCELLED',
      () => db.user.insertMany([
        userInsert(email: 'cancel', name: 'Cancel'),
      ], options: ExecutionOptions(cancellation: cancelled)),
    );
    await rejects(
      'MUTATION.RELATION',
      () => insert.returning().select((u) => u.memberships.many()).get(),
    );
    check(
      samples == cancelledBefore && events.isEmpty && acquires == 0,
      'cancelled and invalid descriptions have no defaults or I/O',
    );
    late Write<User, UserFields> escaped;
    await db.session((session) async {
      escaped = session.user
          .byId(ada.id)
          .plan
          .update(userPatch(name: 'escaped'));
    });
    await rejects('SESSION.CLOSED', () => escaped.execute());
    check(
      (await db.user.byId(ada.id).single()).name == 'Conflict',
      'expired description leaves root usable',
    );
    // The manual SQL table path keeps assignment-based writes after filtering.
    await db
        .table(userTable)
        .where((u) => u.id.eq(.value(ada.id)))
        .update((u) => [u.nickname.set('manual')])
        .execute();
    check(
      (await db.user.byId(ada.id).single()).nickname == 'manual',
      'manual table writes preserved',
    );
    return List.unmodifiable(checked);
  } finally {
    await engine.close();
  }
}
