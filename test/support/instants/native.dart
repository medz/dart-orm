import 'package:orm/migrate.dart';
import 'package:orm/sqlite.dart';

import 'schema.orm.dart';

Future<void> main() async {
  final db = await sqlite(const SqliteOptions.memory());
  try {
    await Migrator(
      db,
    ).apply([Migration.create('0001_instant', appSchema, dialect: db.dialect)]);
    final expected = DateTime.utc(2024);
    if (Codecs.dateTime.decode('2024-01-01 00:00:00') != expected) {
      throw StateError('UTC storage used process timezone');
    }
    final local = DateTime(2024, 1, 1);
    if (Codecs.dateTime.decode(Codecs.dateTime.encode(local)) !=
        local.toUtc()) {
      throw StateError('Local input changed instant');
    }
    final first = await db.events.create(at: expected);
    final raw =
        (await db.execute(
              SqlCommand('SELECT created FROM events WHERE id = 1'),
            )).rows.single.single
            as String;
    if (first.created != DateTime.parse('${raw}Z')) {
      throw StateError('Default used process timezone');
    }
    final next = DateTime.utc(2024, 1, 1, 0, 0, 0, 0, 1);
    await db.events.create(at: next);
    final ordered = await db.events.orderBy((e) => [e.at.asc()]).get();
    if (ordered.first.at != expected || ordered.last.at != next) {
      throw StateError('Microsecond sorting changed');
    }
    await db.moments.create(at: expected);
    await db.execute(
      SqlCommand("INSERT INTO links (at) VALUES ('2024-01-01 08:00+08')"),
    );
    if ((await db.moments
                .select((m) => m.links.select((l) => l.at).many())
                .single())
            .single !=
        expected) {
      throw StateError('Equivalent instant keys differ');
    }
    if ((await verifySchema(
      db,
      SchemaSnapshot(appSchema),
    )).differences.isNotEmpty) {
      throw StateError('Instant catalog differs');
    }
    print('Instant UTC, precision, ordering, relations and defaults verified.');
  } finally {
    await db.close();
  }
}
