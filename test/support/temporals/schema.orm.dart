// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/orm.dart';

import "schema.dart" as models;

final _appointmentsId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _appointmentsDay = Column<LocalDate>(
  "day",
  Codecs.date,
  nullable: false,
  generated: false,
);
final _appointmentsTime = Column<LocalTime>(
  "time",
  Codecs.time,
  nullable: false,
  generated: false,
  defaultSql: "'12:30'",
);
final _appointmentsStarts = Column<LocalDateTime?>(
  "starts",
  Codecs.localDateTime.nullable(),
  nullable: true,
  generated: false,
);
final appointmentsSchema = TableSchema(
  "appointments",
  columns: [
    _appointmentsId,
    _appointmentsDay,
    _appointmentsTime,
    _appointmentsStarts,
  ],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class AppointmentsFields extends Fields {
  AppointmentsFields(super.table);
  late final id = column(_appointmentsId);
  late final day = column(_appointmentsDay);
  late final time = column(_appointmentsTime);
  late final starts = column(_appointmentsStarts);
}

final appointmentsTable = Table<models.Appointment, AppointmentsFields>(
  appointmentsSchema,
  AppointmentsFields.new,
  (row) => (row.id, row.day, row.time, row.starts).map(
    (id, day, time, starts) => (id: id, day: day, time: time, starts: starts),
  ),
);

final class AppointmentsTableSet
    extends TableSet<models.Appointment, AppointmentsFields> {
  AppointmentsTableSet(Database<Backend> db) : super(db, appointmentsTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Appointment> create({
    Change<int> id = const Change.keep(),
    required LocalDate day,
    Change<LocalTime> time = const Change.keep(),
    LocalDateTime? starts,
  }) => createRow(
    (row) => [
      ...row.id.change(id),
      row.day.set(day),
      ...row.time.change(time),
      row.starts.set(starts),
    ],
  );
  Query<models.Appointment, AppointmentsFields> byId(int id) =>
      where((row) => row.id.eq(id));
}

extension AppointmentsUpdates on Query<models.Appointment, AppointmentsFields> {
  Future<int> patch({
    Change<LocalDate> day = const Change.keep(),
    Change<LocalTime> time = const Change.keep(),
    Change<LocalDateTime?> starts = const Change.keep(),
  }) => update(
    (row) => [
      ...row.day.change(day),
      ...row.time.change(time),
      ...row.starts.change(starts),
    ],
  ).execute();
}

final _holidaysDay = Column<LocalDate>(
  "day",
  Codecs.date,
  nullable: false,
  generated: false,
);
final _holidaysLabel = Column<String>(
  "label",
  Codecs.text,
  nullable: false,
  generated: false,
);
final holidaysSchema = TableSchema(
  "holidays",
  columns: [_holidaysDay, _holidaysLabel],
  primaryKey: ["day"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class HolidaysFields extends Fields {
  HolidaysFields(super.table);
  late final day = column(_holidaysDay);
  late final label = column(_holidaysLabel);
  Relation<models.Visit, VisitsFields> get visits =>
      Relation(visitsTable, parent: [day], child: (row) => [row.day]);
}

final holidaysTable = Table<models.Holiday, HolidaysFields>(
  holidaysSchema,
  HolidaysFields.new,
  (row) => (row.day, row.label).map((day, label) => (day: day, label: label)),
);

final class HolidaysTableSet extends TableSet<models.Holiday, HolidaysFields> {
  HolidaysTableSet(Database<Backend> db) : super(db, holidaysTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Holiday> create({
    required LocalDate day,
    required String label,
  }) => createRow((row) => [row.day.set(day), row.label.set(label)]);
  Query<models.Holiday, HolidaysFields> byId(LocalDate day) =>
      where((row) => row.day.eq(day));
}

extension HolidaysUpdates on Query<models.Holiday, HolidaysFields> {
  Future<int> patch({
    Change<LocalDate> day = const Change.keep(),
    Change<String> label = const Change.keep(),
  }) =>
      update((row) => [...row.day.change(day), ...row.label.change(label)])
          .execute();
}

final _visitsId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _visitsDay = Column<LocalDate>(
  "day",
  Codecs.date,
  nullable: false,
  generated: false,
);
final visitsSchema = TableSchema(
  "visits",
  columns: [_visitsId, _visitsDay],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [
    ForeignKey(["day"], "holidays", ["day"], onDelete: "RESTRICT"),
  ],
);

final class VisitsFields extends Fields {
  VisitsFields(super.table);
  late final id = column(_visitsId);
  late final day = column(_visitsDay);
  Relation<models.Holiday, HolidaysFields> get holiday =>
      Relation(holidaysTable, parent: [day], child: (row) => [row.day]);
}

final visitsTable = Table<models.Visit, VisitsFields>(
  visitsSchema,
  VisitsFields.new,
  (row) => (row.id, row.day).map((id, day) => (id: id, day: day)),
);

final class VisitsTableSet extends TableSet<models.Visit, VisitsFields> {
  VisitsTableSet(Database<Backend> db) : super(db, visitsTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Visit> create({
    Change<int> id = const Change.keep(),
    required LocalDate day,
  }) => createRow((row) => [...row.id.change(id), row.day.set(day)]);
  Query<models.Visit, VisitsFields> byId(int id) =>
      where((row) => row.id.eq(id));
}

extension VisitsUpdates on Query<models.Visit, VisitsFields> {
  Future<int> patch({Change<LocalDate> day = const Change.keep()}) =>
      update((row) => [...row.day.change(day)]).execute();
}

final appSchema = <TableSchema>[
  appointmentsSchema,
  holidaysSchema,
  visitsSchema,
];

extension AppTables<B extends Backend> on Database<B> {
  AppointmentsTableSet get appointments => AppointmentsTableSet(this);
  HolidaysTableSet get holidays => HolidaysTableSet(this);
  VisitsTableSet get visits => VisitsTableSet(this);
}
