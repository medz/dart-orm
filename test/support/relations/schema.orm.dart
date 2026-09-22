// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';
import 'package:orm/sql.dart' as orm show allOf;

/// A complete immutable row from "accounts".
final class Account({
  required final int tenant,
  required final int id,
  required final String? label,
  required final String? note,
  required final int? managerId,
  required final String? marker,
});
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
  Relation<Account, AccountFields> get manager => Relation(
    accountTable,
    parent: [tenant, managerId],
    child: (row) => [row.tenant, row.id],
  );
  Relation<Account, AccountFields> get reports => Relation(
    accountTable,
    parent: [tenant, id],
    child: (row) => [row.tenant, row.managerId],
  );
  Relation<Event, EventFields> get events => Relation(
    eventTable,
    parent: [tenant, id],
    child: (row) => [row.tenant, row.owner],
  );
  Relation<Event, EventFields> get reviews => Relation(
    eventTable,
    parent: [tenant, id],
    child: (row) => [row.tenant, row.reviewer],
  );
}

final accountTable = Table<Account, AccountFields>(
  accountSchema,
  AccountFields.new,
  (row) =>
      (row.tenant, row.id, row.label, row.note, row.managerId, row.marker).map(
        (v0, v1, v2, v3, v4, v5) => Account(
          tenant: v0,
          id: v1,
          label: v2,
          note: v3,
          managerId: v4,
          marker: v5,
        ),
      ),
);

final class AccountTableSet extends TableSet<Account, AccountFields> {
  AccountTableSet(QueryContext db) : super(db, accountTable) {
    db.registerSchema(appSchema);
  }
  Future<Account> create({
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
  Query<Account, AccountFields> byId({required int tenant, required int id}) =>
      where(
        (row) =>
            orm.allOf([row.tenant.eq(.value(tenant)), row.id.eq(.value(id))]),
      );
}

extension AccountUpdates on Query<Account, AccountFields> {
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

/// A complete immutable row from "events".
final class Event({
  required final int id,
  required final int? tenant,
  required final int? owner,
  required final int? reviewer,
  required final String title,
  required final int score,
});
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
  Relation<Account, AccountFields> get author => Relation(
    accountTable,
    parent: [tenant, owner],
    child: (row) => [row.tenant, row.id],
  );
  Relation<Account, AccountFields> get reviewerAccount => Relation(
    accountTable,
    parent: [tenant, reviewer],
    child: (row) => [row.tenant, row.id],
  );
}

final eventTable = Table<Event, EventFields>(
  eventSchema,
  EventFields.new,
  (row) =>
      (row.id, row.tenant, row.owner, row.reviewer, row.title, row.score).map(
        (v0, v1, v2, v3, v4, v5) => Event(
          id: v0,
          tenant: v1,
          owner: v2,
          reviewer: v3,
          title: v4,
          score: v5,
        ),
      ),
);

final class EventTableSet extends TableSet<Event, EventFields> {
  EventTableSet(QueryContext db) : super(db, eventTable) {
    db.registerSchema(appSchema);
  }
  Future<Event> create({
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
  Query<Event, EventFields> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

extension EventUpdates on Query<Event, EventFields> {
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

final appSchema = List<TableSchema>.unmodifiable([accountSchema, eventSchema]);

extension AppTables on QueryContext {
  AccountTableSet get account => AccountTableSet(this);
  EventTableSet get event => EventTableSet(this);
}
