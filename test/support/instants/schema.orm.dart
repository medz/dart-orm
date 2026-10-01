// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';

import "schema.dart" as models;
export "schema.dart" show Event, Moment, Link;

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

final class EventTableSet extends TableSet<models.Event, EventFields> {
  EventTableSet(QueryContext db) : super(db, eventTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Event> create({
    Change<int> id = const Change.keep(),
    required DateTime at,
    Change<DateTime> created = const Change.keep(),
    DateTime? optional,
  }) => createRow(
    (row) => [
      ...row.id.change(id),
      row.at.set(at),
      ...row.created.change(created),
      row.optional.set(optional),
    ],
  );
  Query<models.Event, EventFields> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

extension EventUpdates on Query<models.Event, EventFields> {
  Future<int> patch({
    Change<DateTime> at = const Change.keep(),
    Change<DateTime> created = const Change.keep(),
    Change<DateTime?> optional = const Change.keep(),
  }) => update(
    (row) => [
      ...row.at.change(at),
      ...row.created.change(created),
      ...row.optional.change(optional),
    ],
  ).execute();
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

final class LinkTableSet extends TableSet<models.Link, LinkFields> {
  LinkTableSet(QueryContext db) : super(db, linkTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Link> create({
    Change<int> id = const Change.keep(),
    required DateTime at,
  }) => createRow((row) => [...row.id.change(id), row.at.set(at)]);
  Query<models.Link, LinkFields> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

extension LinkUpdates on Query<models.Link, LinkFields> {
  Future<int> patch({Change<DateTime> at = const Change.keep()}) =>
      update((row) => [...row.at.change(at)]).execute();
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

final class MomentTableSet extends TableSet<models.Moment, MomentFields> {
  MomentTableSet(QueryContext db) : super(db, momentTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Moment> create({
    required DateTime at,
    Change<String> label = const Change.keep(),
  }) => createRow((row) => [row.at.set(at), ...row.label.change(label)]);
  Query<models.Moment, MomentFields> byId(DateTime at) =>
      where((row) => row.at.eq(.value(at)));
}

extension MomentUpdates on Query<models.Moment, MomentFields> {
  Future<int> patch({
    Change<DateTime> at = const Change.keep(),
    Change<String> label = const Change.keep(),
  }) =>
      update((row) => [...row.at.change(at), ...row.label.change(label)])
          .execute();
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
