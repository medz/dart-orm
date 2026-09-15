import 'package:orm/migrate.dart';
import 'package:orm/sqlite.dart';

import 'schema.orm.dart';

Future<void> main() async {
  final db = await sqlite(const SqliteOptions.memory());
  try {
    await Migrator(db).apply([Migration.create('0001_local', appSchema)]);
    final last = LocalDate.fromJulianDay(LocalDate.maxJulianDay);
    final stamp = LocalDateTime.parse('294276-12-31 23:59:59.999999');
    final row = await db.appointments.create(
      day: last,
      time: Change.set(LocalTime(24)),
      starts: stamp,
    );
    if (row.day != last || row.time != LocalTime(24) || row.starts != stamp) {
      throw StateError('Finite endpoint changed');
    }
    await db.appointments.create(day: LocalDate.fromJulianDay(0));
    final sorted = await db.appointments
        .orderBy((a) => [a.day.asc()])
        .stream(batchSize: 1)
        .toList();
    if (sorted.first.day.julianDay != 0 || sorted.last.day != last) {
      throw StateError('Calendar ordering changed');
    }
    await db.holidays.create(day: LocalDate(0, 1, 1), label: 'era');
    await db.execute(
      SqlCommand("INSERT INTO visits (day) VALUES ('0000-01-01')"),
    );
    final children = await db.holidays
        .select((h) => h.visits.select((v) => v.day).many())
        .single();
    if (children.single != LocalDate(0, 1, 1)) {
      throw StateError('Equivalent relation keys differ');
    }
    final catalog = await verifySchema(db, SchemaSnapshot(appSchema));
    if (catalog.differences.isNotEmpty || catalog.unmanaged.isNotEmpty) {
      throw StateError('Temporal catalog differs');
    }
    print(
      'Native temporal endpoints, ordering, streaming, relations and catalog verified.',
    );
  } finally {
    await db.close();
  }
}
