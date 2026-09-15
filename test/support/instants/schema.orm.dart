// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/orm.dart';

import "schema.dart" as models;

final _eventsId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _eventsAt = Column<DateTime>(
  "at",
  Codecs.dateTime,
  nullable: false,
  generated: false,
);
final _eventsCreated = Column<DateTime>(
  "created",
  Codecs.dateTime,
  nullable: false,
  generated: false,
  defaultSql: "CURRENT_TIMESTAMP",
);
final _eventsOptional = Column<DateTime?>(
  "optional",
  Codecs.dateTime.nullable(),
  nullable: true,
  generated: false,
);
final eventsSchema = TableSchema(
  "events",
  columns: [_eventsId, _eventsAt, _eventsCreated, _eventsOptional],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class EventsFields extends Fields {
  EventsFields(super.table);
  late final id = column(_eventsId);
  late final at = column(_eventsAt);
  late final created = column(_eventsCreated);
  late final optional = column(_eventsOptional);
}

final eventsTable = Table<models.Event, EventsFields>(
  eventsSchema,
  EventsFields.new,
  (row) => (row.id, row.at, row.created, row.optional).map(
    (id, at, created, optional) =>
        (id: id, at: at, created: created, optional: optional),
  ),
);

final class EventsTableSet extends TableSet<models.Event, EventsFields> {
  EventsTableSet(Database<Backend> db) : super(db, eventsTable) {
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
  Query<models.Event, EventsFields> byId(int id) =>
      where((row) => row.id.eq(id));
}

extension EventsUpdates on Query<models.Event, EventsFields> {
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

final _momentsAt = Column<DateTime>(
  "at",
  Codecs.dateTime,
  nullable: false,
  generated: false,
);
final _momentsLabel = Column<String>(
  "label",
  Codecs.text,
  nullable: false,
  generated: false,
  defaultSql: "'pending'",
);
final momentsSchema = TableSchema(
  "moments",
  columns: [_momentsAt, _momentsLabel],
  primaryKey: ["at"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class MomentsFields extends Fields {
  MomentsFields(super.table);
  late final at = column(_momentsAt);
  late final label = column(_momentsLabel);
  Relation<models.Link, LinksFields> get links =>
      Relation(linksTable, parent: [at], child: (row) => [row.at]);
}

final momentsTable = Table<models.Moment, MomentsFields>(
  momentsSchema,
  MomentsFields.new,
  (row) => (row.at, row.label).map((at, label) => (at: at, label: label)),
);

final class MomentsTableSet extends TableSet<models.Moment, MomentsFields> {
  MomentsTableSet(Database<Backend> db) : super(db, momentsTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Moment> create({
    required DateTime at,
    Change<String> label = const Change.keep(),
  }) => createRow((row) => [row.at.set(at), ...row.label.change(label)]);
  Query<models.Moment, MomentsFields> byId(DateTime at) =>
      where((row) => row.at.eq(at));
}

extension MomentsUpdates on Query<models.Moment, MomentsFields> {
  Future<int> patch({
    Change<DateTime> at = const Change.keep(),
    Change<String> label = const Change.keep(),
  }) =>
      update((row) => [...row.at.change(at), ...row.label.change(label)])
          .execute();
}

final _linksId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _linksAt = Column<DateTime>(
  "at",
  Codecs.dateTime,
  nullable: false,
  generated: false,
);
final linksSchema = TableSchema(
  "links",
  columns: [_linksId, _linksAt],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [
    ForeignKey(["at"], "moments", ["at"], onDelete: "RESTRICT"),
  ],
);

final class LinksFields extends Fields {
  LinksFields(super.table);
  late final id = column(_linksId);
  late final at = column(_linksAt);
  Relation<models.Moment, MomentsFields> get moment =>
      Relation(momentsTable, parent: [at], child: (row) => [row.at]);
}

final linksTable = Table<models.Link, LinksFields>(
  linksSchema,
  LinksFields.new,
  (row) => (row.id, row.at).map((id, at) => (id: id, at: at)),
);

final class LinksTableSet extends TableSet<models.Link, LinksFields> {
  LinksTableSet(Database<Backend> db) : super(db, linksTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Link> create({
    Change<int> id = const Change.keep(),
    required DateTime at,
  }) => createRow((row) => [...row.id.change(id), row.at.set(at)]);
  Query<models.Link, LinksFields> byId(int id) => where((row) => row.id.eq(id));
}

extension LinksUpdates on Query<models.Link, LinksFields> {
  Future<int> patch({Change<DateTime> at = const Change.keep()}) =>
      update((row) => [...row.at.change(at)]).execute();
}

final appSchema = <TableSchema>[eventsSchema, momentsSchema, linksSchema];

extension AppTables<B extends Backend> on Database<B> {
  EventsTableSet get events => EventsTableSet(this);
  MomentsTableSet get moments => MomentsTableSet(this);
  LinksTableSet get links => LinksTableSet(this);
}
