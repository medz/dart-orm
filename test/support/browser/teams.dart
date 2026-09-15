import 'package:orm/migrate.dart';
import 'package:orm/sqlite_web.dart';

import '../../../example/teams/schema.dart';
import '../../../example/teams/schema.orm.dart';

Future<void> checkTeams(Uri wasm, Uri worker) async {
  final events = <QueryEvent>[];
  final acquired = <AcquisitionEvent>[], decoded = <DecodeEvent>[];
  final db = await sqliteWeb(
    SqliteWebOptions.memory(wasm: wasm, worker: worker),
    onQuery: events.add,
    onAcquire: acquired.add,
    onDecode: decoded.add,
  );
  void expect(bool value, String message) {
    if (!value) throw StateError(message);
  }

  try {
    await Migrator(
      db,
    ).apply([Migration.create('0001_teams', appSchema, dialect: db.dialect)]);
    await db.transaction((tx) async {
      await tx.users.create(id: 1, name: 'Ada');
      await tx.users.create(id: 2, name: 'Ben');
      await tx.users.create(id: 3, name: 'Cy');
      await tx.teams.create(id: 10, name: 'Core');
      await tx.teams.create(id: 20, name: 'Docs');
      await tx.memberships.create(
        teamId: 10,
        userId: 1,
        role: .set(MembershipRole.owner),
        joinedAt: DateTime.utc(2026, 1, 1),
      );
      await tx.memberships.create(
        teamId: 20,
        userId: 1,
        joinedAt: DateTime.utc(2026, 1, 2),
      );
      await tx.memberships.create(
        teamId: 10,
        userId: 2,
        joinedAt: DateTime.utc(2026, 1, 1),
      );
    });
    events.clear();
    acquired.clear();
    decoded.clear();
    final query = db.users
        .orderBy((u) => [u.id.asc()])
        .select(
          (u) => u.memberships
              .orderBy((m) => [m.joinedAt.desc(), m.teamId.desc()])
              .take(1)
              .select(
                (m) => (
                  m.team.select((t) => t.name).required(),
                  m.role,
                ).map((team, role) => (team: team, role: role)),
              )
              .many(),
        );
    final plan = query.inspect();
    expect(
      plan.sqlTemplateCount == 2 && plan.loads.single.limitPerParent == 1,
      'Inspection lost a batch or its per-parent limit',
    );
    expect(
      events.isEmpty && acquired.isEmpty && decoded.isEmpty,
      'Inspection performed execution work',
    );
    final rows = await query.get();
    expect(
      rows[0].single == (team: 'Docs', role: MembershipRole.member),
      'User 1 association differs',
    );
    expect(
      rows[1].single == (team: 'Core', role: MembershipRole.member) &&
          rows[2].isEmpty,
      'Shared/empty association differs',
    );
    expect(
      events.length == 2 && events[0].rowCount == 3 && events[1].rowCount == 2,
      'Relation counts or row volume differ',
    );
    expect(
      acquired.length == 1 &&
          !acquired.single.reusedConnection &&
          acquired.single.error == null,
      'Acquisition observation differs',
    );
    expect(
      decoded.length == 2 &&
          decoded[0].inputRows == 2 &&
          decoded[1].inputRows == 3 &&
          decoded.every((e) => e.error == null),
      'Decoding observations differ',
    );
    final calls = <String>[];
    T mark<T>(String label, T value) {
      calls.add(label);
      return value;
    }

    final mixed = db.users
        .where((u) => u.id.eq(1))
        .select(
          (u) =>
              (
                u.id.map((v) => mark('id', v)),
                u.name.map((v) => mark('name', v)),
                u.id.map((v) => mark('active', v > 0)),
                u.name.map<String?>((_) => mark('nullable', null)),
                u.id.map((v) => mark('fraction', v + .5)),
                u.name.map((v) => mark('tags', [v])),
              ).map((id, name, active, nullable, fraction, tags) {
                calls.add('result');
                return (
                  id: id,
                  name: name,
                  active: active,
                  nullable: nullable,
                  fraction: fraction,
                  tags: tags,
                );
              }),
        );
    mixed.inspect();
    expect(calls.isEmpty, 'Inspection invoked a mixed projection mapper');
    final value = await mixed.single();
    expect(
      value.id == 1 &&
          value.name == 'Ada' &&
          value.active &&
          value.nullable == null &&
          value.fraction == 1.5 &&
          value.tags.single == 'Ada',
      'Six-field mixed projection differs',
    );
    expect(
      calls.join(',') == 'id,name,active,nullable,fraction,tags,result',
      'Mixed projection evaluation order differs',
    );
    await db.transaction((tx) async {
      await tx.teams.byId(10).patch(name: .set('Kernel'));
      await tx.memberships
          .byId(teamId: 10, userId: 2)
          .patch(role: .set(MembershipRole.owner));
    });
    expect(
      (await query.get())[1].single ==
          (team: 'Kernel', role: MembershipRole.owner),
      'Transaction did not retain payload/endpoint changes',
    );
    await db.teams.byId(10).delete().execute();
    expect(
      await db.memberships.count() == 1 && await db.users.count() == 3,
      'Cascade removed an endpoint or retained invalid associations',
    );
    expect(
      (await verifySchema(db, SchemaSnapshot(appSchema))).matches,
      'Junction schema differs',
    );
  } finally {
    await db.close();
  }
}
