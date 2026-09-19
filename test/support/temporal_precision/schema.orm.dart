// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';

import "schema.dart" as models;
export "schema.dart" show Moment, Slot, Booking;

final _momentsId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _momentsClock = Column<LocalTime>(
  "clock",
  Codecs.time,
  nullable: false,
  generated: false,
  temporalPrecision: 3,
);
final _momentsLocal = Column<LocalDateTime>(
  "local",
  Codecs.localDateTime,
  nullable: false,
  generated: false,
  temporalPrecision: 3,
);
final _momentsInstant = Column<DateTime>(
  "instant",
  Codecs.dateTime,
  nullable: false,
  generated: false,
  temporalPrecision: 0,
);
final _momentsOptional = Column<LocalTime?>(
  "optional",
  Codecs.time.nullable(),
  nullable: true,
  generated: false,
  temporalPrecision: 2,
);
final _momentsDefaulted = Column<LocalTime>(
  "defaulted",
  Codecs.time,
  nullable: false,
  generated: false,
  defaultSql: "'23:59:59.9995'",
  temporalPrecision: 3,
);
final _momentsRounded = Column<LocalTime>(
  "rounded",
  Codecs.time,
  nullable: false,
  generated: false,
  computed: ComputedColumn.forDialects(
    sqlite: "\"clock\"",
    postgres: "\"clock\"",
    mysql: "\"clock\"",
    mariadb: "\"clock\"",
    storage: ComputedStorage.stored,
  ),
  temporalPrecision: 0,
);
final momentsSchema = TableSchema(
  "moments",
  columns: [
    _momentsId,
    _momentsClock,
    _momentsLocal,
    _momentsInstant,
    _momentsOptional,
    _momentsDefaulted,
    _momentsRounded,
  ],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class MomentsFields extends Fields {
  MomentsFields(super.table);
  late final id = column(_momentsId);
  late final clock = column(_momentsClock);
  late final local = column(_momentsLocal);
  late final instant = column(_momentsInstant);
  late final optional = column(_momentsOptional);
  late final defaulted = column(_momentsDefaulted);
  late final rounded = readColumn(_momentsRounded);
}

final momentsTable = Table<models.Moment, MomentsFields>(
  momentsSchema,
  MomentsFields.new,
  (row) =>
      (
        (row.id, row.clock, row.local, row.instant, row.optional).map(
          (id, clock, local, instant, optional) => (
            id: id,
            clock: clock,
            local: local,
            instant: instant,
            optional: optional,
          ),
        ),
        (
          row.defaulted,
          row.rounded,
        ).map((defaulted, rounded) => (defaulted: defaulted, rounded: rounded)),
      ).map(
        (left, right) => (
          id: left.id,
          clock: left.clock,
          local: left.local,
          instant: left.instant,
          optional: left.optional,
          defaulted: right.defaulted,
          rounded: right.rounded,
        ),
      ),
);

final class MomentsTableSet extends TableSet<models.Moment, MomentsFields> {
  MomentsTableSet(QueryContext db) : super(db, momentsTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Moment> create({
    Change<int> id = const Change.keep(),
    required LocalTime clock,
    required LocalDateTime local,
    required DateTime instant,
    LocalTime? optional,
    Change<LocalTime> defaulted = const Change.keep(),
  }) => createRow(
    (row) => [
      ...row.id.change(id),
      row.clock.set(clock),
      row.local.set(local),
      row.instant.set(instant),
      row.optional.set(optional),
      ...row.defaulted.change(defaulted),
    ],
  );
  Query<models.Moment, MomentsFields> byId(int id) =>
      where((row) => row.id.eq(id));
}

extension MomentsUpdates on Query<models.Moment, MomentsFields> {
  Future<int> patch({
    Change<LocalTime> clock = const Change.keep(),
    Change<LocalDateTime> local = const Change.keep(),
    Change<DateTime> instant = const Change.keep(),
    Change<LocalTime?> optional = const Change.keep(),
    Change<LocalTime> defaulted = const Change.keep(),
  }) => update(
    (row) => [
      ...row.clock.change(clock),
      ...row.local.change(local),
      ...row.instant.change(instant),
      ...row.optional.change(optional),
      ...row.defaulted.change(defaulted),
    ],
  ).execute();
}

final _slotsTime = Column<LocalTime>(
  "time",
  Codecs.time,
  nullable: false,
  generated: false,
  temporalPrecision: 3,
);
final _slotsLabel = Column<String>(
  "label",
  Codecs.text,
  nullable: false,
  generated: false,
);
final slotsSchema = TableSchema(
  "slots",
  columns: [_slotsTime, _slotsLabel],
  primaryKey: ["time"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class SlotsFields extends Fields {
  SlotsFields(super.table);
  late final time = column(_slotsTime);
  late final label = column(_slotsLabel);
  Relation<models.Booking, BookingsFields> get bookings =>
      Relation(bookingsTable, parent: [time], child: (row) => [row.time]);
}

final slotsTable = Table<models.Slot, SlotsFields>(
  slotsSchema,
  SlotsFields.new,
  (row) =>
      (row.time, row.label).map((time, label) => (time: time, label: label)),
);

final class SlotsTableSet extends TableSet<models.Slot, SlotsFields> {
  SlotsTableSet(QueryContext db) : super(db, slotsTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Slot> create({
    required LocalTime time,
    required String label,
  }) => createRow((row) => [row.time.set(time), row.label.set(label)]);
  Query<models.Slot, SlotsFields> byId(LocalTime time) =>
      where((row) => row.time.eq(time));
}

extension SlotsUpdates on Query<models.Slot, SlotsFields> {
  Future<int> patch({
    Change<LocalTime> time = const Change.keep(),
    Change<String> label = const Change.keep(),
  }) =>
      update((row) => [...row.time.change(time), ...row.label.change(label)])
          .execute();
}

final _bookingsId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _bookingsTime = Column<LocalTime>(
  "time",
  Codecs.time,
  nullable: false,
  generated: false,
  temporalPrecision: 3,
);
final bookingsSchema = TableSchema(
  "bookings",
  columns: [_bookingsId, _bookingsTime],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [
    ForeignKey(["time"], "slots", ["time"], onDelete: "RESTRICT"),
  ],
);

final class BookingsFields extends Fields {
  BookingsFields(super.table);
  late final id = column(_bookingsId);
  late final time = column(_bookingsTime);
  Relation<models.Slot, SlotsFields> get slot =>
      Relation(slotsTable, parent: [time], child: (row) => [row.time]);
}

final bookingsTable = Table<models.Booking, BookingsFields>(
  bookingsSchema,
  BookingsFields.new,
  (row) => (row.id, row.time).map((id, time) => (id: id, time: time)),
);

final class BookingsTableSet extends TableSet<models.Booking, BookingsFields> {
  BookingsTableSet(QueryContext db) : super(db, bookingsTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Booking> create({
    Change<int> id = const Change.keep(),
    required LocalTime time,
  }) => createRow((row) => [...row.id.change(id), row.time.set(time)]);
  Query<models.Booking, BookingsFields> byId(int id) =>
      where((row) => row.id.eq(id));
}

extension BookingsUpdates on Query<models.Booking, BookingsFields> {
  Future<int> patch({Change<LocalTime> time = const Change.keep()}) =>
      update((row) => [...row.time.change(time)]).execute();
}

final appSchema = List<TableSchema>.unmodifiable([
  momentsSchema,
  slotsSchema,
  bookingsSchema,
]);

extension AppTables on QueryContext {
  MomentsTableSet get moments => MomentsTableSet(this);
  SlotsTableSet get slots => SlotsTableSet(this);
  BookingsTableSet get bookings => BookingsTableSet(this);
}
