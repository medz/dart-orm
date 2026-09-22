import 'package:orm/migrate.dart';
import 'package:orm/sqlite.dart';

import 'schema.orm.dart';

Future<void> main() async {
  final events = <QueryEvent>[];
  final acquisitions = <AcquisitionEvent>[];
  final decodes = <DecodeEvent>[];
  final db = await sqlite(
    const SqliteOptions.memory(),
    onQuery: events.add,
    onAcquire: acquisitions.add,
    onDecode: decodes.add,
  );
  try {
    await Migrator(
      db.sql,
    ).apply([Migration.create('0001_teams', appSchema, dialect: db.dialect)]);
    await db.transaction((tx) async {
      await tx.user.create(id: 1, name: 'Ada');
      await tx.team.create(id: 10, name: 'Core');
      await tx.team.create(id: 20, name: 'Docs');
      await tx.membership.create(
        teamId: 10,
        userId: 1,
        role: .set(MembershipRole.owner),
        joinedAt: DateTime.utc(2026, 1, 1),
      );
      await tx.membership.create(
        teamId: 20,
        userId: 1,
        joinedAt: DateTime.utc(2026, 1, 2),
      );
    });
    final owners = await db.user
        .where(
          (u) => u.memberships
              .where(
                (m) => allOf([
                  m.role.eq(.value(MembershipRole.owner)),
                  m.team.where((t) => t.name.eq(.value('Core'))).any(),
                ]),
              )
              .any(),
        )
        .select((u) => u.name)
        .get();
    if (owners.length != 1 || owners.single != 'Ada') {
      throw StateError(
        'Nested association filters must select the Core owner.',
      );
    }
    print('Core owners: $owners');
    events.clear();
    acquisitions.clear();
    decodes.clear();
    final query = db.user.select(
      (u) => (
        u.name,
        u.memberships
            .orderBy((m) => [m.joinedAt.desc(), m.teamId.desc()])
            .take(2)
            .select(
              (m) => (
                m.team.select((t) => t.name).required(),
                m.role,
              ).map((team, role) => (team: team, role: role)),
            )
            .many(),
      ).map((name, teams) => (name: name, teams: teams)),
    );
    final plan = query.inspect();
    print(
      '${plan.sqlTemplateCount} SQL templates; ${plan.loads.single.maxKeysPerBatch} parent keys per batch',
    );
    final cards = await query.get();
    print(cards);
    print(
      '${events.length} SQL statements; ${events.map((e) => e.rowCount).toList()} rows',
    );
    print(
      '${acquisitions.length} acquisition; ${decodes.length} decode batches',
    );
  } finally {
    await db.close();
  }
}
