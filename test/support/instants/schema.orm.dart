// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/orm.dart' as orm_model show ModelTable, ModelQuery;
import 'package:orm/values.dart';

import "schema.dart" as models;
export "schema.dart" show Event, Moment, Link;

final class _OrmWriteAbsent {
  const _OrmWriteAbsent();
}

const _writeAbsent = _OrmWriteAbsent();
WriteValue<T, F> _writeLiteral<T, F extends Fields>(Object? value) =>
    identical(value, _writeAbsent) ? const .keep() : .set(value as T);

final _eventId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _eventAt = Column<DateTime>(
  "at",
  Codecs.dateTime,
  nullable: false,
  generated: false,
);
final _eventCreated = Column<DateTime>(
  "created",
  Codecs.dateTime,
  nullable: false,
  generated: false,
  defaultSql: "CURRENT_TIMESTAMP",
);
final _eventOptional = Column<DateTime?>(
  "optional",
  Codecs.dateTime.nullable(),
  nullable: true,
  generated: false,
);
final eventSchema = TableSchema(
  "events",
  columns: [_eventId, _eventAt, _eventCreated, _eventOptional],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class EventFields extends Fields {
  EventFields(super.table);
  late final id = column(_eventId);
  late final at = column(_eventAt);
  late final created = column(_eventCreated);
  late final optional = column(_eventOptional);
}

final eventTable = Table<models.Event, EventFields>(
  eventSchema,
  EventFields.new,
  (row) => (row.id, row.at, row.created, row.optional).map(
    (v0, v1, v2, v3) => models.Event(id: v0, at: v1, created: v2, optional: v3),
  ),
);

/// Immutable input data; composition belongs to [eventPatch], not field names.
final class EventPatch {
  final WriteValue<DateTime, EventFields> at;
  final WriteValue<DateTime, EventFields> created;
  final WriteValue<DateTime?, EventFields> optional;
  EventPatch._({
    required this.at,
    required this.created,
    required this.optional,
  });

  List<Assignment> _assignments(EventFields fields) => [
    ...fields.at.write(at, fields),
    ...fields.created.write(created, fields),
    ...fields.optional.write(optional, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class EventPatchFactory {
  EventPatch call({DateTime at, DateTime created, DateTime? optional});
  EventPatch values({
    WriteValue<DateTime, EventFields> at = const .keep(),
    WriteValue<DateTime, EventFields> created = const .keep(),
    WriteValue<DateTime?, EventFields> optional = const .keep(),
  });
  EventPatch overlay(Iterable<EventPatch> layers);
  bool isEmpty(EventPatch input);
}

const EventPatchFactory eventPatch = _EventPatchFactory();

final class _EventPatchFactory implements EventPatchFactory {
  const _EventPatchFactory();
  @override
  EventPatch call({
    Object? at = _writeAbsent,
    Object? created = _writeAbsent,
    Object? optional = _writeAbsent,
  }) => EventPatch._(
    at: _writeLiteral<DateTime, EventFields>(at),
    created: _writeLiteral<DateTime, EventFields>(created),
    optional: _writeLiteral<DateTime?, EventFields>(optional),
  );
  @override
  EventPatch values({
    WriteValue<DateTime, EventFields> at = const .keep(),
    WriteValue<DateTime, EventFields> created = const .keep(),
    WriteValue<DateTime?, EventFields> optional = const .keep(),
  }) => EventPatch._(at: at, created: created, optional: optional);
  @override
  EventPatch overlay(Iterable<EventPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = EventPatch._(
        at: WriteValue.overlay(earlier.at, later.at),
        created: WriteValue.overlay(earlier.created, later.created),
        optional: WriteValue.overlay(earlier.optional, later.optional),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(EventPatch input) =>
      input.at.isMissing && input.created.isMissing && input.optional.isMissing;
}

/// Immutable input data; composition belongs to [eventInsert], not field names.
final class EventInsert {
  final WriteValue<int, EventFields> id;
  final WriteValue<DateTime, EventFields> at;
  final WriteValue<DateTime, EventFields> created;
  final WriteValue<DateTime?, EventFields> optional;
  EventInsert._({
    required this.id,
    required this.at,
    required this.created,
    required this.optional,
  }) {
    if (at.isMissing) {
      throw ArgumentError.value(at, 'at', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(EventFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.at.write(at, fields),
    ...fields.created.write(created, fields),
    ...fields.optional.write(optional, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class EventInsertFactory {
  EventInsert call({
    int id,
    required DateTime at,
    DateTime created,
    DateTime? optional,
  });
  EventInsert values({
    WriteValue<int, EventFields> id = const .keep(),
    required WriteValue<DateTime, EventFields> at,
    WriteValue<DateTime, EventFields> created = const .keep(),
    WriteValue<DateTime?, EventFields> optional = const .keep(),
  });
  EventInsert overlay(EventInsert earlier, Iterable<EventPatch> layers);
}

const EventInsertFactory eventInsert = _EventInsertFactory();

final class _EventInsertFactory implements EventInsertFactory {
  const _EventInsertFactory();
  @override
  EventInsert call({
    Object? id = _writeAbsent,
    required DateTime at,
    Object? created = _writeAbsent,
    Object? optional = _writeAbsent,
  }) => EventInsert._(
    id: _writeLiteral<int, EventFields>(id),
    at: .set(at),
    created: _writeLiteral<DateTime, EventFields>(created),
    optional: _writeLiteral<DateTime?, EventFields>(optional),
  );
  @override
  EventInsert values({
    WriteValue<int, EventFields> id = const .keep(),
    required WriteValue<DateTime, EventFields> at,
    WriteValue<DateTime, EventFields> created = const .keep(),
    WriteValue<DateTime?, EventFields> optional = const .keep(),
  }) => EventInsert._(id: id, at: at, created: created, optional: optional);
  @override
  EventInsert overlay(EventInsert earlier, Iterable<EventPatch> layers) {
    for (final later in layers) {
      earlier = EventInsert._(
        id: earlier.id,
        at: WriteValue.overlay(earlier.at, later.at),
        created: WriteValue.overlay(earlier.created, later.created),
        optional: WriteValue.overlay(earlier.optional, later.optional),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Event from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class EventCreator {
  Future<models.Event> call({
    int id,
    required DateTime at,
    DateTime created,
    DateTime? optional,
  });
}

final class _EventCreator implements EventCreator {
  final EventTableSet _table;
  const _EventCreator(this._table);
  @override
  Future<models.Event> call({
    Object? id = _writeAbsent,
    required DateTime at,
    Object? created = _writeAbsent,
    Object? optional = _writeAbsent,
  }) async => _table.plan
      .insert(
        EventInsert._(
          id: _writeLiteral<int, EventFields>(id),
          at: .set(at),
          created: _writeLiteral<DateTime, EventFields>(created),
          optional: _writeLiteral<DateTime?, EventFields>(optional),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class EventPatcher {
  Future<int> call({DateTime at, DateTime created, DateTime? optional});
}

final class _EventPatcher implements EventPatcher {
  final orm_model.ModelQuery<models.Event, EventFields, EventPatch> _query;
  const _EventPatcher(this._query);
  @override
  Future<int> call({
    Object? at = _writeAbsent,
    Object? created = _writeAbsent,
    Object? optional = _writeAbsent,
  }) => _query.update(
    EventPatch._(
      at: _writeLiteral<DateTime, EventFields>(at),
      created: _writeLiteral<DateTime, EventFields>(created),
      optional: _writeLiteral<DateTime?, EventFields>(optional),
    ),
  );
}

/// Named literal updates on a complete models.Event query.
extension EventWrites
    on orm_model.ModelQuery<models.Event, EventFields, EventPatch> {
  /// Executes one update; omitted fields remain unchanged.
  EventPatcher get patch => _EventPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class EventTableSet
    extends
        orm_model.ModelTable<
          models.Event,
          EventFields,
          EventInsert,
          EventPatch
        > {
  EventTableSet(QueryContext db)
    : super(
        db,
        eventTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final EventCreator create = _EventCreator(this);

  orm_model.ModelQuery<models.Event, EventFields, EventPatch> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

final _linkId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _linkAt = Column<DateTime>(
  "at",
  Codecs.dateTime,
  nullable: false,
  generated: false,
);
final linkSchema = TableSchema(
  "links",
  columns: [_linkId, _linkAt],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [
    ForeignKey(["at"], "moments", ["at"], onDelete: "RESTRICT"),
  ],
);

final class LinkFields extends Fields {
  LinkFields(super.table);
  late final id = column(_linkId);
  late final at = column(_linkAt);
  Relation<models.Moment, MomentFields> get moment =>
      Relation(momentTable, parent: [at], child: (row) => [row.at]);
}

final linkTable = Table<models.Link, LinkFields>(
  linkSchema,
  LinkFields.new,
  (row) => (row.id, row.at).map((v0, v1) => models.Link(id: v0, at: v1)),
);

/// Immutable input data; composition belongs to [linkPatch], not field names.
final class LinkPatch {
  final WriteValue<DateTime, LinkFields> at;
  LinkPatch._({required this.at});

  List<Assignment> _assignments(LinkFields fields) => [
    ...fields.at.write(at, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class LinkPatchFactory {
  LinkPatch call({DateTime at});
  LinkPatch values({WriteValue<DateTime, LinkFields> at = const .keep()});
  LinkPatch overlay(Iterable<LinkPatch> layers);
  bool isEmpty(LinkPatch input);
}

const LinkPatchFactory linkPatch = _LinkPatchFactory();

final class _LinkPatchFactory implements LinkPatchFactory {
  const _LinkPatchFactory();
  @override
  LinkPatch call({Object? at = _writeAbsent}) =>
      LinkPatch._(at: _writeLiteral<DateTime, LinkFields>(at));
  @override
  LinkPatch values({WriteValue<DateTime, LinkFields> at = const .keep()}) =>
      LinkPatch._(at: at);
  @override
  LinkPatch overlay(Iterable<LinkPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = LinkPatch._(at: WriteValue.overlay(earlier.at, later.at));
    }
    return earlier;
  }

  @override
  bool isEmpty(LinkPatch input) => input.at.isMissing;
}

/// Immutable input data; composition belongs to [linkInsert], not field names.
final class LinkInsert {
  final WriteValue<int, LinkFields> id;
  final WriteValue<DateTime, LinkFields> at;
  LinkInsert._({required this.id, required this.at}) {
    if (at.isMissing) {
      throw ArgumentError.value(at, 'at', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(LinkFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.at.write(at, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class LinkInsertFactory {
  LinkInsert call({int id, required DateTime at});
  LinkInsert values({
    WriteValue<int, LinkFields> id = const .keep(),
    required WriteValue<DateTime, LinkFields> at,
  });
  LinkInsert overlay(LinkInsert earlier, Iterable<LinkPatch> layers);
}

const LinkInsertFactory linkInsert = _LinkInsertFactory();

final class _LinkInsertFactory implements LinkInsertFactory {
  const _LinkInsertFactory();
  @override
  LinkInsert call({Object? id = _writeAbsent, required DateTime at}) =>
      LinkInsert._(id: _writeLiteral<int, LinkFields>(id), at: .set(at));
  @override
  LinkInsert values({
    WriteValue<int, LinkFields> id = const .keep(),
    required WriteValue<DateTime, LinkFields> at,
  }) => LinkInsert._(id: id, at: at);
  @override
  LinkInsert overlay(LinkInsert earlier, Iterable<LinkPatch> layers) {
    for (final later in layers) {
      earlier = LinkInsert._(
        id: earlier.id,
        at: WriteValue.overlay(earlier.at, later.at),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Link from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class LinkCreator {
  Future<models.Link> call({int id, required DateTime at});
}

final class _LinkCreator implements LinkCreator {
  final LinkTableSet _table;
  const _LinkCreator(this._table);
  @override
  Future<models.Link> call({
    Object? id = _writeAbsent,
    required DateTime at,
  }) async => _table.plan
      .insert(
        LinkInsert._(id: _writeLiteral<int, LinkFields>(id), at: .set(at)),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class LinkPatcher {
  Future<int> call({DateTime at});
}

final class _LinkPatcher implements LinkPatcher {
  final orm_model.ModelQuery<models.Link, LinkFields, LinkPatch> _query;
  const _LinkPatcher(this._query);
  @override
  Future<int> call({Object? at = _writeAbsent}) =>
      _query.update(LinkPatch._(at: _writeLiteral<DateTime, LinkFields>(at)));
}

/// Named literal updates on a complete models.Link query.
extension LinkWrites
    on orm_model.ModelQuery<models.Link, LinkFields, LinkPatch> {
  /// Executes one update; omitted fields remain unchanged.
  LinkPatcher get patch => _LinkPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class LinkTableSet
    extends
        orm_model.ModelTable<models.Link, LinkFields, LinkInsert, LinkPatch> {
  LinkTableSet(QueryContext db)
    : super(
        db,
        linkTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final LinkCreator create = _LinkCreator(this);

  orm_model.ModelQuery<models.Link, LinkFields, LinkPatch> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

final _momentAt = Column<DateTime>(
  "at",
  Codecs.dateTime,
  nullable: false,
  generated: false,
);
final _momentLabel = Column<String>(
  "label",
  Codecs.text,
  nullable: false,
  generated: false,
  defaultSql: "'pending'",
);
final momentSchema = TableSchema(
  "moments",
  columns: [_momentAt, _momentLabel],
  primaryKey: ["at"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class MomentFields extends Fields {
  MomentFields(super.table);
  late final at = column(_momentAt);
  late final label = column(_momentLabel);

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Link, LinkFields> get links =>
      Relation(linkTable, parent: [at], child: (row) => [row.at]);
}

final momentTable = Table<models.Moment, MomentFields>(
  momentSchema,
  MomentFields.new,
  (row) =>
      (row.at, row.label).map((v0, v1) => models.Moment(at: v0, label: v1)),
);

/// Immutable input data; composition belongs to [momentPatch], not field names.
final class MomentPatch {
  final WriteValue<DateTime, MomentFields> at;
  final WriteValue<String, MomentFields> label;
  MomentPatch._({required this.at, required this.label});

  List<Assignment> _assignments(MomentFields fields) => [
    ...fields.at.write(at, fields),
    ...fields.label.write(label, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class MomentPatchFactory {
  MomentPatch call({DateTime at, String label});
  MomentPatch values({
    WriteValue<DateTime, MomentFields> at = const .keep(),
    WriteValue<String, MomentFields> label = const .keep(),
  });
  MomentPatch overlay(Iterable<MomentPatch> layers);
  bool isEmpty(MomentPatch input);
}

const MomentPatchFactory momentPatch = _MomentPatchFactory();

final class _MomentPatchFactory implements MomentPatchFactory {
  const _MomentPatchFactory();
  @override
  MomentPatch call({Object? at = _writeAbsent, Object? label = _writeAbsent}) =>
      MomentPatch._(
        at: _writeLiteral<DateTime, MomentFields>(at),
        label: _writeLiteral<String, MomentFields>(label),
      );
  @override
  MomentPatch values({
    WriteValue<DateTime, MomentFields> at = const .keep(),
    WriteValue<String, MomentFields> label = const .keep(),
  }) => MomentPatch._(at: at, label: label);
  @override
  MomentPatch overlay(Iterable<MomentPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = MomentPatch._(
        at: WriteValue.overlay(earlier.at, later.at),
        label: WriteValue.overlay(earlier.label, later.label),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(MomentPatch input) =>
      input.at.isMissing && input.label.isMissing;
}

/// Immutable input data; composition belongs to [momentInsert], not field names.
final class MomentInsert {
  final WriteValue<DateTime, MomentFields> at;
  final WriteValue<String, MomentFields> label;
  MomentInsert._({required this.at, required this.label}) {
    if (at.isMissing) {
      throw ArgumentError.value(at, 'at', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(MomentFields fields) => [
    ...fields.at.write(at, fields),
    ...fields.label.write(label, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class MomentInsertFactory {
  MomentInsert call({required DateTime at, String label});
  MomentInsert values({
    required WriteValue<DateTime, MomentFields> at,
    WriteValue<String, MomentFields> label = const .keep(),
  });
  MomentInsert overlay(MomentInsert earlier, Iterable<MomentPatch> layers);
}

const MomentInsertFactory momentInsert = _MomentInsertFactory();

final class _MomentInsertFactory implements MomentInsertFactory {
  const _MomentInsertFactory();
  @override
  MomentInsert call({required DateTime at, Object? label = _writeAbsent}) =>
      MomentInsert._(
        at: .set(at),
        label: _writeLiteral<String, MomentFields>(label),
      );
  @override
  MomentInsert values({
    required WriteValue<DateTime, MomentFields> at,
    WriteValue<String, MomentFields> label = const .keep(),
  }) => MomentInsert._(at: at, label: label);
  @override
  MomentInsert overlay(MomentInsert earlier, Iterable<MomentPatch> layers) {
    for (final later in layers) {
      earlier = MomentInsert._(
        at: WriteValue.overlay(earlier.at, later.at),
        label: WriteValue.overlay(earlier.label, later.label),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Moment from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class MomentCreator {
  Future<models.Moment> call({required DateTime at, String label});
}

final class _MomentCreator implements MomentCreator {
  final MomentTableSet _table;
  const _MomentCreator(this._table);
  @override
  Future<models.Moment> call({
    required DateTime at,
    Object? label = _writeAbsent,
  }) async => _table.plan
      .insert(
        MomentInsert._(
          at: .set(at),
          label: _writeLiteral<String, MomentFields>(label),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class MomentPatcher {
  Future<int> call({DateTime at, String label});
}

final class _MomentPatcher implements MomentPatcher {
  final orm_model.ModelQuery<models.Moment, MomentFields, MomentPatch> _query;
  const _MomentPatcher(this._query);
  @override
  Future<int> call({Object? at = _writeAbsent, Object? label = _writeAbsent}) =>
      _query.update(
        MomentPatch._(
          at: _writeLiteral<DateTime, MomentFields>(at),
          label: _writeLiteral<String, MomentFields>(label),
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

  orm_model.ModelQuery<models.Moment, MomentFields, MomentPatch> byId(
    DateTime at,
  ) => where((row) => row.at.eq(.value(at)));
}

final appSchema = List<TableSchema>.unmodifiable([
  eventSchema,
  linkSchema,
  momentSchema,
]);

extension AppTables on QueryContext {
  EventTableSet get event => EventTableSet(this);
  LinkTableSet get link => LinkTableSet(this);
  MomentTableSet get moment => MomentTableSet(this);
}
