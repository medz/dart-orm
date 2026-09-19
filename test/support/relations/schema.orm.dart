// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';

import "schema.dart" as models;
export "schema.dart" show Account, Event;

final _accountsTenant = Column<int>(
  "tenant",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _accountsId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _accountsLabel = Column<String?>(
  "label",
  Codecs.text.nullable(),
  nullable: true,
  generated: false,
);
final _accountsNote = Column<String?>(
  "note",
  Codecs.text.nullable(),
  nullable: true,
  generated: false,
);
final _accountsManagerId = Column<int?>(
  "manager_id",
  Codecs.integer.nullable(),
  nullable: true,
  generated: false,
);
final _accountsMarker = Column<String?>(
  "_ORM_PRESENT",
  Codecs.text.nullable(),
  nullable: true,
  generated: false,
);
final accountsSchema = TableSchema(
  "accounts",
  columns: [
    _accountsTenant,
    _accountsId,
    _accountsLabel,
    _accountsNote,
    _accountsManagerId,
    _accountsMarker,
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

final class AccountsFields extends Fields {
  AccountsFields(super.table);
  late final tenant = column(_accountsTenant);
  late final id = column(_accountsId);
  late final label = column(_accountsLabel);
  late final note = column(_accountsNote);
  late final managerId = column(_accountsManagerId);
  late final marker = column(_accountsMarker);
  Relation<models.Account, AccountsFields> get manager => Relation(
    accountsTable,
    parent: [tenant, managerId],
    child: (row) => [row.tenant, row.id],
  );
  Relation<models.Account, AccountsFields> get reports => Relation(
    accountsTable,
    parent: [tenant, id],
    child: (row) => [row.tenant, row.managerId],
  );
  Relation<models.Event, EventsFields> get events => Relation(
    eventsTable,
    parent: [tenant, id],
    child: (row) => [row.tenant, row.owner],
  );
  Relation<models.Event, EventsFields> get reviews => Relation(
    eventsTable,
    parent: [tenant, id],
    child: (row) => [row.tenant, row.reviewer],
  );
}

final accountsTable = Table<models.Account, AccountsFields>(
  accountsSchema,
  AccountsFields.new,
  (row) =>
      (row.tenant, row.id, row.label, row.note, row.managerId, row.marker).map(
        (tenant, id, label, note, managerId, marker) => (
          tenant: tenant,
          id: id,
          label: label,
          note: note,
          managerId: managerId,
          marker: marker,
        ),
      ),
);

final class AccountsTableSet extends TableSet<models.Account, AccountsFields> {
  AccountsTableSet(QueryContext db) : super(db, accountsTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Account> create({
    required int tenant,
    required int id,
    String? label,
    String? note,
    int? managerId,
    String? marker,
  }) => createRow(
    (row) => [
      row.tenant.set(tenant),
      row.id.set(id),
      row.label.set(label),
      row.note.set(note),
      row.managerId.set(managerId),
      row.marker.set(marker),
    ],
  );
  Query<models.Account, AccountsFields> byId({
    required int tenant,
    required int id,
  }) => where((row) => row.tenant.eq(tenant).and(row.id.eq(id)));
}

extension AccountsUpdates on Query<models.Account, AccountsFields> {
  Future<int> patch({
    Change<int> tenant = const Change.keep(),
    Change<int> id = const Change.keep(),
    Change<String?> label = const Change.keep(),
    Change<String?> note = const Change.keep(),
    Change<int?> managerId = const Change.keep(),
    Change<String?> marker = const Change.keep(),
  }) => update(
    (row) => [
      ...row.tenant.change(tenant),
      ...row.id.change(id),
      ...row.label.change(label),
      ...row.note.change(note),
      ...row.managerId.change(managerId),
      ...row.marker.change(marker),
    ],
  ).execute();
}

final _eventsId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _eventsTenant = Column<int?>(
  "tenant",
  Codecs.integer.nullable(),
  nullable: true,
  generated: false,
);
final _eventsOwner = Column<int?>(
  "owner",
  Codecs.integer.nullable(),
  nullable: true,
  generated: false,
);
final _eventsReviewer = Column<int?>(
  "reviewer",
  Codecs.integer.nullable(),
  nullable: true,
  generated: false,
);
final _eventsTitle = Column<String>(
  "title",
  Codecs.text,
  nullable: false,
  generated: false,
);
final _eventsScore = Column<int>(
  "score",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final eventsSchema = TableSchema(
  "events",
  columns: [
    _eventsId,
    _eventsTenant,
    _eventsOwner,
    _eventsReviewer,
    _eventsTitle,
    _eventsScore,
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

final class EventsFields extends Fields {
  EventsFields(super.table);
  late final id = column(_eventsId);
  late final tenant = column(_eventsTenant);
  late final owner = column(_eventsOwner);
  late final reviewer = column(_eventsReviewer);
  late final title = column(_eventsTitle);
  late final score = column(_eventsScore);
  Relation<models.Account, AccountsFields> get author => Relation(
    accountsTable,
    parent: [tenant, owner],
    child: (row) => [row.tenant, row.id],
  );
  Relation<models.Account, AccountsFields> get reviewerAccount => Relation(
    accountsTable,
    parent: [tenant, reviewer],
    child: (row) => [row.tenant, row.id],
  );
}

final eventsTable = Table<models.Event, EventsFields>(
  eventsSchema,
  EventsFields.new,
  (row) =>
      (row.id, row.tenant, row.owner, row.reviewer, row.title, row.score).map(
        (id, tenant, owner, reviewer, title, score) => (
          id: id,
          tenant: tenant,
          owner: owner,
          reviewer: reviewer,
          title: title,
          score: score,
        ),
      ),
);

final class EventsTableSet extends TableSet<models.Event, EventsFields> {
  EventsTableSet(QueryContext db) : super(db, eventsTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Event> create({
    required int id,
    int? tenant,
    int? owner,
    int? reviewer,
    required String title,
    required int score,
  }) => createRow(
    (row) => [
      row.id.set(id),
      row.tenant.set(tenant),
      row.owner.set(owner),
      row.reviewer.set(reviewer),
      row.title.set(title),
      row.score.set(score),
    ],
  );
  Query<models.Event, EventsFields> byId(int id) =>
      where((row) => row.id.eq(id));
}

extension EventsUpdates on Query<models.Event, EventsFields> {
  Future<int> patch({
    Change<int> id = const Change.keep(),
    Change<int?> tenant = const Change.keep(),
    Change<int?> owner = const Change.keep(),
    Change<int?> reviewer = const Change.keep(),
    Change<String> title = const Change.keep(),
    Change<int> score = const Change.keep(),
  }) => update(
    (row) => [
      ...row.id.change(id),
      ...row.tenant.change(tenant),
      ...row.owner.change(owner),
      ...row.reviewer.change(reviewer),
      ...row.title.change(title),
      ...row.score.change(score),
    ],
  ).execute();
}

final appSchema = List<TableSchema>.unmodifiable([
  accountsSchema,
  eventsSchema,
]);

extension AppTables on QueryContext {
  AccountsTableSet get accounts => AccountsTableSet(this);
  EventsTableSet get events => EventsTableSet(this);
}
