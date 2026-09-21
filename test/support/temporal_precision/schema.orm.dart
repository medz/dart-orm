// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';

/// A complete immutable row from "moments".
final class Moment({
  required final int id,
  required final LocalTime clock,
  required final LocalDateTime local,
  required final DateTime instant,
  required final LocalTime? optional,
  required final LocalTime defaulted,
  required final LocalTime rounded,
});
final _momentId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _momentClock = Column<LocalTime>(
  "clock",
  Codecs.time,
  nullable: false,
  generated: false,
  temporalPrecision: 3,
);
final _momentLocal = Column<LocalDateTime>(
  "local",
  Codecs.localDateTime,
  nullable: false,
  generated: false,
  temporalPrecision: 3,
);
final _momentInstant = Column<DateTime>(
  "instant",
  Codecs.dateTime,
  nullable: false,
  generated: false,
  temporalPrecision: 0,
);
final _momentOptional = Column<LocalTime?>(
  "optional",
  Codecs.time.nullable(),
  nullable: true,
  generated: false,
  temporalPrecision: 2,
);
final _momentDefaulted = Column<LocalTime>(
  "defaulted",
  Codecs.time,
  nullable: false,
  generated: false,
  defaultSql: "'23:59:59.9995'",
  temporalPrecision: 3,
);
final _momentRounded = Column<LocalTime>(
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
final momentSchema = TableSchema(
  "moments",
  columns: [
    _momentId,
    _momentClock,
    _momentLocal,
    _momentInstant,
    _momentOptional,
    _momentDefaulted,
    _momentRounded,
  ],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class MomentFields extends Fields {
  MomentFields(super.table);
  late final id = column(_momentId);
  late final clock = column(_momentClock);
  late final local = column(_momentLocal);
  late final instant = column(_momentInstant);
  late final optional = column(_momentOptional);
  late final defaulted = column(_momentDefaulted);
  late final rounded = readColumn(_momentRounded);
}

final momentTable = Table<Moment, MomentFields>(
  momentSchema,
  MomentFields.new,
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
        (left, right) => Moment(
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

final class MomentTableSet extends TableSet<Moment, MomentFields> {
  MomentTableSet(QueryContext db) : super(db, momentTable) {
    db.registerSchema(appSchema);
  }
  Future<Moment> create({
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
  Query<Moment, MomentFields> byId(int id) => where((row) => row.id.eq(id));
}

extension MomentUpdates on Query<Moment, MomentFields> {
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

/// A complete immutable row from "slots".
final class Slot({required final LocalTime time, required final String label});
final _slotTime = Column<LocalTime>(
  "time",
  Codecs.time,
  nullable: false,
  generated: false,
  temporalPrecision: 3,
);
final _slotLabel = Column<String>(
  "label",
  Codecs.text,
  nullable: false,
  generated: false,
);
final slotSchema = TableSchema(
  "slots",
  columns: [_slotTime, _slotLabel],
  primaryKey: ["time"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class SlotFields extends Fields {
  SlotFields(super.table);
  late final time = column(_slotTime);
  late final label = column(_slotLabel);
  Relation<Booking, BookingFields> get bookings =>
      Relation(bookingTable, parent: [time], child: (row) => [row.time]);
}

final slotTable = Table<Slot, SlotFields>(
  slotSchema,
  SlotFields.new,
  (row) => (row.time, row.label).map((v0, v1) => Slot(time: v0, label: v1)),
);

final class SlotTableSet extends TableSet<Slot, SlotFields> {
  SlotTableSet(QueryContext db) : super(db, slotTable) {
    db.registerSchema(appSchema);
  }
  Future<Slot> create({required LocalTime time, required String label}) =>
      createRow((row) => [row.time.set(time), row.label.set(label)]);
  Query<Slot, SlotFields> byId(LocalTime time) =>
      where((row) => row.time.eq(time));
}

extension SlotUpdates on Query<Slot, SlotFields> {
  Future<int> patch({
    Change<LocalTime> time = const Change.keep(),
    Change<String> label = const Change.keep(),
  }) =>
      update((row) => [...row.time.change(time), ...row.label.change(label)])
          .execute();
}

/// A complete immutable row from "bookings".
final class Booking({required final int id, required final LocalTime time});
final _bookingId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _bookingTime = Column<LocalTime>(
  "time",
  Codecs.time,
  nullable: false,
  generated: false,
  temporalPrecision: 3,
);
final bookingSchema = TableSchema(
  "bookings",
  columns: [_bookingId, _bookingTime],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [
    ForeignKey(["time"], "slots", ["time"], onDelete: "RESTRICT"),
  ],
);

final class BookingFields extends Fields {
  BookingFields(super.table);
  late final id = column(_bookingId);
  late final time = column(_bookingTime);
  Relation<Slot, SlotFields> get slot =>
      Relation(slotTable, parent: [time], child: (row) => [row.time]);
}

final bookingTable = Table<Booking, BookingFields>(
  bookingSchema,
  BookingFields.new,
  (row) => (row.id, row.time).map((v0, v1) => Booking(id: v0, time: v1)),
);

final class BookingTableSet extends TableSet<Booking, BookingFields> {
  BookingTableSet(QueryContext db) : super(db, bookingTable) {
    db.registerSchema(appSchema);
  }
  Future<Booking> create({
    Change<int> id = const Change.keep(),
    required LocalTime time,
  }) => createRow((row) => [...row.id.change(id), row.time.set(time)]);
  Query<Booking, BookingFields> byId(int id) => where((row) => row.id.eq(id));
}

extension BookingUpdates on Query<Booking, BookingFields> {
  Future<int> patch({Change<LocalTime> time = const Change.keep()}) =>
      update((row) => [...row.time.change(time)]).execute();
}

final appSchema = List<TableSchema>.unmodifiable([
  momentSchema,
  slotSchema,
  bookingSchema,
]);

extension AppTables on QueryContext {
  MomentTableSet get moment => MomentTableSet(this);
  SlotTableSet get slot => SlotTableSet(this);
  BookingTableSet get booking => BookingTableSet(this);
}
