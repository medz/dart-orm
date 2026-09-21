// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';

/// A complete immutable row from "notes".
final class Note({
  required final int id,
  required final String body,
  required final DateTime createdAt,
});
final _noteId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _noteBody = Column<String>(
  "body",
  Codecs.text,
  nullable: false,
  generated: false,
);
final _noteCreatedAt = Column<DateTime>(
  "created_at",
  Codecs.dateTime,
  nullable: false,
  generated: false,
);
final noteSchema = TableSchema(
  "notes",
  columns: [_noteId, _noteBody, _noteCreatedAt],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class NoteFields extends Fields {
  NoteFields(super.table);
  late final id = column(_noteId);
  late final body = column(_noteBody);
  late final createdAt = column(_noteCreatedAt);
}

final noteTable = Table<Note, NoteFields>(
  noteSchema,
  NoteFields.new,
  (row) => (
    row.id,
    row.body,
    row.createdAt,
  ).map((v0, v1, v2) => Note(id: v0, body: v1, createdAt: v2)),
);

final class NoteTableSet extends TableSet<Note, NoteFields> {
  NoteTableSet(QueryContext db) : super(db, noteTable) {
    db.registerSchema(appSchema);
  }
  Future<Note> create({
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
  Query<Note, NoteFields> byId(int id) => where((row) => row.id.eq(id));
}

extension NoteUpdates on Query<Note, NoteFields> {
  Future<int> patch({
    Change<String> body = const Change.keep(),
    Change<DateTime> createdAt = const Change.keep(),
  }) => update(
    (row) => [...row.body.change(body), ...row.createdAt.change(createdAt)],
  ).execute();
}

final appSchema = List<TableSchema>.unmodifiable([noteSchema]);

extension AppTables on QueryContext {
  NoteTableSet get note => NoteTableSet(this);
}
