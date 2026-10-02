// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/orm.dart' as orm_model show ModelTable, ModelQuery;
import 'package:orm/values.dart';

import "schema.dart" as models;
export "types.dart" show TicketId;
export "schema.dart" show Ticket, SequenceRow;
import "types.dart" as types0;

final class _OrmWriteAbsent {
  const _OrmWriteAbsent();
}

const _writeAbsent = _OrmWriteAbsent();
WriteValue<T, F> _writeLiteral<T, F extends Fields>(Object? value) =>
    identical(value, _writeAbsent) ? const .keep() : .set(value as T);

final _sequenceRowId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
  clientDefault: types0.clientIdentity,
);
final sequenceRowSchema = TableSchema(
  "sequences",
  columns: [_sequenceRowId],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class SequenceRowFields extends Fields {
  SequenceRowFields(super.table);
  late final id = column(_sequenceRowId);
}

final sequenceRowTable = Table<models.SequenceRow, SequenceRowFields>(
  sequenceRowSchema,
  SequenceRowFields.new,
  (row) => row.id.map((value) => models.SequenceRow(id: value)),
);

/// Immutable input data; composition belongs to [sequenceRowPatch], not field names.
final class SequenceRowPatch {
  SequenceRowPatch._();

  List<Assignment> _assignments(SequenceRowFields fields) => [];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class SequenceRowPatchFactory {
  SequenceRowPatch call();
  SequenceRowPatch values();
  SequenceRowPatch overlay(Iterable<SequenceRowPatch> layers);
  bool isEmpty(SequenceRowPatch input);
}

const SequenceRowPatchFactory sequenceRowPatch = _SequenceRowPatchFactory();

final class _SequenceRowPatchFactory implements SequenceRowPatchFactory {
  const _SequenceRowPatchFactory();
  @override
  SequenceRowPatch call() => SequenceRowPatch._();
  @override
  SequenceRowPatch values() => SequenceRowPatch._();
  @override
  SequenceRowPatch overlay(Iterable<SequenceRowPatch> layers) {
    var earlier = call();
    for (final _ in layers) {
      earlier = SequenceRowPatch._();
    }
    return earlier;
  }

  @override
  bool isEmpty(SequenceRowPatch input) => true;
}

/// Immutable input data; composition belongs to [sequenceRowInsert], not field names.
final class SequenceRowInsert {
  final WriteValue<int, SequenceRowFields> id;
  SequenceRowInsert._({required this.id});

  List<Assignment> _assignments(SequenceRowFields fields) => [
    ...fields.id.write(id, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class SequenceRowInsertFactory {
  SequenceRowInsert call({int id});
  SequenceRowInsert values({
    WriteValue<int, SequenceRowFields> id = const .keep(),
  });
  SequenceRowInsert overlay(
    SequenceRowInsert earlier,
    Iterable<SequenceRowPatch> layers,
  );
}

const SequenceRowInsertFactory sequenceRowInsert = _SequenceRowInsertFactory();

final class _SequenceRowInsertFactory implements SequenceRowInsertFactory {
  const _SequenceRowInsertFactory();
  @override
  SequenceRowInsert call({Object? id = _writeAbsent}) =>
      SequenceRowInsert._(id: _writeLiteral<int, SequenceRowFields>(id));
  @override
  SequenceRowInsert values({
    WriteValue<int, SequenceRowFields> id = const .keep(),
  }) => SequenceRowInsert._(id: id);
  @override
  SequenceRowInsert overlay(
    SequenceRowInsert earlier,
    Iterable<SequenceRowPatch> layers,
  ) {
    for (final _ in layers) {
      earlier = SequenceRowInsert._(id: earlier.id);
    }
    return earlier;
  }
}

/// Creates a complete models.SequenceRow from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class SequenceRowCreator {
  Future<models.SequenceRow> call({int id});
}

final class _SequenceRowCreator implements SequenceRowCreator {
  final SequenceRowTableSet _table;
  const _SequenceRowCreator(this._table);
  @override
  Future<models.SequenceRow> call({Object? id = _writeAbsent}) async => _table
      .plan
      .insert(
        SequenceRowInsert._(id: _writeLiteral<int, SequenceRowFields>(id)),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class SequenceRowPatcher {
  Future<int> call();
}

final class _SequenceRowPatcher implements SequenceRowPatcher {
  final orm_model.ModelQuery<
    models.SequenceRow,
    SequenceRowFields,
    SequenceRowPatch
  >
  _query;
  const _SequenceRowPatcher(this._query);
  @override
  Future<int> call() => _query.update(SequenceRowPatch._());
}

/// Named literal updates on a complete models.SequenceRow query.
extension SequenceRowWrites
    on
        orm_model.ModelQuery<
          models.SequenceRow,
          SequenceRowFields,
          SequenceRowPatch
        > {
  /// Executes one update; omitted fields remain unchanged.
  SequenceRowPatcher get patch => _SequenceRowPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class SequenceRowTableSet
    extends
        orm_model.ModelTable<
          models.SequenceRow,
          SequenceRowFields,
          SequenceRowInsert,
          SequenceRowPatch
        > {
  SequenceRowTableSet(QueryContext db)
    : super(
        db,
        sequenceRowTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final SequenceRowCreator create = _SequenceRowCreator(this);

  orm_model.ModelQuery<models.SequenceRow, SequenceRowFields, SequenceRowPatch>
  byId(int id) => where((row) => row.id.eq(.value(id)));
}

final _ticketId = Column<types0.TicketId>(
  "id",
  types0.TicketId.codec,
  nullable: false,
  generated: false,
  clientDefault: types0.nextId,
);
final _ticketName = Column<String>(
  "name",
  Codecs.text,
  nullable: false,
  generated: false,
  clientDefault: types0.nameFactory,
);
final _ticketLabel = Column<String?>(
  "label",
  Codecs.text.nullable(),
  nullable: true,
  generated: false,
  clientDefault: types0.empty<String>,
);
final _ticketState = Column<String>(
  "state",
  Codecs.text,
  nullable: false,
  generated: false,
  defaultSql: "'server'",
  clientDefault: types0.Defaults.state,
);
final _ticketCreatedAt = Column<DateTime>(
  "created_at",
  Codecs.dateTime,
  nullable: false,
  generated: false,
  clientDefault: DateTime.now,
);
final ticketSchema = TableSchema(
  "tickets",
  columns: [
    _ticketId,
    _ticketName,
    _ticketLabel,
    _ticketState,
    _ticketCreatedAt,
  ],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class TicketFields extends Fields {
  TicketFields(super.table);
  late final id = column(_ticketId);
  late final name = column(_ticketName);
  late final label = column(_ticketLabel);
  late final state = column(_ticketState);
  late final createdAt = column(_ticketCreatedAt);
}

final ticketTable = Table<models.Ticket, TicketFields>(
  ticketSchema,
  TicketFields.new,
  (row) => (row.id, row.name, row.label, row.state, row.createdAt).map(
    (v0, v1, v2, v3, v4) =>
        models.Ticket(id: v0, name: v1, label: v2, state: v3, createdAt: v4),
  ),
);

/// Immutable input data; composition belongs to [ticketPatch], not field names.
final class TicketPatch {
  final WriteValue<types0.TicketId, TicketFields> id;
  final WriteValue<String, TicketFields> name;
  final WriteValue<String?, TicketFields> label;
  final WriteValue<String, TicketFields> state;
  final WriteValue<DateTime, TicketFields> createdAt;
  TicketPatch._({
    required this.id,
    required this.name,
    required this.label,
    required this.state,
    required this.createdAt,
  });

  List<Assignment> _assignments(TicketFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.name.write(name, fields),
    ...fields.label.write(label, fields),
    ...fields.state.write(state, fields),
    ...fields.createdAt.write(createdAt, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class TicketPatchFactory {
  TicketPatch call({
    types0.TicketId id,
    String name,
    String? label,
    String state,
    DateTime createdAt,
  });
  TicketPatch values({
    WriteValue<types0.TicketId, TicketFields> id = const .keep(),
    WriteValue<String, TicketFields> name = const .keep(),
    WriteValue<String?, TicketFields> label = const .keep(),
    WriteValue<String, TicketFields> state = const .keep(),
    WriteValue<DateTime, TicketFields> createdAt = const .keep(),
  });
  TicketPatch overlay(Iterable<TicketPatch> layers);
  bool isEmpty(TicketPatch input);
}

const TicketPatchFactory ticketPatch = _TicketPatchFactory();

final class _TicketPatchFactory implements TicketPatchFactory {
  const _TicketPatchFactory();
  @override
  TicketPatch call({
    Object? id = _writeAbsent,
    Object? name = _writeAbsent,
    Object? label = _writeAbsent,
    Object? state = _writeAbsent,
    Object? createdAt = _writeAbsent,
  }) => TicketPatch._(
    id: _writeLiteral<types0.TicketId, TicketFields>(id),
    name: _writeLiteral<String, TicketFields>(name),
    label: _writeLiteral<String?, TicketFields>(label),
    state: _writeLiteral<String, TicketFields>(state),
    createdAt: _writeLiteral<DateTime, TicketFields>(createdAt),
  );
  @override
  TicketPatch values({
    WriteValue<types0.TicketId, TicketFields> id = const .keep(),
    WriteValue<String, TicketFields> name = const .keep(),
    WriteValue<String?, TicketFields> label = const .keep(),
    WriteValue<String, TicketFields> state = const .keep(),
    WriteValue<DateTime, TicketFields> createdAt = const .keep(),
  }) => TicketPatch._(
    id: id,
    name: name,
    label: label,
    state: state,
    createdAt: createdAt,
  );
  @override
  TicketPatch overlay(Iterable<TicketPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = TicketPatch._(
        id: WriteValue.overlay(earlier.id, later.id),
        name: WriteValue.overlay(earlier.name, later.name),
        label: WriteValue.overlay(earlier.label, later.label),
        state: WriteValue.overlay(earlier.state, later.state),
        createdAt: WriteValue.overlay(earlier.createdAt, later.createdAt),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(TicketPatch input) =>
      input.id.isMissing &&
      input.name.isMissing &&
      input.label.isMissing &&
      input.state.isMissing &&
      input.createdAt.isMissing;
}

/// Immutable input data; composition belongs to [ticketInsert], not field names.
final class TicketInsert {
  final WriteValue<types0.TicketId, TicketFields> id;
  final WriteValue<String, TicketFields> name;
  final WriteValue<String?, TicketFields> label;
  final WriteValue<String, TicketFields> state;
  final WriteValue<DateTime, TicketFields> createdAt;
  TicketInsert._({
    required this.id,
    required this.name,
    required this.label,
    required this.state,
    required this.createdAt,
  });

  List<Assignment> _assignments(TicketFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.name.write(name, fields),
    ...fields.label.write(label, fields),
    ...fields.state.write(state, fields),
    ...fields.createdAt.write(createdAt, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class TicketInsertFactory {
  TicketInsert call({
    types0.TicketId id,
    String name,
    String? label,
    String state,
    DateTime createdAt,
  });
  TicketInsert values({
    WriteValue<types0.TicketId, TicketFields> id = const .keep(),
    WriteValue<String, TicketFields> name = const .keep(),
    WriteValue<String?, TicketFields> label = const .keep(),
    WriteValue<String, TicketFields> state = const .keep(),
    WriteValue<DateTime, TicketFields> createdAt = const .keep(),
  });
  TicketInsert overlay(TicketInsert earlier, Iterable<TicketPatch> layers);
}

const TicketInsertFactory ticketInsert = _TicketInsertFactory();

final class _TicketInsertFactory implements TicketInsertFactory {
  const _TicketInsertFactory();
  @override
  TicketInsert call({
    Object? id = _writeAbsent,
    Object? name = _writeAbsent,
    Object? label = _writeAbsent,
    Object? state = _writeAbsent,
    Object? createdAt = _writeAbsent,
  }) => TicketInsert._(
    id: _writeLiteral<types0.TicketId, TicketFields>(id),
    name: _writeLiteral<String, TicketFields>(name),
    label: _writeLiteral<String?, TicketFields>(label),
    state: _writeLiteral<String, TicketFields>(state),
    createdAt: _writeLiteral<DateTime, TicketFields>(createdAt),
  );
  @override
  TicketInsert values({
    WriteValue<types0.TicketId, TicketFields> id = const .keep(),
    WriteValue<String, TicketFields> name = const .keep(),
    WriteValue<String?, TicketFields> label = const .keep(),
    WriteValue<String, TicketFields> state = const .keep(),
    WriteValue<DateTime, TicketFields> createdAt = const .keep(),
  }) => TicketInsert._(
    id: id,
    name: name,
    label: label,
    state: state,
    createdAt: createdAt,
  );
  @override
  TicketInsert overlay(TicketInsert earlier, Iterable<TicketPatch> layers) {
    for (final later in layers) {
      earlier = TicketInsert._(
        id: WriteValue.overlay(earlier.id, later.id),
        name: WriteValue.overlay(earlier.name, later.name),
        label: WriteValue.overlay(earlier.label, later.label),
        state: WriteValue.overlay(earlier.state, later.state),
        createdAt: WriteValue.overlay(earlier.createdAt, later.createdAt),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Ticket from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class TicketCreator {
  Future<models.Ticket> call({
    types0.TicketId id,
    String name,
    String? label,
    String state,
    DateTime createdAt,
  });
}

final class _TicketCreator implements TicketCreator {
  final TicketTableSet _table;
  const _TicketCreator(this._table);
  @override
  Future<models.Ticket> call({
    Object? id = _writeAbsent,
    Object? name = _writeAbsent,
    Object? label = _writeAbsent,
    Object? state = _writeAbsent,
    Object? createdAt = _writeAbsent,
  }) async => _table.plan
      .insert(
        TicketInsert._(
          id: _writeLiteral<types0.TicketId, TicketFields>(id),
          name: _writeLiteral<String, TicketFields>(name),
          label: _writeLiteral<String?, TicketFields>(label),
          state: _writeLiteral<String, TicketFields>(state),
          createdAt: _writeLiteral<DateTime, TicketFields>(createdAt),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class TicketPatcher {
  Future<int> call({
    types0.TicketId id,
    String name,
    String? label,
    String state,
    DateTime createdAt,
  });
}

final class _TicketPatcher implements TicketPatcher {
  final orm_model.ModelQuery<models.Ticket, TicketFields, TicketPatch> _query;
  const _TicketPatcher(this._query);
  @override
  Future<int> call({
    Object? id = _writeAbsent,
    Object? name = _writeAbsent,
    Object? label = _writeAbsent,
    Object? state = _writeAbsent,
    Object? createdAt = _writeAbsent,
  }) => _query.update(
    TicketPatch._(
      id: _writeLiteral<types0.TicketId, TicketFields>(id),
      name: _writeLiteral<String, TicketFields>(name),
      label: _writeLiteral<String?, TicketFields>(label),
      state: _writeLiteral<String, TicketFields>(state),
      createdAt: _writeLiteral<DateTime, TicketFields>(createdAt),
    ),
  );
}

/// Named literal updates on a complete models.Ticket query.
extension TicketWrites
    on orm_model.ModelQuery<models.Ticket, TicketFields, TicketPatch> {
  /// Executes one update; omitted fields remain unchanged.
  TicketPatcher get patch => _TicketPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class TicketTableSet
    extends
        orm_model.ModelTable<
          models.Ticket,
          TicketFields,
          TicketInsert,
          TicketPatch
        > {
  TicketTableSet(QueryContext db)
    : super(
        db,
        ticketTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final TicketCreator create = _TicketCreator(this);

  orm_model.ModelQuery<models.Ticket, TicketFields, TicketPatch> byId(
    types0.TicketId id,
  ) => where((row) => row.id.eq(.value(id)));
}

final appSchema = List<TableSchema>.unmodifiable([
  sequenceRowSchema,
  ticketSchema,
]);

extension AppTables on QueryContext {
  SequenceRowTableSet get sequenceRow => SequenceRowTableSet(this);
  TicketTableSet get ticket => TicketTableSet(this);
}
