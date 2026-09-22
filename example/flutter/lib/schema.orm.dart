// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';

/// A complete immutable row from "notes".
final class Note({
  required final int id,
  required final String text,
  required final bool done,
  required final DateTime createdAt,
});
final _noteId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _noteText = Column<String>(
  "body",
  Codecs.text,
  nullable: false,
  generated: false,
);
final _noteDone = Column<bool>(
  "done",
  Codecs.boolean,
  nullable: false,
  generated: false,
  defaultSql: "false",
);
final _noteCreatedAt = Column<DateTime>(
  "created_at",
  Codecs.dateTime,
  nullable: false,
  generated: false,
);
final noteSchema = TableSchema(
  "notes",
  columns: [_noteId, _noteText, _noteDone, _noteCreatedAt],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class NoteFields extends Fields {
  NoteFields(super.table);
  late final id = column(_noteId);
  late final text = column(_noteText);
  late final done = column(_noteDone);
  late final createdAt = column(_noteCreatedAt);
  Relation<Comment, CommentFields> get comments =>
      Relation(commentTable, parent: [id], child: (row) => [row.noteId]);
}

final noteTable = Table<Note, NoteFields>(
  noteSchema,
  NoteFields.new,
  (row) => (
    row.id,
    row.text,
    row.done,
    row.createdAt,
  ).map((v0, v1, v2, v3) => Note(id: v0, text: v1, done: v2, createdAt: v3)),
);

final class NoteTableSet extends TableSet<Note, NoteFields> {
  NoteTableSet(QueryContext db) : super(db, noteTable) {
    db.registerSchema(appSchema);
  }
  Future<Note> create({
    Change<int> id = const Change.keep(),
    required String text,
    Change<bool> done = const Change.keep(),
    required DateTime createdAt,
  }) => createRow(
    (row) => [
      ...row.id.change(id),
      row.text.set(text),
      ...row.done.change(done),
      row.createdAt.set(createdAt),
    ],
  );
  Query<Note, NoteFields> byId(int id) => where((row) => row.id.eq(.value(id)));
}

extension NoteUpdates on Query<Note, NoteFields> {
  Future<int> patch({
    Change<String> text = const Change.keep(),
    Change<bool> done = const Change.keep(),
    Change<DateTime> createdAt = const Change.keep(),
  }) => update(
    (row) => [
      ...row.text.change(text),
      ...row.done.change(done),
      ...row.createdAt.change(createdAt),
    ],
  ).execute();
}

/// A complete immutable row from "comments".
final class Comment({
  required final int id,
  required final int noteId,
  required final String text,
});
final _commentId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _commentNoteId = Column<int>(
  "note_id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _commentText = Column<String>(
  "text",
  Codecs.text,
  nullable: false,
  generated: false,
);
final commentSchema = TableSchema(
  "comments",
  columns: [_commentId, _commentNoteId, _commentText],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [
    ForeignKey(["note_id"], "notes", ["id"], onDelete: "CASCADE"),
  ],
);

final class CommentFields extends Fields {
  CommentFields(super.table);
  late final id = column(_commentId);
  late final noteId = column(_commentNoteId);
  late final text = column(_commentText);
  Relation<Note, NoteFields> get note =>
      Relation(noteTable, parent: [noteId], child: (row) => [row.id]);
}

final commentTable = Table<Comment, CommentFields>(
  commentSchema,
  CommentFields.new,
  (row) => (
    row.id,
    row.noteId,
    row.text,
  ).map((v0, v1, v2) => Comment(id: v0, noteId: v1, text: v2)),
);

final class CommentTableSet extends TableSet<Comment, CommentFields> {
  CommentTableSet(QueryContext db) : super(db, commentTable) {
    db.registerSchema(appSchema);
  }
  Future<Comment> create({
    Change<int> id = const Change.keep(),
    required int noteId,
    required String text,
  }) => createRow(
    (row) => [...row.id.change(id), row.noteId.set(noteId), row.text.set(text)],
  );
  Query<Comment, CommentFields> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

extension CommentUpdates on Query<Comment, CommentFields> {
  Future<int> patch({
    Change<int> noteId = const Change.keep(),
    Change<String> text = const Change.keep(),
  }) =>
      update((row) => [...row.noteId.change(noteId), ...row.text.change(text)])
          .execute();
}

final appSchema = List<TableSchema>.unmodifiable([noteSchema, commentSchema]);

extension AppTables on QueryContext {
  NoteTableSet get note => NoteTableSet(this);
  CommentTableSet get comment => CommentTableSet(this);
}
