// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/orm.dart' as orm_model show ModelTable, ModelQuery;
import 'package:orm/values.dart';

import "schema.dart" as models;
export "schema.dart" show Appointment, Holiday, Visit;

final class _OrmWriteAbsent {
  const _OrmWriteAbsent();
}

const _writeAbsent = _OrmWriteAbsent();
WriteValue<T, F> _writeLiteral<T, F extends Fields>(Object? value) =>
    identical(value, _writeAbsent) ? const .keep() : .set(value as T);

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

/// Immutable input data; composition belongs to [appointmentPatch], not field names.
final class AppointmentPatch {
  final WriteValue<LocalDate, AppointmentFields> day;
  final WriteValue<LocalTime, AppointmentFields> time;
  final WriteValue<LocalDateTime?, AppointmentFields> starts;
  AppointmentPatch._({
    required this.day,
    required this.time,
    required this.starts,
  });

  List<Assignment> _assignments(AppointmentFields fields) => [
    ...fields.day.write(day, fields),
    ...fields.time.write(time, fields),
    ...fields.starts.write(starts, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class AppointmentPatchFactory {
  AppointmentPatch call({LocalDate day, LocalTime time, LocalDateTime? starts});
  AppointmentPatch values({
    WriteValue<LocalDate, AppointmentFields> day = const .keep(),
    WriteValue<LocalTime, AppointmentFields> time = const .keep(),
    WriteValue<LocalDateTime?, AppointmentFields> starts = const .keep(),
  });
  AppointmentPatch overlay(Iterable<AppointmentPatch> layers);
  bool isEmpty(AppointmentPatch input);
}

const AppointmentPatchFactory appointmentPatch = _AppointmentPatchFactory();

final class _AppointmentPatchFactory implements AppointmentPatchFactory {
  const _AppointmentPatchFactory();
  @override
  AppointmentPatch call({
    Object? day = _writeAbsent,
    Object? time = _writeAbsent,
    Object? starts = _writeAbsent,
  }) => AppointmentPatch._(
    day: _writeLiteral<LocalDate, AppointmentFields>(day),
    time: _writeLiteral<LocalTime, AppointmentFields>(time),
    starts: _writeLiteral<LocalDateTime?, AppointmentFields>(starts),
  );
  @override
  AppointmentPatch values({
    WriteValue<LocalDate, AppointmentFields> day = const .keep(),
    WriteValue<LocalTime, AppointmentFields> time = const .keep(),
    WriteValue<LocalDateTime?, AppointmentFields> starts = const .keep(),
  }) => AppointmentPatch._(day: day, time: time, starts: starts);
  @override
  AppointmentPatch overlay(Iterable<AppointmentPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = AppointmentPatch._(
        day: WriteValue.overlay(earlier.day, later.day),
        time: WriteValue.overlay(earlier.time, later.time),
        starts: WriteValue.overlay(earlier.starts, later.starts),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(AppointmentPatch input) =>
      input.day.isMissing && input.time.isMissing && input.starts.isMissing;
}

/// Immutable input data; composition belongs to [appointmentInsert], not field names.
final class AppointmentInsert {
  final WriteValue<int, AppointmentFields> id;
  final WriteValue<LocalDate, AppointmentFields> day;
  final WriteValue<LocalTime, AppointmentFields> time;
  final WriteValue<LocalDateTime?, AppointmentFields> starts;
  AppointmentInsert._({
    required this.id,
    required this.day,
    required this.time,
    required this.starts,
  }) {
    if (day.isMissing) {
      throw ArgumentError.value(day, 'day', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(AppointmentFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.day.write(day, fields),
    ...fields.time.write(time, fields),
    ...fields.starts.write(starts, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class AppointmentInsertFactory {
  AppointmentInsert call({
    int id,
    required LocalDate day,
    LocalTime time,
    LocalDateTime? starts,
  });
  AppointmentInsert values({
    WriteValue<int, AppointmentFields> id = const .keep(),
    required WriteValue<LocalDate, AppointmentFields> day,
    WriteValue<LocalTime, AppointmentFields> time = const .keep(),
    WriteValue<LocalDateTime?, AppointmentFields> starts = const .keep(),
  });
  AppointmentInsert overlay(
    AppointmentInsert earlier,
    Iterable<AppointmentPatch> layers,
  );
}

const AppointmentInsertFactory appointmentInsert = _AppointmentInsertFactory();

final class _AppointmentInsertFactory implements AppointmentInsertFactory {
  const _AppointmentInsertFactory();
  @override
  AppointmentInsert call({
    Object? id = _writeAbsent,
    required LocalDate day,
    Object? time = _writeAbsent,
    Object? starts = _writeAbsent,
  }) => AppointmentInsert._(
    id: _writeLiteral<int, AppointmentFields>(id),
    day: .set(day),
    time: _writeLiteral<LocalTime, AppointmentFields>(time),
    starts: _writeLiteral<LocalDateTime?, AppointmentFields>(starts),
  );
  @override
  AppointmentInsert values({
    WriteValue<int, AppointmentFields> id = const .keep(),
    required WriteValue<LocalDate, AppointmentFields> day,
    WriteValue<LocalTime, AppointmentFields> time = const .keep(),
    WriteValue<LocalDateTime?, AppointmentFields> starts = const .keep(),
  }) => AppointmentInsert._(id: id, day: day, time: time, starts: starts);
  @override
  AppointmentInsert overlay(
    AppointmentInsert earlier,
    Iterable<AppointmentPatch> layers,
  ) {
    for (final later in layers) {
      earlier = AppointmentInsert._(
        id: earlier.id,
        day: WriteValue.overlay(earlier.day, later.day),
        time: WriteValue.overlay(earlier.time, later.time),
        starts: WriteValue.overlay(earlier.starts, later.starts),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Appointment from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class AppointmentCreator {
  Future<models.Appointment> call({
    int id,
    required LocalDate day,
    LocalTime time,
    LocalDateTime? starts,
  });
}

final class _AppointmentCreator implements AppointmentCreator {
  final AppointmentTableSet _table;
  const _AppointmentCreator(this._table);
  @override
  Future<models.Appointment> call({
    Object? id = _writeAbsent,
    required LocalDate day,
    Object? time = _writeAbsent,
    Object? starts = _writeAbsent,
  }) async => _table.plan
      .insert(
        AppointmentInsert._(
          id: _writeLiteral<int, AppointmentFields>(id),
          day: .set(day),
          time: _writeLiteral<LocalTime, AppointmentFields>(time),
          starts: _writeLiteral<LocalDateTime?, AppointmentFields>(starts),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class AppointmentPatcher {
  Future<int> call({LocalDate day, LocalTime time, LocalDateTime? starts});
}

final class _AppointmentPatcher implements AppointmentPatcher {
  final orm_model.ModelQuery<
    models.Appointment,
    AppointmentFields,
    AppointmentPatch
  >
  _query;
  const _AppointmentPatcher(this._query);
  @override
  Future<int> call({
    Object? day = _writeAbsent,
    Object? time = _writeAbsent,
    Object? starts = _writeAbsent,
  }) => _query.update(
    AppointmentPatch._(
      day: _writeLiteral<LocalDate, AppointmentFields>(day),
      time: _writeLiteral<LocalTime, AppointmentFields>(time),
      starts: _writeLiteral<LocalDateTime?, AppointmentFields>(starts),
    ),
  );
}

/// Named literal updates on a complete models.Appointment query.
extension AppointmentWrites
    on
        orm_model.ModelQuery<
          models.Appointment,
          AppointmentFields,
          AppointmentPatch
        > {
  /// Executes one update; omitted fields remain unchanged.
  AppointmentPatcher get patch => _AppointmentPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class AppointmentTableSet
    extends
        orm_model.ModelTable<
          models.Appointment,
          AppointmentFields,
          AppointmentInsert,
          AppointmentPatch
        > {
  AppointmentTableSet(QueryContext db)
    : super(
        db,
        appointmentTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final AppointmentCreator create = _AppointmentCreator(this);

  orm_model.ModelQuery<models.Appointment, AppointmentFields, AppointmentPatch>
  byId(int id) => where((row) => row.id.eq(.value(id)));
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

/// Immutable input data; composition belongs to [holidayPatch], not field names.
final class HolidayPatch {
  final WriteValue<LocalDate, HolidayFields> day;
  final WriteValue<String, HolidayFields> label;
  HolidayPatch._({required this.day, required this.label});

  List<Assignment> _assignments(HolidayFields fields) => [
    ...fields.day.write(day, fields),
    ...fields.label.write(label, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class HolidayPatchFactory {
  HolidayPatch call({LocalDate day, String label});
  HolidayPatch values({
    WriteValue<LocalDate, HolidayFields> day = const .keep(),
    WriteValue<String, HolidayFields> label = const .keep(),
  });
  HolidayPatch overlay(Iterable<HolidayPatch> layers);
  bool isEmpty(HolidayPatch input);
}

const HolidayPatchFactory holidayPatch = _HolidayPatchFactory();

final class _HolidayPatchFactory implements HolidayPatchFactory {
  const _HolidayPatchFactory();
  @override
  HolidayPatch call({
    Object? day = _writeAbsent,
    Object? label = _writeAbsent,
  }) => HolidayPatch._(
    day: _writeLiteral<LocalDate, HolidayFields>(day),
    label: _writeLiteral<String, HolidayFields>(label),
  );
  @override
  HolidayPatch values({
    WriteValue<LocalDate, HolidayFields> day = const .keep(),
    WriteValue<String, HolidayFields> label = const .keep(),
  }) => HolidayPatch._(day: day, label: label);
  @override
  HolidayPatch overlay(Iterable<HolidayPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = HolidayPatch._(
        day: WriteValue.overlay(earlier.day, later.day),
        label: WriteValue.overlay(earlier.label, later.label),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(HolidayPatch input) =>
      input.day.isMissing && input.label.isMissing;
}

/// Immutable input data; composition belongs to [holidayInsert], not field names.
final class HolidayInsert {
  final WriteValue<LocalDate, HolidayFields> day;
  final WriteValue<String, HolidayFields> label;
  HolidayInsert._({required this.day, required this.label}) {
    if (day.isMissing) {
      throw ArgumentError.value(day, 'day', 'Must be supplied.');
    }
    if (label.isMissing) {
      throw ArgumentError.value(label, 'label', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(HolidayFields fields) => [
    ...fields.day.write(day, fields),
    ...fields.label.write(label, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class HolidayInsertFactory {
  HolidayInsert call({required LocalDate day, required String label});
  HolidayInsert values({
    required WriteValue<LocalDate, HolidayFields> day,
    required WriteValue<String, HolidayFields> label,
  });
  HolidayInsert overlay(HolidayInsert earlier, Iterable<HolidayPatch> layers);
}

const HolidayInsertFactory holidayInsert = _HolidayInsertFactory();

final class _HolidayInsertFactory implements HolidayInsertFactory {
  const _HolidayInsertFactory();
  @override
  HolidayInsert call({required LocalDate day, required String label}) =>
      HolidayInsert._(day: .set(day), label: .set(label));
  @override
  HolidayInsert values({
    required WriteValue<LocalDate, HolidayFields> day,
    required WriteValue<String, HolidayFields> label,
  }) => HolidayInsert._(day: day, label: label);
  @override
  HolidayInsert overlay(HolidayInsert earlier, Iterable<HolidayPatch> layers) {
    for (final later in layers) {
      earlier = HolidayInsert._(
        day: WriteValue.overlay(earlier.day, later.day),
        label: WriteValue.overlay(earlier.label, later.label),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Holiday from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class HolidayCreator {
  Future<models.Holiday> call({required LocalDate day, required String label});
}

final class _HolidayCreator implements HolidayCreator {
  final HolidayTableSet _table;
  const _HolidayCreator(this._table);
  @override
  Future<models.Holiday> call({
    required LocalDate day,
    required String label,
  }) async => _table.plan
      .insert(HolidayInsert._(day: .set(day), label: .set(label)))
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class HolidayPatcher {
  Future<int> call({LocalDate day, String label});
}

final class _HolidayPatcher implements HolidayPatcher {
  final orm_model.ModelQuery<models.Holiday, HolidayFields, HolidayPatch>
  _query;
  const _HolidayPatcher(this._query);
  @override
  Future<int> call({
    Object? day = _writeAbsent,
    Object? label = _writeAbsent,
  }) => _query.update(
    HolidayPatch._(
      day: _writeLiteral<LocalDate, HolidayFields>(day),
      label: _writeLiteral<String, HolidayFields>(label),
    ),
  );
}

/// Named literal updates on a complete models.Holiday query.
extension HolidayWrites
    on orm_model.ModelQuery<models.Holiday, HolidayFields, HolidayPatch> {
  /// Executes one update; omitted fields remain unchanged.
  HolidayPatcher get patch => _HolidayPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class HolidayTableSet
    extends
        orm_model.ModelTable<
          models.Holiday,
          HolidayFields,
          HolidayInsert,
          HolidayPatch
        > {
  HolidayTableSet(QueryContext db)
    : super(
        db,
        holidayTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final HolidayCreator create = _HolidayCreator(this);

  orm_model.ModelQuery<models.Holiday, HolidayFields, HolidayPatch> byId(
    LocalDate day,
  ) => where((row) => row.day.eq(.value(day)));
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

/// Immutable input data; composition belongs to [visitPatch], not field names.
final class VisitPatch {
  final WriteValue<LocalDate, VisitFields> day;
  VisitPatch._({required this.day});

  List<Assignment> _assignments(VisitFields fields) => [
    ...fields.day.write(day, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class VisitPatchFactory {
  VisitPatch call({LocalDate day});
  VisitPatch values({WriteValue<LocalDate, VisitFields> day = const .keep()});
  VisitPatch overlay(Iterable<VisitPatch> layers);
  bool isEmpty(VisitPatch input);
}

const VisitPatchFactory visitPatch = _VisitPatchFactory();

final class _VisitPatchFactory implements VisitPatchFactory {
  const _VisitPatchFactory();
  @override
  VisitPatch call({Object? day = _writeAbsent}) =>
      VisitPatch._(day: _writeLiteral<LocalDate, VisitFields>(day));
  @override
  VisitPatch values({WriteValue<LocalDate, VisitFields> day = const .keep()}) =>
      VisitPatch._(day: day);
  @override
  VisitPatch overlay(Iterable<VisitPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = VisitPatch._(day: WriteValue.overlay(earlier.day, later.day));
    }
    return earlier;
  }

  @override
  bool isEmpty(VisitPatch input) => input.day.isMissing;
}

/// Immutable input data; composition belongs to [visitInsert], not field names.
final class VisitInsert {
  final WriteValue<int, VisitFields> id;
  final WriteValue<LocalDate, VisitFields> day;
  VisitInsert._({required this.id, required this.day}) {
    if (day.isMissing) {
      throw ArgumentError.value(day, 'day', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(VisitFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.day.write(day, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class VisitInsertFactory {
  VisitInsert call({int id, required LocalDate day});
  VisitInsert values({
    WriteValue<int, VisitFields> id = const .keep(),
    required WriteValue<LocalDate, VisitFields> day,
  });
  VisitInsert overlay(VisitInsert earlier, Iterable<VisitPatch> layers);
}

const VisitInsertFactory visitInsert = _VisitInsertFactory();

final class _VisitInsertFactory implements VisitInsertFactory {
  const _VisitInsertFactory();
  @override
  VisitInsert call({Object? id = _writeAbsent, required LocalDate day}) =>
      VisitInsert._(id: _writeLiteral<int, VisitFields>(id), day: .set(day));
  @override
  VisitInsert values({
    WriteValue<int, VisitFields> id = const .keep(),
    required WriteValue<LocalDate, VisitFields> day,
  }) => VisitInsert._(id: id, day: day);
  @override
  VisitInsert overlay(VisitInsert earlier, Iterable<VisitPatch> layers) {
    for (final later in layers) {
      earlier = VisitInsert._(
        id: earlier.id,
        day: WriteValue.overlay(earlier.day, later.day),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Visit from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class VisitCreator {
  Future<models.Visit> call({int id, required LocalDate day});
}

final class _VisitCreator implements VisitCreator {
  final VisitTableSet _table;
  const _VisitCreator(this._table);
  @override
  Future<models.Visit> call({
    Object? id = _writeAbsent,
    required LocalDate day,
  }) async => _table.plan
      .insert(
        VisitInsert._(id: _writeLiteral<int, VisitFields>(id), day: .set(day)),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class VisitPatcher {
  Future<int> call({LocalDate day});
}

final class _VisitPatcher implements VisitPatcher {
  final orm_model.ModelQuery<models.Visit, VisitFields, VisitPatch> _query;
  const _VisitPatcher(this._query);
  @override
  Future<int> call({Object? day = _writeAbsent}) => _query.update(
    VisitPatch._(day: _writeLiteral<LocalDate, VisitFields>(day)),
  );
}

/// Named literal updates on a complete models.Visit query.
extension VisitWrites
    on orm_model.ModelQuery<models.Visit, VisitFields, VisitPatch> {
  /// Executes one update; omitted fields remain unchanged.
  VisitPatcher get patch => _VisitPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class VisitTableSet
    extends
        orm_model.ModelTable<
          models.Visit,
          VisitFields,
          VisitInsert,
          VisitPatch
        > {
  VisitTableSet(QueryContext db)
    : super(
        db,
        visitTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final VisitCreator create = _VisitCreator(this);

  orm_model.ModelQuery<models.Visit, VisitFields, VisitPatch> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
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
