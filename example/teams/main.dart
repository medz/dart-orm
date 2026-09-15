import 'package:orm/migrate.dart';
import 'package:orm/sqlite.dart';

import 'schema.dart';
import 'schema.orm.dart';

Future<void> main() async {
  final events = <QueryEvent>[];
  final db = await sqlite(const SqliteOptions.memory(), onQuery: events.add);
  try {
    await Migrator(db).apply([Migration.create('0001_teams', appSchema)]);
    await db.transaction((tx) async {
      await tx.users.create(id: 1, name: 'Ada');
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
    });
    events.clear();
    final cards = await db.users
        .select(
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
        )
        .get();
    print(cards);
    print(
      '${events.length} SQL statements; ${events.map((e) => e.rowCount).toList()} rows',
    );
  } finally {
    await db.close();
  }
}
