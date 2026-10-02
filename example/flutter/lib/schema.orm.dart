// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/orm.dart' as orm_model show ModelTable, ModelQuery;
import 'package:orm/values.dart';
import "package:orm_flutter/schema.dart" as models;
export "package:orm_flutter/schema.dart" show Note, Comment;

final class _OrmWriteAbsent {
  const _OrmWriteAbsent();
}

const _writeAbsent = _OrmWriteAbsent();
WriteValue<T, F> _writeLiteral<T, F extends Fields>(Object? value) =>
    identical(value, _writeAbsent) ? const .keep() : .set(value as T);

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
  Relation<models.Note, NoteFields> get note =>
      Relation(noteTable, parent: [noteId], child: (row) => [row.id]);
}

final commentTable = Table<models.Comment, CommentFields>(
  commentSchema,
  CommentFields.new,
  (row) => (
    row.id,
    row.noteId,
    row.text,
  ).map((v0, v1, v2) => models.Comment(id: v0, noteId: v1, text: v2)),
);

/// Immutable input data; composition belongs to [commentPatch], not field names.
final class CommentPatch {
  final WriteValue<int, CommentFields> noteId;
  final WriteValue<String, CommentFields> text;
  CommentPatch._({required this.noteId, required this.text});

  List<Assignment> _assignments(CommentFields fields) => [
    ...fields.noteId.write(noteId, fields),
    ...fields.text.write(text, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class CommentPatchFactory {
  CommentPatch call({int noteId, String text});
  CommentPatch values({
    WriteValue<int, CommentFields> noteId = const .keep(),
    WriteValue<String, CommentFields> text = const .keep(),
  });
  CommentPatch overlay(Iterable<CommentPatch> layers);
  bool isEmpty(CommentPatch input);
}

const CommentPatchFactory commentPatch = _CommentPatchFactory();

final class _CommentPatchFactory implements CommentPatchFactory {
  const _CommentPatchFactory();
  @override
  CommentPatch call({
    Object? noteId = _writeAbsent,
    Object? text = _writeAbsent,
  }) => CommentPatch._(
    noteId: _writeLiteral<int, CommentFields>(noteId),
    text: _writeLiteral<String, CommentFields>(text),
  );
  @override
  CommentPatch values({
    WriteValue<int, CommentFields> noteId = const .keep(),
    WriteValue<String, CommentFields> text = const .keep(),
  }) => CommentPatch._(noteId: noteId, text: text);
  @override
  CommentPatch overlay(Iterable<CommentPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = CommentPatch._(
        noteId: WriteValue.overlay(earlier.noteId, later.noteId),
        text: WriteValue.overlay(earlier.text, later.text),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(CommentPatch input) =>
      input.noteId.isMissing && input.text.isMissing;
}

/// Immutable input data; composition belongs to [commentInsert], not field names.
final class CommentInsert {
  final WriteValue<int, CommentFields> id;
  final WriteValue<int, CommentFields> noteId;
  final WriteValue<String, CommentFields> text;
  CommentInsert._({
    required this.id,
    required this.noteId,
    required this.text,
  }) {
    if (noteId.isMissing) {
      throw ArgumentError.value(noteId, 'noteId', 'Must be supplied.');
    }
    if (text.isMissing) {
      throw ArgumentError.value(text, 'text', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(CommentFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.noteId.write(noteId, fields),
    ...fields.text.write(text, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class CommentInsertFactory {
  CommentInsert call({int id, required int noteId, required String text});
  CommentInsert values({
    WriteValue<int, CommentFields> id = const .keep(),
    required WriteValue<int, CommentFields> noteId,
    required WriteValue<String, CommentFields> text,
  });
  CommentInsert overlay(CommentInsert earlier, Iterable<CommentPatch> layers);
}

const CommentInsertFactory commentInsert = _CommentInsertFactory();

final class _CommentInsertFactory implements CommentInsertFactory {
  const _CommentInsertFactory();
  @override
  CommentInsert call({
    Object? id = _writeAbsent,
    required int noteId,
    required String text,
  }) => CommentInsert._(
    id: _writeLiteral<int, CommentFields>(id),
    noteId: .set(noteId),
    text: .set(text),
  );
  @override
  CommentInsert values({
    WriteValue<int, CommentFields> id = const .keep(),
    required WriteValue<int, CommentFields> noteId,
    required WriteValue<String, CommentFields> text,
  }) => CommentInsert._(id: id, noteId: noteId, text: text);
  @override
  CommentInsert overlay(CommentInsert earlier, Iterable<CommentPatch> layers) {
    for (final later in layers) {
      earlier = CommentInsert._(
        id: earlier.id,
        noteId: WriteValue.overlay(earlier.noteId, later.noteId),
        text: WriteValue.overlay(earlier.text, later.text),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Comment from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class CommentCreator {
  Future<models.Comment> call({
    int id,
    required int noteId,
    required String text,
  });
}

final class _CommentCreator implements CommentCreator {
  final CommentTableSet _table;
  const _CommentCreator(this._table);
  @override
  Future<models.Comment> call({
    Object? id = _writeAbsent,
    required int noteId,
    required String text,
  }) async => _table.plan
      .insert(
        CommentInsert._(
          id: _writeLiteral<int, CommentFields>(id),
          noteId: .set(noteId),
          text: .set(text),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class CommentPatcher {
  Future<int> call({int noteId, String text});
}

final class _CommentPatcher implements CommentPatcher {
  final orm_model.ModelQuery<models.Comment, CommentFields, CommentPatch>
  _query;
  const _CommentPatcher(this._query);
  @override
  Future<int> call({
    Object? noteId = _writeAbsent,
    Object? text = _writeAbsent,
  }) => _query.update(
    CommentPatch._(
      noteId: _writeLiteral<int, CommentFields>(noteId),
      text: _writeLiteral<String, CommentFields>(text),
    ),
  );
}

/// Named literal updates on a complete models.Comment query.
extension CommentWrites
    on orm_model.ModelQuery<models.Comment, CommentFields, CommentPatch> {
  /// Executes one update; omitted fields remain unchanged.
  CommentPatcher get patch => _CommentPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class CommentTableSet
    extends
        orm_model.ModelTable<
          models.Comment,
          CommentFields,
          CommentInsert,
          CommentPatch
        > {
  CommentTableSet(QueryContext db)
    : super(
        db,
        commentTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final CommentCreator create = _CommentCreator(this);

  orm_model.ModelQuery<models.Comment, CommentFields, CommentPatch> byId(
    int id,
  ) => where((row) => row.id.eq(.value(id)));
}

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

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Comment, CommentFields> get comments =>
      Relation(commentTable, parent: [id], child: (row) => [row.noteId]);
}

final noteTable = Table<models.Note, NoteFields>(
  noteSchema,
  NoteFields.new,
  (row) => (row.id, row.text, row.done, row.createdAt).map(
    (v0, v1, v2, v3) => models.Note(id: v0, text: v1, done: v2, createdAt: v3),
  ),
);

/// Immutable input data; composition belongs to [notePatch], not field names.
final class NotePatch {
  final WriteValue<String, NoteFields> text;
  final WriteValue<bool, NoteFields> done;
  final WriteValue<DateTime, NoteFields> createdAt;
  NotePatch._({
    required this.text,
    required this.done,
    required this.createdAt,
  });

  List<Assignment> _assignments(NoteFields fields) => [
    ...fields.text.write(text, fields),
    ...fields.done.write(done, fields),
    ...fields.createdAt.write(createdAt, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class NotePatchFactory {
  NotePatch call({String text, bool done, DateTime createdAt});
  NotePatch values({
    WriteValue<String, NoteFields> text = const .keep(),
    WriteValue<bool, NoteFields> done = const .keep(),
    WriteValue<DateTime, NoteFields> createdAt = const .keep(),
  });
  NotePatch overlay(Iterable<NotePatch> layers);
  bool isEmpty(NotePatch input);
}

const NotePatchFactory notePatch = _NotePatchFactory();

final class _NotePatchFactory implements NotePatchFactory {
  const _NotePatchFactory();
  @override
  NotePatch call({
    Object? text = _writeAbsent,
    Object? done = _writeAbsent,
    Object? createdAt = _writeAbsent,
  }) => NotePatch._(
    text: _writeLiteral<String, NoteFields>(text),
    done: _writeLiteral<bool, NoteFields>(done),
    createdAt: _writeLiteral<DateTime, NoteFields>(createdAt),
  );
  @override
  NotePatch values({
    WriteValue<String, NoteFields> text = const .keep(),
    WriteValue<bool, NoteFields> done = const .keep(),
    WriteValue<DateTime, NoteFields> createdAt = const .keep(),
  }) => NotePatch._(text: text, done: done, createdAt: createdAt);
  @override
  NotePatch overlay(Iterable<NotePatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = NotePatch._(
        text: WriteValue.overlay(earlier.text, later.text),
        done: WriteValue.overlay(earlier.done, later.done),
        createdAt: WriteValue.overlay(earlier.createdAt, later.createdAt),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(NotePatch input) =>
      input.text.isMissing && input.done.isMissing && input.createdAt.isMissing;
}

/// Immutable input data; composition belongs to [noteInsert], not field names.
final class NoteInsert {
  final WriteValue<int, NoteFields> id;
  final WriteValue<String, NoteFields> text;
  final WriteValue<bool, NoteFields> done;
  final WriteValue<DateTime, NoteFields> createdAt;
  NoteInsert._({
    required this.id,
    required this.text,
    required this.done,
    required this.createdAt,
  }) {
    if (text.isMissing) {
      throw ArgumentError.value(text, 'text', 'Must be supplied.');
    }
    if (createdAt.isMissing) {
      throw ArgumentError.value(createdAt, 'createdAt', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(NoteFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.text.write(text, fields),
    ...fields.done.write(done, fields),
    ...fields.createdAt.write(createdAt, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class NoteInsertFactory {
  NoteInsert call({
    int id,
    required String text,
    bool done,
    required DateTime createdAt,
  });
  NoteInsert values({
    WriteValue<int, NoteFields> id = const .keep(),
    required WriteValue<String, NoteFields> text,
    WriteValue<bool, NoteFields> done = const .keep(),
    required WriteValue<DateTime, NoteFields> createdAt,
  });
  NoteInsert overlay(NoteInsert earlier, Iterable<NotePatch> layers);
}

const NoteInsertFactory noteInsert = _NoteInsertFactory();

final class _NoteInsertFactory implements NoteInsertFactory {
  const _NoteInsertFactory();
  @override
  NoteInsert call({
    Object? id = _writeAbsent,
    required String text,
    Object? done = _writeAbsent,
    required DateTime createdAt,
  }) => NoteInsert._(
    id: _writeLiteral<int, NoteFields>(id),
    text: .set(text),
    done: _writeLiteral<bool, NoteFields>(done),
    createdAt: .set(createdAt),
  );
  @override
  NoteInsert values({
    WriteValue<int, NoteFields> id = const .keep(),
    required WriteValue<String, NoteFields> text,
    WriteValue<bool, NoteFields> done = const .keep(),
    required WriteValue<DateTime, NoteFields> createdAt,
  }) => NoteInsert._(id: id, text: text, done: done, createdAt: createdAt);
  @override
  NoteInsert overlay(NoteInsert earlier, Iterable<NotePatch> layers) {
    for (final later in layers) {
      earlier = NoteInsert._(
        id: earlier.id,
        text: WriteValue.overlay(earlier.text, later.text),
        done: WriteValue.overlay(earlier.done, later.done),
        createdAt: WriteValue.overlay(earlier.createdAt, later.createdAt),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Note from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class NoteCreator {
  Future<models.Note> call({
    int id,
    required String text,
    bool done,
    required DateTime createdAt,
  });
}

final class _NoteCreator implements NoteCreator {
  final NoteTableSet _table;
  const _NoteCreator(this._table);
  @override
  Future<models.Note> call({
    Object? id = _writeAbsent,
    required String text,
    Object? done = _writeAbsent,
    required DateTime createdAt,
  }) async => _table.plan
      .insert(
        NoteInsert._(
          id: _writeLiteral<int, NoteFields>(id),
          text: .set(text),
          done: _writeLiteral<bool, NoteFields>(done),
          createdAt: .set(createdAt),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class NotePatcher {
  Future<int> call({String text, bool done, DateTime createdAt});
}

final class _NotePatcher implements NotePatcher {
  final orm_model.ModelQuery<models.Note, NoteFields, NotePatch> _query;
  const _NotePatcher(this._query);
  @override
  Future<int> call({
    Object? text = _writeAbsent,
    Object? done = _writeAbsent,
    Object? createdAt = _writeAbsent,
  }) => _query.update(
    NotePatch._(
      text: _writeLiteral<String, NoteFields>(text),
      done: _writeLiteral<bool, NoteFields>(done),
      createdAt: _writeLiteral<DateTime, NoteFields>(createdAt),
    ),
  );
}

/// Named literal updates on a complete models.Note query.
extension NoteWrites
    on orm_model.ModelQuery<models.Note, NoteFields, NotePatch> {
  /// Executes one update; omitted fields remain unchanged.
  NotePatcher get patch => _NotePatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class NoteTableSet
    extends
        orm_model.ModelTable<models.Note, NoteFields, NoteInsert, NotePatch> {
  NoteTableSet(QueryContext db)
    : super(
        db,
        noteTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final NoteCreator create = _NoteCreator(this);

  orm_model.ModelQuery<models.Note, NoteFields, NotePatch> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

final appSchema = List<TableSchema>.unmodifiable([commentSchema, noteSchema]);

extension AppTables on QueryContext {
  CommentTableSet get comment => CommentTableSet(this);
  NoteTableSet get note => NoteTableSet(this);
}
