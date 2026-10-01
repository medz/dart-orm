// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';

import "schema.dart" as models;
export "schema.dart" show Appointment, Holiday, Visit;

final _appointmentId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _appointmentDay = Column<LocalDate>(
  "day",
  Codecs.date,
  nullable: false,
  generated: false,
);
final _appointmentTime = Column<LocalTime>(
  "time",
  Codecs.time,
  nullable: false,
  generated: false,
  defaultSql: "'12:30'",
);
final _appointmentStarts = Column<LocalDateTime?>(
  "starts",
  Codecs.localDateTime.nullable(),
  nullable: true,
  generated: false,
);
final appointmentSchema = TableSchema(
  "appointments",
  columns: [
    _appointmentId,
    _appointmentDay,
    _appointmentTime,
    _appointmentStarts,
  ],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class AppointmentFields extends Fields {
  AppointmentFields(super.table);
  late final id = column(_appointmentId);
  late final day = column(_appointmentDay);
  late final time = column(_appointmentTime);
  late final starts = column(_appointmentStarts);
}

final appointmentTable = Table<models.Appointment, AppointmentFields>(
  appointmentSchema,
  AppointmentFields.new,
  (row) => (row.id, row.day, row.time, row.starts).map(
    (v0, v1, v2, v3) =>
        models.Appointment(id: v0, day: v1, time: v2, starts: v3),
  ),
);

final class AppointmentTableSet
    extends TableSet<models.Appointment, AppointmentFields> {
  AppointmentTableSet(QueryContext db) : super(db, appointmentTable) {
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
  Query<models.Appointment, AppointmentFields> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

extension AppointmentUpdates on Query<models.Appointment, AppointmentFields> {
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

final _holidayDay = Column<LocalDate>(
  "day",
  Codecs.date,
  nullable: false,
  generated: false,
);
final _holidayLabel = Column<String>(
  "label",
  Codecs.text,
  nullable: false,
  generated: false,
);
final holidaySchema = TableSchema(
  "holidays",
  columns: [_holidayDay, _holidayLabel],
  primaryKey: ["day"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class HolidayFields extends Fields {
  HolidayFields(super.table);
  late final day = column(_holidayDay);
  late final label = column(_holidayLabel);

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Visit, VisitFields> get visits =>
      Relation(visitTable, parent: [day], child: (row) => [row.day]);
}

final holidayTable = Table<models.Holiday, HolidayFields>(
  holidaySchema,
  HolidayFields.new,
  (row) =>
      (row.day, row.label).map((v0, v1) => models.Holiday(day: v0, label: v1)),
);

final class HolidayTableSet extends TableSet<models.Holiday, HolidayFields> {
  HolidayTableSet(QueryContext db) : super(db, holidayTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Holiday> create({
    required LocalDate day,
    required String label,
  }) => createRow((row) => [row.day.set(day), row.label.set(label)]);
  Query<models.Holiday, HolidayFields> byId(LocalDate day) =>
      where((row) => row.day.eq(.value(day)));
}

extension HolidayUpdates on Query<models.Holiday, HolidayFields> {
  Future<int> patch({
    Change<LocalDate> day = const Change.keep(),
    Change<String> label = const Change.keep(),
  }) =>
      update((row) => [...row.day.change(day), ...row.label.change(label)])
          .execute();
}

final _visitId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _visitDay = Column<LocalDate>(
  "day",
  Codecs.date,
  nullable: false,
  generated: false,
);
final visitSchema = TableSchema(
  "visits",
  columns: [_visitId, _visitDay],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [
    ForeignKey(["day"], "holidays", ["day"], onDelete: "RESTRICT"),
  ],
);

final class VisitFields extends Fields {
  VisitFields(super.table);
  late final id = column(_visitId);
  late final day = column(_visitDay);
  Relation<models.Holiday, HolidayFields> get holiday =>
      Relation(holidayTable, parent: [day], child: (row) => [row.day]);
}

final visitTable = Table<models.Visit, VisitFields>(
  visitSchema,
  VisitFields.new,
  (row) => (row.id, row.day).map((v0, v1) => models.Visit(id: v0, day: v1)),
);

final class VisitTableSet extends TableSet<models.Visit, VisitFields> {
  VisitTableSet(QueryContext db) : super(db, visitTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Visit> create({
    Change<int> id = const Change.keep(),
    required LocalDate day,
  }) => createRow((row) => [...row.id.change(id), row.day.set(day)]);
  Query<models.Visit, VisitFields> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

extension VisitUpdates on Query<models.Visit, VisitFields> {
  Future<int> patch({Change<LocalDate> day = const Change.keep()}) =>
      update((row) => [...row.day.change(day)]).execute();
}

final appSchema = List<TableSchema>.unmodifiable([
  appointmentSchema,
  holidaySchema,
  visitSchema,
]);

extension AppTables on QueryContext {
  AppointmentTableSet get appointment => AppointmentTableSet(this);
  HolidayTableSet get holiday => HolidayTableSet(this);
  VisitTableSet get visit => VisitTableSet(this);
}
