// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/orm.dart';

import "schema.dart" as models;
export "schema.dart" show Note, Comment;

final _notesId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _notesText = Column<String>(
  "body",
  Codecs.text,
  nullable: false,
  generated: false,
);
final _notesDone = Column<bool>(
  "done",
  Codecs.boolean,
  nullable: false,
  generated: false,
  defaultSql: "false",
);
final _notesCreatedAt = Column<DateTime>(
  "created_at",
  Codecs.dateTime,
  nullable: false,
  generated: false,
);
final notesSchema = TableSchema(
  "notes",
  columns: [_notesId, _notesText, _notesDone, _notesCreatedAt],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class NotesFields extends Fields {
  NotesFields(super.table);
  late final id = column(_notesId);
  late final text = column(_notesText);
  late final done = column(_notesDone);
  late final createdAt = column(_notesCreatedAt);
  Relation<models.Comment, CommentsFields> get comments =>
      Relation(commentsTable, parent: [id], child: (row) => [row.noteId]);
}

final notesTable = Table<models.Note, NotesFields>(
  notesSchema,
  NotesFields.new,
  (row) => (row.id, row.text, row.done, row.createdAt).map(
    (id, text, done, createdAt) =>
        (id: id, text: text, done: done, createdAt: createdAt),
  ),
);

final class NotesTableSet extends TableSet<models.Note, NotesFields> {
  NotesTableSet(Database<Backend> db) : super(db, notesTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Note> create({
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
  Query<models.Note, NotesFields> byId(int id) => where((row) => row.id.eq(id));
}

extension NotesUpdates on Query<models.Note, NotesFields> {
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

final _commentsId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _commentsNoteId = Column<int>(
  "note_id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _commentsText = Column<String>(
  "text",
  Codecs.text,
  nullable: false,
  generated: false,
);
final commentsSchema = TableSchema(
  "comments",
  columns: [_commentsId, _commentsNoteId, _commentsText],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [
    ForeignKey(["note_id"], "notes", ["id"], onDelete: "CASCADE"),
  ],
);

final class CommentsFields extends Fields {
  CommentsFields(super.table);
  late final id = column(_commentsId);
  late final noteId = column(_commentsNoteId);
  late final text = column(_commentsText);
  Relation<models.Note, NotesFields> get note =>
      Relation(notesTable, parent: [noteId], child: (row) => [row.id]);
}

final commentsTable = Table<models.Comment, CommentsFields>(
  commentsSchema,
  CommentsFields.new,
  (row) => (
    row.id,
    row.noteId,
    row.text,
  ).map((id, noteId, text) => (id: id, noteId: noteId, text: text)),
);

final class CommentsTableSet extends TableSet<models.Comment, CommentsFields> {
  CommentsTableSet(Database<Backend> db) : super(db, commentsTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Comment> create({
    Change<int> id = const Change.keep(),
    required int noteId,
    required String text,
  }) => createRow(
    (row) => [...row.id.change(id), row.noteId.set(noteId), row.text.set(text)],
  );
  Query<models.Comment, CommentsFields> byId(int id) =>
      where((row) => row.id.eq(id));
}

extension CommentsUpdates on Query<models.Comment, CommentsFields> {
  Future<int> patch({
    Change<int> noteId = const Change.keep(),
    Change<String> text = const Change.keep(),
  }) =>
      update((row) => [...row.noteId.change(noteId), ...row.text.change(text)])
          .execute();
}

final appSchema = List<TableSchema>.unmodifiable([notesSchema, commentsSchema]);

extension AppTables<B extends Backend> on Database<B> {
  NotesTableSet get notes => NotesTableSet(this);
  CommentsTableSet get comments => CommentsTableSet(this);
}
