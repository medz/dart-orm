// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/orm.dart';

import "schema.dart" as models;
export "schema.dart" show Note;

final _notesId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _notesBody = Column<String>(
  "body",
  Codecs.text,
  nullable: false,
  generated: false,
);
final _notesCreatedAt = Column<DateTime>(
  "created_at",
  Codecs.dateTime,
  nullable: false,
  generated: false,
);
final notesSchema = TableSchema(
  "notes",
  columns: [_notesId, _notesBody, _notesCreatedAt],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class NotesFields extends Fields {
  NotesFields(super.table);
  late final id = column(_notesId);
  late final body = column(_notesBody);
  late final createdAt = column(_notesCreatedAt);
}

final notesTable = Table<models.Note, NotesFields>(
  notesSchema,
  NotesFields.new,
  (row) => (
    row.id,
    row.body,
    row.createdAt,
  ).map((id, body, createdAt) => (id: id, body: body, createdAt: createdAt)),
);

final class NotesTableSet extends TableSet<models.Note, NotesFields> {
  NotesTableSet(Database<Backend> db) : super(db, notesTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Note> create({
    Change<int> id = const Change.keep(),
    required String body,
    required DateTime createdAt,
  }) => createRow(
    (row) => [
      ...row.id.change(id),
      row.body.set(body),
      row.createdAt.set(createdAt),
    ],
  );
  Query<models.Note, NotesFields> byId(int id) => where((row) => row.id.eq(id));
}

extension NotesUpdates on Query<models.Note, NotesFields> {
  Future<int> patch({
    Change<String> body = const Change.keep(),
    Change<DateTime> createdAt = const Change.keep(),
  }) => update(
    (row) => [...row.body.change(body), ...row.createdAt.change(createdAt)],
  ).execute();
}

final appSchema = List<TableSchema>.unmodifiable([notesSchema]);

extension AppTables<B extends Backend> on Database<B> {
  NotesTableSet get notes => NotesTableSet(this);
}
