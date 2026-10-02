// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/orm.dart' as orm_model show ModelTable, ModelQuery;
import 'package:orm/values.dart';
import "package:orm_flutter/legacy/schema.dart" as models;
export "package:orm_flutter/legacy/schema.dart" show Note;

final class _OrmWriteAbsent {
  const _OrmWriteAbsent();
}

const _writeAbsent = _OrmWriteAbsent();
WriteValue<T, F> _writeLiteral<T, F extends Fields>(Object? value) =>
    identical(value, _writeAbsent) ? const .keep() : .set(value as T);

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

final noteTable = Table<models.Note, NoteFields>(
  noteSchema,
  NoteFields.new,
  (row) => (
    row.id,
    row.body,
    row.createdAt,
  ).map((v0, v1, v2) => models.Note(id: v0, body: v1, createdAt: v2)),
);

/// Immutable input data; composition belongs to [notePatch], not field names.
final class NotePatch {
  final WriteValue<String, NoteFields> body;
  final WriteValue<DateTime, NoteFields> createdAt;
  NotePatch._({required this.body, required this.createdAt});

  List<Assignment> _assignments(NoteFields fields) => [
    ...fields.body.write(body, fields),
    ...fields.createdAt.write(createdAt, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class NotePatchFactory {
  NotePatch call({String body, DateTime createdAt});
  NotePatch values({
    WriteValue<String, NoteFields> body = const .keep(),
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
    Object? body = _writeAbsent,
    Object? createdAt = _writeAbsent,
  }) => NotePatch._(
    body: _writeLiteral<String, NoteFields>(body),
    createdAt: _writeLiteral<DateTime, NoteFields>(createdAt),
  );
  @override
  NotePatch values({
    WriteValue<String, NoteFields> body = const .keep(),
    WriteValue<DateTime, NoteFields> createdAt = const .keep(),
  }) => NotePatch._(body: body, createdAt: createdAt);
  @override
  NotePatch overlay(Iterable<NotePatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = NotePatch._(
        body: WriteValue.overlay(earlier.body, later.body),
        createdAt: WriteValue.overlay(earlier.createdAt, later.createdAt),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(NotePatch input) =>
      input.body.isMissing && input.createdAt.isMissing;
}

/// Immutable input data; composition belongs to [noteInsert], not field names.
final class NoteInsert {
  final WriteValue<int, NoteFields> id;
  final WriteValue<String, NoteFields> body;
  final WriteValue<DateTime, NoteFields> createdAt;
  NoteInsert._({
    required this.id,
    required this.body,
    required this.createdAt,
  }) {
    if (body.isMissing) {
      throw ArgumentError.value(body, 'body', 'Must be supplied.');
    }
    if (createdAt.isMissing) {
      throw ArgumentError.value(createdAt, 'createdAt', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(NoteFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.body.write(body, fields),
    ...fields.createdAt.write(createdAt, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class NoteInsertFactory {
  NoteInsert call({int id, required String body, required DateTime createdAt});
  NoteInsert values({
    WriteValue<int, NoteFields> id = const .keep(),
    required WriteValue<String, NoteFields> body,
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
    required String body,
    required DateTime createdAt,
  }) => NoteInsert._(
    id: _writeLiteral<int, NoteFields>(id),
    body: .set(body),
    createdAt: .set(createdAt),
  );
  @override
  NoteInsert values({
    WriteValue<int, NoteFields> id = const .keep(),
    required WriteValue<String, NoteFields> body,
    required WriteValue<DateTime, NoteFields> createdAt,
  }) => NoteInsert._(id: id, body: body, createdAt: createdAt);
  @override
  NoteInsert overlay(NoteInsert earlier, Iterable<NotePatch> layers) {
    for (final later in layers) {
      earlier = NoteInsert._(
        id: earlier.id,
        body: WriteValue.overlay(earlier.body, later.body),
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
    required String body,
    required DateTime createdAt,
  });
}

final class _NoteCreator implements NoteCreator {
  final NoteTableSet _table;
  const _NoteCreator(this._table);
  @override
  Future<models.Note> call({
    Object? id = _writeAbsent,
    required String body,
    required DateTime createdAt,
  }) async => _table.plan
      .insert(
        NoteInsert._(
          id: _writeLiteral<int, NoteFields>(id),
          body: .set(body),
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
  Future<int> call({String body, DateTime createdAt});
}

final class _NotePatcher implements NotePatcher {
  final orm_model.ModelQuery<models.Note, NoteFields, NotePatch> _query;
  const _NotePatcher(this._query);
  @override
  Future<int> call({
    Object? body = _writeAbsent,
    Object? createdAt = _writeAbsent,
  }) => _query.update(
    NotePatch._(
      body: _writeLiteral<String, NoteFields>(body),
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

final appSchema = List<TableSchema>.unmodifiable([noteSchema]);

extension AppTables on QueryContext {
  NoteTableSet get note => NoteTableSet(this);
}
