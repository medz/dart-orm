// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';

export "types.dart" show TicketId;
import "types.dart" as types0;

/// A complete immutable row from "tickets".
final class Ticket({
  required final types0.TicketId id,
  required final String name,
  required final String? label,
  required final String state,
  required final DateTime createdAt,
});
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

final ticketTable = Table<Ticket, TicketFields>(
  ticketSchema,
  TicketFields.new,
  (row) => (row.id, row.name, row.label, row.state, row.createdAt).map(
    (v0, v1, v2, v3, v4) =>
        Ticket(id: v0, name: v1, label: v2, state: v3, createdAt: v4),
  ),
);

final class TicketTableSet extends TableSet<Ticket, TicketFields> {
  TicketTableSet(QueryContext db) : super(db, ticketTable) {
    db.registerSchema(appSchema);
  }
  Future<Ticket> create({
    Change<types0.TicketId> id = const Change.keep(),
    Change<String> name = const Change.keep(),
    Change<String?> label = const Change.keep(),
    Change<String> state = const Change.keep(),
    Change<DateTime> createdAt = const Change.keep(),
  }) => createRow(
    (row) => [
      ...row.id.change(id),
      ...row.name.change(name),
      ...row.label.change(label),
      ...row.state.change(state),
      ...row.createdAt.change(createdAt),
    ],
  );
  Query<Ticket, TicketFields> byId(types0.TicketId id) =>
      where((row) => row.id.eq(.value(id)));
}

extension TicketUpdates on Query<Ticket, TicketFields> {
  Future<int> patch({
    Change<types0.TicketId> id = const Change.keep(),
    Change<String> name = const Change.keep(),
    Change<String?> label = const Change.keep(),
    Change<String> state = const Change.keep(),
    Change<DateTime> createdAt = const Change.keep(),
  }) => update(
    (row) => [
      ...row.id.change(id),
      ...row.name.change(name),
      ...row.label.change(label),
      ...row.state.change(state),
      ...row.createdAt.change(createdAt),
    ],
  ).execute();
}

/// A complete immutable row from "sequences".
final class SequenceRow({required final int id});
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

final sequenceRowTable = Table<SequenceRow, SequenceRowFields>(
  sequenceRowSchema,
  SequenceRowFields.new,
  (row) => row.id.map((value) => SequenceRow(id: value)),
);

final class SequenceRowTableSet
    extends TableSet<SequenceRow, SequenceRowFields> {
  SequenceRowTableSet(QueryContext db) : super(db, sequenceRowTable) {
    db.registerSchema(appSchema);
  }
  Future<SequenceRow> create({Change<int> id = const Change.keep()}) =>
      createRow((row) => [...row.id.change(id)]);
  Query<SequenceRow, SequenceRowFields> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

final appSchema = List<TableSchema>.unmodifiable([
  ticketSchema,
  sequenceRowSchema,
]);

extension AppTables on QueryContext {
  TicketTableSet get ticket => TicketTableSet(this);
  SequenceRowTableSet get sequenceRow => SequenceRowTableSet(this);
}
