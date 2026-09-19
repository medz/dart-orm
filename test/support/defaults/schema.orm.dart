// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';

import "schema.dart" as models;
export "schema.dart" show Ticket, SequenceRow;
import "types.dart" as types0;

final _ticketsId = Column<types0.TicketId>(
  "id",
  types0.TicketId.codec,
  nullable: false,
  generated: false,
  clientDefault: types0.nextId,
);
final _ticketsName = Column<String>(
  "name",
  Codecs.text,
  nullable: false,
  generated: false,
  clientDefault: types0.nameFactory,
);
final _ticketsLabel = Column<String?>(
  "label",
  Codecs.text.nullable(),
  nullable: true,
  generated: false,
  clientDefault: types0.empty<String>,
);
final _ticketsState = Column<String>(
  "state",
  Codecs.text,
  nullable: false,
  generated: false,
  defaultSql: "'server'",
  clientDefault: types0.Defaults.state,
);
final _ticketsCreatedAt = Column<DateTime>(
  "created_at",
  Codecs.dateTime,
  nullable: false,
  generated: false,
  clientDefault: DateTime.now,
);
final ticketsSchema = TableSchema(
  "tickets",
  columns: [
    _ticketsId,
    _ticketsName,
    _ticketsLabel,
    _ticketsState,
    _ticketsCreatedAt,
  ],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class TicketsFields extends Fields {
  TicketsFields(super.table);
  late final id = column(_ticketsId);
  late final name = column(_ticketsName);
  late final label = column(_ticketsLabel);
  late final state = column(_ticketsState);
  late final createdAt = column(_ticketsCreatedAt);
}

final ticketsTable = Table<models.Ticket, TicketsFields>(
  ticketsSchema,
  TicketsFields.new,
  (row) => (row.id, row.name, row.label, row.state, row.createdAt).map(
    (id, name, label, state, createdAt) =>
        (id: id, name: name, label: label, state: state, createdAt: createdAt),
  ),
);

final class TicketsTableSet extends TableSet<models.Ticket, TicketsFields> {
  TicketsTableSet(QueryContext db) : super(db, ticketsTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Ticket> create({
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
  Query<models.Ticket, TicketsFields> byId(types0.TicketId id) =>
      where((row) => row.id.eq(id));
}

extension TicketsUpdates on Query<models.Ticket, TicketsFields> {
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

final _sequencesId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
  clientDefault: types0.clientIdentity,
);
final sequencesSchema = TableSchema(
  "sequences",
  columns: [_sequencesId],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class SequencesFields extends Fields {
  SequencesFields(super.table);
  late final id = column(_sequencesId);
}

final sequencesTable = Table<models.SequenceRow, SequencesFields>(
  sequencesSchema,
  SequencesFields.new,
  (row) => row.id.map((v) => (id: v)),
);

final class SequencesTableSet
    extends TableSet<models.SequenceRow, SequencesFields> {
  SequencesTableSet(QueryContext db) : super(db, sequencesTable) {
    db.registerSchema(appSchema);
  }
  Future<models.SequenceRow> create({Change<int> id = const Change.keep()}) =>
      createRow((row) => [...row.id.change(id)]);
  Query<models.SequenceRow, SequencesFields> byId(int id) =>
      where((row) => row.id.eq(id));
}

final appSchema = List<TableSchema>.unmodifiable([
  ticketsSchema,
  sequencesSchema,
]);

extension AppTables on QueryContext {
  TicketsTableSet get tickets => TicketsTableSet(this);
  SequencesTableSet get sequences => SequencesTableSet(this);
}
