// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/orm.dart' as orm_model show ModelTable, ModelQuery;
import 'package:orm/values.dart';
import 'package:orm/sql.dart' as orm show allOf;

import "schema.dart" as models;
export "schema.dart" show Account, Event;

final class _OrmWriteAbsent {
  const _OrmWriteAbsent();
}

const _writeAbsent = _OrmWriteAbsent();
WriteValue<T, F> _writeLiteral<T, F extends Fields>(Object? value) =>
    identical(value, _writeAbsent) ? const .keep() : .set(value as T);

final _accountTenant = Column<int>(
  "tenant",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _accountId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _accountLabel = Column<String?>(
  "label",
  Codecs.text.nullable(),
  nullable: true,
  generated: false,
);
final _accountNote = Column<String?>(
  "note",
  Codecs.text.nullable(),
  nullable: true,
  generated: false,
);
final _accountManagerId = Column<int?>(
  "manager_id",
  Codecs.integer.nullable(),
  nullable: true,
  generated: false,
);
final _accountMarker = Column<String?>(
  "_ORM_PRESENT",
  Codecs.text.nullable(),
  nullable: true,
  generated: false,
);
final accountSchema = TableSchema(
  "accounts",
  columns: [
    _accountTenant,
    _accountId,
    _accountLabel,
    _accountNote,
    _accountManagerId,
    _accountMarker,
  ],
  primaryKey: ["tenant", "id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [
    ForeignKey(
      ["tenant", "manager_id"],
      "accounts",
      ["tenant", "id"],
      onDelete: "RESTRICT",
    ),
  ],
);

final class AccountFields extends Fields {
  AccountFields(super.table);
  late final tenant = column(_accountTenant);
  late final id = column(_accountId);
  late final label = column(_accountLabel);
  late final note = column(_accountNote);
  late final managerId = column(_accountManagerId);
  late final marker = column(_accountMarker);
  Relation<models.Account, AccountFields> get manager => Relation(
    accountTable,
    parent: [tenant, managerId],
    child: (row) => [row.tenant, row.id],
  );

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Account, AccountFields> get reports => Relation(
    accountTable,
    parent: [tenant, id],
    child: (row) => [row.tenant, row.managerId],
  );

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Event, EventFields> get events => Relation(
    eventTable,
    parent: [tenant, id],
    child: (row) => [row.tenant, row.owner],
  );

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Event, EventFields> get reviews => Relation(
    eventTable,
    parent: [tenant, id],
    child: (row) => [row.tenant, row.reviewer],
  );
}

final accountTable = Table<models.Account, AccountFields>(
  accountSchema,
  AccountFields.new,
  (row) =>
      (row.tenant, row.id, row.label, row.note, row.managerId, row.marker).map(
        (v0, v1, v2, v3, v4, v5) => models.Account(
          tenant: v0,
          id: v1,
          label: v2,
          note: v3,
          managerId: v4,
          marker: v5,
        ),
      ),
);

/// Immutable input data; composition belongs to [accountPatch], not field names.
final class AccountPatch {
  final WriteValue<int, AccountFields> tenant;
  final WriteValue<int, AccountFields> id;
  final WriteValue<String?, AccountFields> label;
  final WriteValue<String?, AccountFields> note;
  final WriteValue<int?, AccountFields> managerId;
  final WriteValue<String?, AccountFields> marker;
  AccountPatch._({
    required this.tenant,
    required this.id,
    required this.label,
    required this.note,
    required this.managerId,
    required this.marker,
  });

  List<Assignment> _assignments(AccountFields fields) => [
    ...fields.tenant.write(tenant, fields),
    ...fields.id.write(id, fields),
    ...fields.label.write(label, fields),
    ...fields.note.write(note, fields),
    ...fields.managerId.write(managerId, fields),
    ...fields.marker.write(marker, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class AccountPatchFactory {
  AccountPatch call({
    int tenant,
    int id,
    String? label,
    String? note,
    int? managerId,
    String? marker,
  });
  AccountPatch values({
    WriteValue<int, AccountFields> tenant = const .keep(),
    WriteValue<int, AccountFields> id = const .keep(),
    WriteValue<String?, AccountFields> label = const .keep(),
    WriteValue<String?, AccountFields> note = const .keep(),
    WriteValue<int?, AccountFields> managerId = const .keep(),
    WriteValue<String?, AccountFields> marker = const .keep(),
  });
  AccountPatch overlay(Iterable<AccountPatch> layers);
  bool isEmpty(AccountPatch input);
}

const AccountPatchFactory accountPatch = _AccountPatchFactory();

final class _AccountPatchFactory implements AccountPatchFactory {
  const _AccountPatchFactory();
  @override
  AccountPatch call({
    Object? tenant = _writeAbsent,
    Object? id = _writeAbsent,
    Object? label = _writeAbsent,
    Object? note = _writeAbsent,
    Object? managerId = _writeAbsent,
    Object? marker = _writeAbsent,
  }) => AccountPatch._(
    tenant: _writeLiteral<int, AccountFields>(tenant),
    id: _writeLiteral<int, AccountFields>(id),
    label: _writeLiteral<String?, AccountFields>(label),
    note: _writeLiteral<String?, AccountFields>(note),
    managerId: _writeLiteral<int?, AccountFields>(managerId),
    marker: _writeLiteral<String?, AccountFields>(marker),
  );
  @override
  AccountPatch values({
    WriteValue<int, AccountFields> tenant = const .keep(),
    WriteValue<int, AccountFields> id = const .keep(),
    WriteValue<String?, AccountFields> label = const .keep(),
    WriteValue<String?, AccountFields> note = const .keep(),
    WriteValue<int?, AccountFields> managerId = const .keep(),
    WriteValue<String?, AccountFields> marker = const .keep(),
  }) => AccountPatch._(
    tenant: tenant,
    id: id,
    label: label,
    note: note,
    managerId: managerId,
    marker: marker,
  );
  @override
  AccountPatch overlay(Iterable<AccountPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = AccountPatch._(
        tenant: WriteValue.overlay(earlier.tenant, later.tenant),
        id: WriteValue.overlay(earlier.id, later.id),
        label: WriteValue.overlay(earlier.label, later.label),
        note: WriteValue.overlay(earlier.note, later.note),
        managerId: WriteValue.overlay(earlier.managerId, later.managerId),
        marker: WriteValue.overlay(earlier.marker, later.marker),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(AccountPatch input) =>
      input.tenant.isMissing &&
      input.id.isMissing &&
      input.label.isMissing &&
      input.note.isMissing &&
      input.managerId.isMissing &&
      input.marker.isMissing;
}

/// Immutable input data; composition belongs to [accountInsert], not field names.
final class AccountInsert {
  final WriteValue<int, AccountFields> tenant;
  final WriteValue<int, AccountFields> id;
  final WriteValue<String?, AccountFields> label;
  final WriteValue<String?, AccountFields> note;
  final WriteValue<int?, AccountFields> managerId;
  final WriteValue<String?, AccountFields> marker;
  AccountInsert._({
    required this.tenant,
    required this.id,
    required this.label,
    required this.note,
    required this.managerId,
    required this.marker,
  }) {
    if (tenant.isMissing) {
      throw ArgumentError.value(tenant, 'tenant', 'Must be supplied.');
    }
    if (id.isMissing) {
      throw ArgumentError.value(id, 'id', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(AccountFields fields) => [
    ...fields.tenant.write(tenant, fields),
    ...fields.id.write(id, fields),
    ...fields.label.write(label, fields),
    ...fields.note.write(note, fields),
    ...fields.managerId.write(managerId, fields),
    ...fields.marker.write(marker, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class AccountInsertFactory {
  AccountInsert call({
    required int tenant,
    required int id,
    String? label,
    String? note,
    int? managerId,
    String? marker,
  });
  AccountInsert values({
    required WriteValue<int, AccountFields> tenant,
    required WriteValue<int, AccountFields> id,
    WriteValue<String?, AccountFields> label = const .keep(),
    WriteValue<String?, AccountFields> note = const .keep(),
    WriteValue<int?, AccountFields> managerId = const .keep(),
    WriteValue<String?, AccountFields> marker = const .keep(),
  });
  AccountInsert overlay(AccountInsert earlier, Iterable<AccountPatch> layers);
}

const AccountInsertFactory accountInsert = _AccountInsertFactory();

final class _AccountInsertFactory implements AccountInsertFactory {
  const _AccountInsertFactory();
  @override
  AccountInsert call({
    required int tenant,
    required int id,
    Object? label = _writeAbsent,
    Object? note = _writeAbsent,
    Object? managerId = _writeAbsent,
    Object? marker = _writeAbsent,
  }) => AccountInsert._(
    tenant: .set(tenant),
    id: .set(id),
    label: _writeLiteral<String?, AccountFields>(label),
    note: _writeLiteral<String?, AccountFields>(note),
    managerId: _writeLiteral<int?, AccountFields>(managerId),
    marker: _writeLiteral<String?, AccountFields>(marker),
  );
  @override
  AccountInsert values({
    required WriteValue<int, AccountFields> tenant,
    required WriteValue<int, AccountFields> id,
    WriteValue<String?, AccountFields> label = const .keep(),
    WriteValue<String?, AccountFields> note = const .keep(),
    WriteValue<int?, AccountFields> managerId = const .keep(),
    WriteValue<String?, AccountFields> marker = const .keep(),
  }) => AccountInsert._(
    tenant: tenant,
    id: id,
    label: label,
    note: note,
    managerId: managerId,
    marker: marker,
  );
  @override
  AccountInsert overlay(AccountInsert earlier, Iterable<AccountPatch> layers) {
    for (final later in layers) {
      earlier = AccountInsert._(
        tenant: WriteValue.overlay(earlier.tenant, later.tenant),
        id: WriteValue.overlay(earlier.id, later.id),
        label: WriteValue.overlay(earlier.label, later.label),
        note: WriteValue.overlay(earlier.note, later.note),
        managerId: WriteValue.overlay(earlier.managerId, later.managerId),
        marker: WriteValue.overlay(earlier.marker, later.marker),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Account from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class AccountCreator {
  Future<models.Account> call({
    required int tenant,
    required int id,
    String? label,
    String? note,
    int? managerId,
    String? marker,
  });
}

final class _AccountCreator implements AccountCreator {
  final AccountTableSet _table;
  const _AccountCreator(this._table);
  @override
  Future<models.Account> call({
    required int tenant,
    required int id,
    Object? label = _writeAbsent,
    Object? note = _writeAbsent,
    Object? managerId = _writeAbsent,
    Object? marker = _writeAbsent,
  }) async => _table.plan
      .insert(
        AccountInsert._(
          tenant: .set(tenant),
          id: .set(id),
          label: _writeLiteral<String?, AccountFields>(label),
          note: _writeLiteral<String?, AccountFields>(note),
          managerId: _writeLiteral<int?, AccountFields>(managerId),
          marker: _writeLiteral<String?, AccountFields>(marker),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class AccountPatcher {
  Future<int> call({
    int tenant,
    int id,
    String? label,
    String? note,
    int? managerId,
    String? marker,
  });
}

final class _AccountPatcher implements AccountPatcher {
  final orm_model.ModelQuery<models.Account, AccountFields, AccountPatch>
  _query;
  const _AccountPatcher(this._query);
  @override
  Future<int> call({
    Object? tenant = _writeAbsent,
    Object? id = _writeAbsent,
    Object? label = _writeAbsent,
    Object? note = _writeAbsent,
    Object? managerId = _writeAbsent,
    Object? marker = _writeAbsent,
  }) => _query.update(
    AccountPatch._(
      tenant: _writeLiteral<int, AccountFields>(tenant),
      id: _writeLiteral<int, AccountFields>(id),
      label: _writeLiteral<String?, AccountFields>(label),
      note: _writeLiteral<String?, AccountFields>(note),
      managerId: _writeLiteral<int?, AccountFields>(managerId),
      marker: _writeLiteral<String?, AccountFields>(marker),
    ),
  );
}

/// Named literal updates on a complete models.Account query.
extension AccountWrites
    on orm_model.ModelQuery<models.Account, AccountFields, AccountPatch> {
  /// Executes one update; omitted fields remain unchanged.
  AccountPatcher get patch => _AccountPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class AccountTableSet
    extends
        orm_model.ModelTable<
          models.Account,
          AccountFields,
          AccountInsert,
          AccountPatch
        > {
  AccountTableSet(QueryContext db)
    : super(
        db,
        accountTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final AccountCreator create = _AccountCreator(this);

  orm_model.ModelQuery<models.Account, AccountFields, AccountPatch> byId({
    required int tenant,
    required int id,
  }) => where(
    (row) => orm.allOf([row.tenant.eq(.value(tenant)), row.id.eq(.value(id))]),
  );
}

final _eventId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _eventTenant = Column<int?>(
  "tenant",
  Codecs.integer.nullable(),
  nullable: true,
  generated: false,
);
final _eventOwner = Column<int?>(
  "owner",
  Codecs.integer.nullable(),
  nullable: true,
  generated: false,
);
final _eventReviewer = Column<int?>(
  "reviewer",
  Codecs.integer.nullable(),
  nullable: true,
  generated: false,
);
final _eventTitle = Column<String>(
  "title",
  Codecs.text,
  nullable: false,
  generated: false,
);
final _eventScore = Column<int>(
  "score",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final eventSchema = TableSchema(
  "events",
  columns: [
    _eventId,
    _eventTenant,
    _eventOwner,
    _eventReviewer,
    _eventTitle,
    _eventScore,
  ],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [
    ForeignKey(
      ["tenant", "owner"],
      "accounts",
      ["tenant", "id"],
      onDelete: "RESTRICT",
    ),
    ForeignKey(
      ["tenant", "reviewer"],
      "accounts",
      ["tenant", "id"],
      onDelete: "RESTRICT",
    ),
  ],
);

final class EventFields extends Fields {
  EventFields(super.table);
  late final id = column(_eventId);
  late final tenant = column(_eventTenant);
  late final owner = column(_eventOwner);
  late final reviewer = column(_eventReviewer);
  late final title = column(_eventTitle);
  late final score = column(_eventScore);
  Relation<models.Account, AccountFields> get author => Relation(
    accountTable,
    parent: [tenant, owner],
    child: (row) => [row.tenant, row.id],
  );
  Relation<models.Account, AccountFields> get reviewerAccount => Relation(
    accountTable,
    parent: [tenant, reviewer],
    child: (row) => [row.tenant, row.id],
  );
}

final eventTable = Table<models.Event, EventFields>(
  eventSchema,
  EventFields.new,
  (row) =>
      (row.id, row.tenant, row.owner, row.reviewer, row.title, row.score).map(
        (v0, v1, v2, v3, v4, v5) => models.Event(
          id: v0,
          tenant: v1,
          owner: v2,
          reviewer: v3,
          title: v4,
          score: v5,
        ),
      ),
);

/// Immutable input data; composition belongs to [eventPatch], not field names.
final class EventPatch {
  final WriteValue<int, EventFields> id;
  final WriteValue<int?, EventFields> tenant;
  final WriteValue<int?, EventFields> owner;
  final WriteValue<int?, EventFields> reviewer;
  final WriteValue<String, EventFields> title;
  final WriteValue<int, EventFields> score;
  EventPatch._({
    required this.id,
    required this.tenant,
    required this.owner,
    required this.reviewer,
    required this.title,
    required this.score,
  });

  List<Assignment> _assignments(EventFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.tenant.write(tenant, fields),
    ...fields.owner.write(owner, fields),
    ...fields.reviewer.write(reviewer, fields),
    ...fields.title.write(title, fields),
    ...fields.score.write(score, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class EventPatchFactory {
  EventPatch call({
    int id,
    int? tenant,
    int? owner,
    int? reviewer,
    String title,
    int score,
  });
  EventPatch values({
    WriteValue<int, EventFields> id = const .keep(),
    WriteValue<int?, EventFields> tenant = const .keep(),
    WriteValue<int?, EventFields> owner = const .keep(),
    WriteValue<int?, EventFields> reviewer = const .keep(),
    WriteValue<String, EventFields> title = const .keep(),
    WriteValue<int, EventFields> score = const .keep(),
  });
  EventPatch overlay(Iterable<EventPatch> layers);
  bool isEmpty(EventPatch input);
}

const EventPatchFactory eventPatch = _EventPatchFactory();

final class _EventPatchFactory implements EventPatchFactory {
  const _EventPatchFactory();
  @override
  EventPatch call({
    Object? id = _writeAbsent,
    Object? tenant = _writeAbsent,
    Object? owner = _writeAbsent,
    Object? reviewer = _writeAbsent,
    Object? title = _writeAbsent,
    Object? score = _writeAbsent,
  }) => EventPatch._(
    id: _writeLiteral<int, EventFields>(id),
    tenant: _writeLiteral<int?, EventFields>(tenant),
    owner: _writeLiteral<int?, EventFields>(owner),
    reviewer: _writeLiteral<int?, EventFields>(reviewer),
    title: _writeLiteral<String, EventFields>(title),
    score: _writeLiteral<int, EventFields>(score),
  );
  @override
  EventPatch values({
    WriteValue<int, EventFields> id = const .keep(),
    WriteValue<int?, EventFields> tenant = const .keep(),
    WriteValue<int?, EventFields> owner = const .keep(),
    WriteValue<int?, EventFields> reviewer = const .keep(),
    WriteValue<String, EventFields> title = const .keep(),
    WriteValue<int, EventFields> score = const .keep(),
  }) => EventPatch._(
    id: id,
    tenant: tenant,
    owner: owner,
    reviewer: reviewer,
    title: title,
    score: score,
  );
  @override
  EventPatch overlay(Iterable<EventPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = EventPatch._(
        id: WriteValue.overlay(earlier.id, later.id),
        tenant: WriteValue.overlay(earlier.tenant, later.tenant),
        owner: WriteValue.overlay(earlier.owner, later.owner),
        reviewer: WriteValue.overlay(earlier.reviewer, later.reviewer),
        title: WriteValue.overlay(earlier.title, later.title),
        score: WriteValue.overlay(earlier.score, later.score),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(EventPatch input) =>
      input.id.isMissing &&
      input.tenant.isMissing &&
      input.owner.isMissing &&
      input.reviewer.isMissing &&
      input.title.isMissing &&
      input.score.isMissing;
}

/// Immutable input data; composition belongs to [eventInsert], not field names.
final class EventInsert {
  final WriteValue<int, EventFields> id;
  final WriteValue<int?, EventFields> tenant;
  final WriteValue<int?, EventFields> owner;
  final WriteValue<int?, EventFields> reviewer;
  final WriteValue<String, EventFields> title;
  final WriteValue<int, EventFields> score;
  EventInsert._({
    required this.id,
    required this.tenant,
    required this.owner,
    required this.reviewer,
    required this.title,
    required this.score,
  }) {
    if (id.isMissing) {
      throw ArgumentError.value(id, 'id', 'Must be supplied.');
    }
    if (title.isMissing) {
      throw ArgumentError.value(title, 'title', 'Must be supplied.');
    }
    if (score.isMissing) {
      throw ArgumentError.value(score, 'score', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(EventFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.tenant.write(tenant, fields),
    ...fields.owner.write(owner, fields),
    ...fields.reviewer.write(reviewer, fields),
    ...fields.title.write(title, fields),
    ...fields.score.write(score, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class EventInsertFactory {
  EventInsert call({
    required int id,
    int? tenant,
    int? owner,
    int? reviewer,
    required String title,
    required int score,
  });
  EventInsert values({
    required WriteValue<int, EventFields> id,
    WriteValue<int?, EventFields> tenant = const .keep(),
    WriteValue<int?, EventFields> owner = const .keep(),
    WriteValue<int?, EventFields> reviewer = const .keep(),
    required WriteValue<String, EventFields> title,
    required WriteValue<int, EventFields> score,
  });
  EventInsert overlay(EventInsert earlier, Iterable<EventPatch> layers);
}

const EventInsertFactory eventInsert = _EventInsertFactory();

final class _EventInsertFactory implements EventInsertFactory {
  const _EventInsertFactory();
  @override
  EventInsert call({
    required int id,
    Object? tenant = _writeAbsent,
    Object? owner = _writeAbsent,
    Object? reviewer = _writeAbsent,
    required String title,
    required int score,
  }) => EventInsert._(
    id: .set(id),
    tenant: _writeLiteral<int?, EventFields>(tenant),
    owner: _writeLiteral<int?, EventFields>(owner),
    reviewer: _writeLiteral<int?, EventFields>(reviewer),
    title: .set(title),
    score: .set(score),
  );
  @override
  EventInsert values({
    required WriteValue<int, EventFields> id,
    WriteValue<int?, EventFields> tenant = const .keep(),
    WriteValue<int?, EventFields> owner = const .keep(),
    WriteValue<int?, EventFields> reviewer = const .keep(),
    required WriteValue<String, EventFields> title,
    required WriteValue<int, EventFields> score,
  }) => EventInsert._(
    id: id,
    tenant: tenant,
    owner: owner,
    reviewer: reviewer,
    title: title,
    score: score,
  );
  @override
  EventInsert overlay(EventInsert earlier, Iterable<EventPatch> layers) {
    for (final later in layers) {
      earlier = EventInsert._(
        id: WriteValue.overlay(earlier.id, later.id),
        tenant: WriteValue.overlay(earlier.tenant, later.tenant),
        owner: WriteValue.overlay(earlier.owner, later.owner),
        reviewer: WriteValue.overlay(earlier.reviewer, later.reviewer),
        title: WriteValue.overlay(earlier.title, later.title),
        score: WriteValue.overlay(earlier.score, later.score),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Event from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class EventCreator {
  Future<models.Event> call({
    required int id,
    int? tenant,
    int? owner,
    int? reviewer,
    required String title,
    required int score,
  });
}

final class _EventCreator implements EventCreator {
  final EventTableSet _table;
  const _EventCreator(this._table);
  @override
  Future<models.Event> call({
    required int id,
    Object? tenant = _writeAbsent,
    Object? owner = _writeAbsent,
    Object? reviewer = _writeAbsent,
    required String title,
    required int score,
  }) async => _table.plan
      .insert(
        EventInsert._(
          id: .set(id),
          tenant: _writeLiteral<int?, EventFields>(tenant),
          owner: _writeLiteral<int?, EventFields>(owner),
          reviewer: _writeLiteral<int?, EventFields>(reviewer),
          title: .set(title),
          score: .set(score),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class EventPatcher {
  Future<int> call({
    int id,
    int? tenant,
    int? owner,
    int? reviewer,
    String title,
    int score,
  });
}

final class _EventPatcher implements EventPatcher {
  final orm_model.ModelQuery<models.Event, EventFields, EventPatch> _query;
  const _EventPatcher(this._query);
  @override
  Future<int> call({
    Object? id = _writeAbsent,
    Object? tenant = _writeAbsent,
    Object? owner = _writeAbsent,
    Object? reviewer = _writeAbsent,
    Object? title = _writeAbsent,
    Object? score = _writeAbsent,
  }) => _query.update(
    EventPatch._(
      id: _writeLiteral<int, EventFields>(id),
      tenant: _writeLiteral<int?, EventFields>(tenant),
      owner: _writeLiteral<int?, EventFields>(owner),
      reviewer: _writeLiteral<int?, EventFields>(reviewer),
      title: _writeLiteral<String, EventFields>(title),
      score: _writeLiteral<int, EventFields>(score),
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

final appSchema = List<TableSchema>.unmodifiable([accountSchema, eventSchema]);

extension AppTables on QueryContext {
  AccountTableSet get account => AccountTableSet(this);
  EventTableSet get event => EventTableSet(this);
}
