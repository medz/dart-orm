// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/orm.dart' as orm_model show ModelTable, ModelQuery;
import 'package:orm/values.dart';

import "schema.dart" as models;
export "schema.dart" show Moment, Slot, Booking;

final class _OrmWriteAbsent {
  const _OrmWriteAbsent();
}

const _writeAbsent = _OrmWriteAbsent();
WriteValue<T, F> _writeLiteral<T, F extends Fields>(Object? value) =>
    identical(value, _writeAbsent) ? const .keep() : .set(value as T);

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
  Relation<models.Slot, SlotFields> get slot =>
      Relation(slotTable, parent: [time], child: (row) => [row.time]);
}

final bookingTable = Table<models.Booking, BookingFields>(
  bookingSchema,
  BookingFields.new,
  (row) => (row.id, row.time).map((v0, v1) => models.Booking(id: v0, time: v1)),
);

/// Immutable input data; composition belongs to [bookingPatch], not field names.
final class BookingPatch {
  final WriteValue<LocalTime, BookingFields> time;
  BookingPatch._({required this.time});

  List<Assignment> _assignments(BookingFields fields) => [
    ...fields.time.write(time, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class BookingPatchFactory {
  BookingPatch call({LocalTime time});
  BookingPatch values({
    WriteValue<LocalTime, BookingFields> time = const .keep(),
  });
  BookingPatch overlay(Iterable<BookingPatch> layers);
  bool isEmpty(BookingPatch input);
}

const BookingPatchFactory bookingPatch = _BookingPatchFactory();

final class _BookingPatchFactory implements BookingPatchFactory {
  const _BookingPatchFactory();
  @override
  BookingPatch call({Object? time = _writeAbsent}) =>
      BookingPatch._(time: _writeLiteral<LocalTime, BookingFields>(time));
  @override
  BookingPatch values({
    WriteValue<LocalTime, BookingFields> time = const .keep(),
  }) => BookingPatch._(time: time);
  @override
  BookingPatch overlay(Iterable<BookingPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = BookingPatch._(
        time: WriteValue.overlay(earlier.time, later.time),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(BookingPatch input) => input.time.isMissing;
}

/// Immutable input data; composition belongs to [bookingInsert], not field names.
final class BookingInsert {
  final WriteValue<int, BookingFields> id;
  final WriteValue<LocalTime, BookingFields> time;
  BookingInsert._({required this.id, required this.time}) {
    if (time.isMissing) {
      throw ArgumentError.value(time, 'time', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(BookingFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.time.write(time, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class BookingInsertFactory {
  BookingInsert call({int id, required LocalTime time});
  BookingInsert values({
    WriteValue<int, BookingFields> id = const .keep(),
    required WriteValue<LocalTime, BookingFields> time,
  });
  BookingInsert overlay(BookingInsert earlier, Iterable<BookingPatch> layers);
}

const BookingInsertFactory bookingInsert = _BookingInsertFactory();

final class _BookingInsertFactory implements BookingInsertFactory {
  const _BookingInsertFactory();
  @override
  BookingInsert call({Object? id = _writeAbsent, required LocalTime time}) =>
      BookingInsert._(
        id: _writeLiteral<int, BookingFields>(id),
        time: .set(time),
      );
  @override
  BookingInsert values({
    WriteValue<int, BookingFields> id = const .keep(),
    required WriteValue<LocalTime, BookingFields> time,
  }) => BookingInsert._(id: id, time: time);
  @override
  BookingInsert overlay(BookingInsert earlier, Iterable<BookingPatch> layers) {
    for (final later in layers) {
      earlier = BookingInsert._(
        id: earlier.id,
        time: WriteValue.overlay(earlier.time, later.time),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Booking from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class BookingCreator {
  Future<models.Booking> call({int id, required LocalTime time});
}

final class _BookingCreator implements BookingCreator {
  final BookingTableSet _table;
  const _BookingCreator(this._table);
  @override
  Future<models.Booking> call({
    Object? id = _writeAbsent,
    required LocalTime time,
  }) async => _table.plan
      .insert(
        BookingInsert._(
          id: _writeLiteral<int, BookingFields>(id),
          time: .set(time),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class BookingPatcher {
  Future<int> call({LocalTime time});
}

final class _BookingPatcher implements BookingPatcher {
  final orm_model.ModelQuery<models.Booking, BookingFields, BookingPatch>
  _query;
  const _BookingPatcher(this._query);
  @override
  Future<int> call({Object? time = _writeAbsent}) => _query.update(
    BookingPatch._(time: _writeLiteral<LocalTime, BookingFields>(time)),
  );
}

/// Named literal updates on a complete models.Booking query.
extension BookingWrites
    on orm_model.ModelQuery<models.Booking, BookingFields, BookingPatch> {
  /// Executes one update; omitted fields remain unchanged.
  BookingPatcher get patch => _BookingPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class BookingTableSet
    extends
        orm_model.ModelTable<
          models.Booking,
          BookingFields,
          BookingInsert,
          BookingPatch
        > {
  BookingTableSet(QueryContext db)
    : super(
        db,
        bookingTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final BookingCreator create = _BookingCreator(this);

  orm_model.ModelQuery<models.Booking, BookingFields, BookingPatch> byId(
    int id,
  ) => where((row) => row.id.eq(.value(id)));
}

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

final momentTable = Table<models.Moment, MomentFields>(
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
        (left, right) => models.Moment(
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

/// Immutable input data; composition belongs to [momentPatch], not field names.
final class MomentPatch {
  final WriteValue<LocalTime, MomentFields> clock;
  final WriteValue<LocalDateTime, MomentFields> local;
  final WriteValue<DateTime, MomentFields> instant;
  final WriteValue<LocalTime?, MomentFields> optional;
  final WriteValue<LocalTime, MomentFields> defaulted;
  MomentPatch._({
    required this.clock,
    required this.local,
    required this.instant,
    required this.optional,
    required this.defaulted,
  });

  List<Assignment> _assignments(MomentFields fields) => [
    ...fields.clock.write(clock, fields),
    ...fields.local.write(local, fields),
    ...fields.instant.write(instant, fields),
    ...fields.optional.write(optional, fields),
    ...fields.defaulted.write(defaulted, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class MomentPatchFactory {
  MomentPatch call({
    LocalTime clock,
    LocalDateTime local,
    DateTime instant,
    LocalTime? optional,
    LocalTime defaulted,
  });
  MomentPatch values({
    WriteValue<LocalTime, MomentFields> clock = const .keep(),
    WriteValue<LocalDateTime, MomentFields> local = const .keep(),
    WriteValue<DateTime, MomentFields> instant = const .keep(),
    WriteValue<LocalTime?, MomentFields> optional = const .keep(),
    WriteValue<LocalTime, MomentFields> defaulted = const .keep(),
  });
  MomentPatch overlay(Iterable<MomentPatch> layers);
  bool isEmpty(MomentPatch input);
}

const MomentPatchFactory momentPatch = _MomentPatchFactory();

final class _MomentPatchFactory implements MomentPatchFactory {
  const _MomentPatchFactory();
  @override
  MomentPatch call({
    Object? clock = _writeAbsent,
    Object? local = _writeAbsent,
    Object? instant = _writeAbsent,
    Object? optional = _writeAbsent,
    Object? defaulted = _writeAbsent,
  }) => MomentPatch._(
    clock: _writeLiteral<LocalTime, MomentFields>(clock),
    local: _writeLiteral<LocalDateTime, MomentFields>(local),
    instant: _writeLiteral<DateTime, MomentFields>(instant),
    optional: _writeLiteral<LocalTime?, MomentFields>(optional),
    defaulted: _writeLiteral<LocalTime, MomentFields>(defaulted),
  );
  @override
  MomentPatch values({
    WriteValue<LocalTime, MomentFields> clock = const .keep(),
    WriteValue<LocalDateTime, MomentFields> local = const .keep(),
    WriteValue<DateTime, MomentFields> instant = const .keep(),
    WriteValue<LocalTime?, MomentFields> optional = const .keep(),
    WriteValue<LocalTime, MomentFields> defaulted = const .keep(),
  }) => MomentPatch._(
    clock: clock,
    local: local,
    instant: instant,
    optional: optional,
    defaulted: defaulted,
  );
  @override
  MomentPatch overlay(Iterable<MomentPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = MomentPatch._(
        clock: WriteValue.overlay(earlier.clock, later.clock),
        local: WriteValue.overlay(earlier.local, later.local),
        instant: WriteValue.overlay(earlier.instant, later.instant),
        optional: WriteValue.overlay(earlier.optional, later.optional),
        defaulted: WriteValue.overlay(earlier.defaulted, later.defaulted),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(MomentPatch input) =>
      input.clock.isMissing &&
      input.local.isMissing &&
      input.instant.isMissing &&
      input.optional.isMissing &&
      input.defaulted.isMissing;
}

/// Immutable input data; composition belongs to [momentInsert], not field names.
final class MomentInsert {
  final WriteValue<int, MomentFields> id;
  final WriteValue<LocalTime, MomentFields> clock;
  final WriteValue<LocalDateTime, MomentFields> local;
  final WriteValue<DateTime, MomentFields> instant;
  final WriteValue<LocalTime?, MomentFields> optional;
  final WriteValue<LocalTime, MomentFields> defaulted;
  MomentInsert._({
    required this.id,
    required this.clock,
    required this.local,
    required this.instant,
    required this.optional,
    required this.defaulted,
  }) {
    if (clock.isMissing) {
      throw ArgumentError.value(clock, 'clock', 'Must be supplied.');
    }
    if (local.isMissing) {
      throw ArgumentError.value(local, 'local', 'Must be supplied.');
    }
    if (instant.isMissing) {
      throw ArgumentError.value(instant, 'instant', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(MomentFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.clock.write(clock, fields),
    ...fields.local.write(local, fields),
    ...fields.instant.write(instant, fields),
    ...fields.optional.write(optional, fields),
    ...fields.defaulted.write(defaulted, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class MomentInsertFactory {
  MomentInsert call({
    int id,
    required LocalTime clock,
    required LocalDateTime local,
    required DateTime instant,
    LocalTime? optional,
    LocalTime defaulted,
  });
  MomentInsert values({
    WriteValue<int, MomentFields> id = const .keep(),
    required WriteValue<LocalTime, MomentFields> clock,
    required WriteValue<LocalDateTime, MomentFields> local,
    required WriteValue<DateTime, MomentFields> instant,
    WriteValue<LocalTime?, MomentFields> optional = const .keep(),
    WriteValue<LocalTime, MomentFields> defaulted = const .keep(),
  });
  MomentInsert overlay(MomentInsert earlier, Iterable<MomentPatch> layers);
}

const MomentInsertFactory momentInsert = _MomentInsertFactory();

final class _MomentInsertFactory implements MomentInsertFactory {
  const _MomentInsertFactory();
  @override
  MomentInsert call({
    Object? id = _writeAbsent,
    required LocalTime clock,
    required LocalDateTime local,
    required DateTime instant,
    Object? optional = _writeAbsent,
    Object? defaulted = _writeAbsent,
  }) => MomentInsert._(
    id: _writeLiteral<int, MomentFields>(id),
    clock: .set(clock),
    local: .set(local),
    instant: .set(instant),
    optional: _writeLiteral<LocalTime?, MomentFields>(optional),
    defaulted: _writeLiteral<LocalTime, MomentFields>(defaulted),
  );
  @override
  MomentInsert values({
    WriteValue<int, MomentFields> id = const .keep(),
    required WriteValue<LocalTime, MomentFields> clock,
    required WriteValue<LocalDateTime, MomentFields> local,
    required WriteValue<DateTime, MomentFields> instant,
    WriteValue<LocalTime?, MomentFields> optional = const .keep(),
    WriteValue<LocalTime, MomentFields> defaulted = const .keep(),
  }) => MomentInsert._(
    id: id,
    clock: clock,
    local: local,
    instant: instant,
    optional: optional,
    defaulted: defaulted,
  );
  @override
  MomentInsert overlay(MomentInsert earlier, Iterable<MomentPatch> layers) {
    for (final later in layers) {
      earlier = MomentInsert._(
        id: earlier.id,
        clock: WriteValue.overlay(earlier.clock, later.clock),
        local: WriteValue.overlay(earlier.local, later.local),
        instant: WriteValue.overlay(earlier.instant, later.instant),
        optional: WriteValue.overlay(earlier.optional, later.optional),
        defaulted: WriteValue.overlay(earlier.defaulted, later.defaulted),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Moment from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class MomentCreator {
  Future<models.Moment> call({
    int id,
    required LocalTime clock,
    required LocalDateTime local,
    required DateTime instant,
    LocalTime? optional,
    LocalTime defaulted,
  });
}

final class _MomentCreator implements MomentCreator {
  final MomentTableSet _table;
  const _MomentCreator(this._table);
  @override
  Future<models.Moment> call({
    Object? id = _writeAbsent,
    required LocalTime clock,
    required LocalDateTime local,
    required DateTime instant,
    Object? optional = _writeAbsent,
    Object? defaulted = _writeAbsent,
  }) async => _table.plan
      .insert(
        MomentInsert._(
          id: _writeLiteral<int, MomentFields>(id),
          clock: .set(clock),
          local: .set(local),
          instant: .set(instant),
          optional: _writeLiteral<LocalTime?, MomentFields>(optional),
          defaulted: _writeLiteral<LocalTime, MomentFields>(defaulted),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class MomentPatcher {
  Future<int> call({
    LocalTime clock,
    LocalDateTime local,
    DateTime instant,
    LocalTime? optional,
    LocalTime defaulted,
  });
}

final class _MomentPatcher implements MomentPatcher {
  final orm_model.ModelQuery<models.Moment, MomentFields, MomentPatch> _query;
  const _MomentPatcher(this._query);
  @override
  Future<int> call({
    Object? clock = _writeAbsent,
    Object? local = _writeAbsent,
    Object? instant = _writeAbsent,
    Object? optional = _writeAbsent,
    Object? defaulted = _writeAbsent,
  }) => _query.update(
    MomentPatch._(
      clock: _writeLiteral<LocalTime, MomentFields>(clock),
      local: _writeLiteral<LocalDateTime, MomentFields>(local),
      instant: _writeLiteral<DateTime, MomentFields>(instant),
      optional: _writeLiteral<LocalTime?, MomentFields>(optional),
      defaulted: _writeLiteral<LocalTime, MomentFields>(defaulted),
    ),
  );
}

/// Named literal updates on a complete models.Moment query.
extension MomentWrites
    on orm_model.ModelQuery<models.Moment, MomentFields, MomentPatch> {
  /// Executes one update; omitted fields remain unchanged.
  MomentPatcher get patch => _MomentPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class MomentTableSet
    extends
        orm_model.ModelTable<
          models.Moment,
          MomentFields,
          MomentInsert,
          MomentPatch
        > {
  MomentTableSet(QueryContext db)
    : super(
        db,
        momentTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final MomentCreator create = _MomentCreator(this);

  orm_model.ModelQuery<models.Moment, MomentFields, MomentPatch> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

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

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Booking, BookingFields> get bookings =>
      Relation(bookingTable, parent: [time], child: (row) => [row.time]);
}

final slotTable = Table<models.Slot, SlotFields>(
  slotSchema,
  SlotFields.new,
  (row) =>
      (row.time, row.label).map((v0, v1) => models.Slot(time: v0, label: v1)),
);

/// Immutable input data; composition belongs to [slotPatch], not field names.
final class SlotPatch {
  final WriteValue<LocalTime, SlotFields> time;
  final WriteValue<String, SlotFields> label;
  SlotPatch._({required this.time, required this.label});

  List<Assignment> _assignments(SlotFields fields) => [
    ...fields.time.write(time, fields),
    ...fields.label.write(label, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class SlotPatchFactory {
  SlotPatch call({LocalTime time, String label});
  SlotPatch values({
    WriteValue<LocalTime, SlotFields> time = const .keep(),
    WriteValue<String, SlotFields> label = const .keep(),
  });
  SlotPatch overlay(Iterable<SlotPatch> layers);
  bool isEmpty(SlotPatch input);
}

const SlotPatchFactory slotPatch = _SlotPatchFactory();

final class _SlotPatchFactory implements SlotPatchFactory {
  const _SlotPatchFactory();
  @override
  SlotPatch call({Object? time = _writeAbsent, Object? label = _writeAbsent}) =>
      SlotPatch._(
        time: _writeLiteral<LocalTime, SlotFields>(time),
        label: _writeLiteral<String, SlotFields>(label),
      );
  @override
  SlotPatch values({
    WriteValue<LocalTime, SlotFields> time = const .keep(),
    WriteValue<String, SlotFields> label = const .keep(),
  }) => SlotPatch._(time: time, label: label);
  @override
  SlotPatch overlay(Iterable<SlotPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = SlotPatch._(
        time: WriteValue.overlay(earlier.time, later.time),
        label: WriteValue.overlay(earlier.label, later.label),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(SlotPatch input) =>
      input.time.isMissing && input.label.isMissing;
}

/// Immutable input data; composition belongs to [slotInsert], not field names.
final class SlotInsert {
  final WriteValue<LocalTime, SlotFields> time;
  final WriteValue<String, SlotFields> label;
  SlotInsert._({required this.time, required this.label}) {
    if (time.isMissing) {
      throw ArgumentError.value(time, 'time', 'Must be supplied.');
    }
    if (label.isMissing) {
      throw ArgumentError.value(label, 'label', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(SlotFields fields) => [
    ...fields.time.write(time, fields),
    ...fields.label.write(label, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class SlotInsertFactory {
  SlotInsert call({required LocalTime time, required String label});
  SlotInsert values({
    required WriteValue<LocalTime, SlotFields> time,
    required WriteValue<String, SlotFields> label,
  });
  SlotInsert overlay(SlotInsert earlier, Iterable<SlotPatch> layers);
}

const SlotInsertFactory slotInsert = _SlotInsertFactory();

final class _SlotInsertFactory implements SlotInsertFactory {
  const _SlotInsertFactory();
  @override
  SlotInsert call({required LocalTime time, required String label}) =>
      SlotInsert._(time: .set(time), label: .set(label));
  @override
  SlotInsert values({
    required WriteValue<LocalTime, SlotFields> time,
    required WriteValue<String, SlotFields> label,
  }) => SlotInsert._(time: time, label: label);
  @override
  SlotInsert overlay(SlotInsert earlier, Iterable<SlotPatch> layers) {
    for (final later in layers) {
      earlier = SlotInsert._(
        time: WriteValue.overlay(earlier.time, later.time),
        label: WriteValue.overlay(earlier.label, later.label),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Slot from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class SlotCreator {
  Future<models.Slot> call({required LocalTime time, required String label});
}

final class _SlotCreator implements SlotCreator {
  final SlotTableSet _table;
  const _SlotCreator(this._table);
  @override
  Future<models.Slot> call({
    required LocalTime time,
    required String label,
  }) async => _table.plan
      .insert(SlotInsert._(time: .set(time), label: .set(label)))
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class SlotPatcher {
  Future<int> call({LocalTime time, String label});
}

final class _SlotPatcher implements SlotPatcher {
  final orm_model.ModelQuery<models.Slot, SlotFields, SlotPatch> _query;
  const _SlotPatcher(this._query);
  @override
  Future<int> call({
    Object? time = _writeAbsent,
    Object? label = _writeAbsent,
  }) => _query.update(
    SlotPatch._(
      time: _writeLiteral<LocalTime, SlotFields>(time),
      label: _writeLiteral<String, SlotFields>(label),
    ),
  );
}

/// Named literal updates on a complete models.Slot query.
extension SlotWrites
    on orm_model.ModelQuery<models.Slot, SlotFields, SlotPatch> {
  /// Executes one update; omitted fields remain unchanged.
  SlotPatcher get patch => _SlotPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class SlotTableSet
    extends
        orm_model.ModelTable<models.Slot, SlotFields, SlotInsert, SlotPatch> {
  SlotTableSet(QueryContext db)
    : super(
        db,
        slotTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final SlotCreator create = _SlotCreator(this);

  orm_model.ModelQuery<models.Slot, SlotFields, SlotPatch> byId(
    LocalTime time,
  ) => where((row) => row.time.eq(.value(time)));
}

final appSchema = List<TableSchema>.unmodifiable([
  bookingSchema,
  momentSchema,
  slotSchema,
]);

extension AppTables on QueryContext {
  BookingTableSet get booking => BookingTableSet(this);
  MomentTableSet get moment => MomentTableSet(this);
  SlotTableSet get slot => SlotTableSet(this);
}
