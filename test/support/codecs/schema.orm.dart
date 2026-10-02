// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/orm.dart' as orm_model show ModelTable, ModelQuery;
import 'package:orm/values.dart';

import "schema.dart" as models;
export "types.dart" show PersonId, Membership, Location;
export "schema.dart" show Person, Note;
import "types.dart" as types0;
import "alternate.dart" as types1;

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
final _noteOwnerId = Column<types0.PersonId>(
  "owner_id",
  types0.PersonId.codec,
  nullable: false,
  generated: false,
);
final _noteBody = Column<String>(
  "body",
  Codecs.text,
  nullable: false,
  generated: false,
);
final noteSchema = TableSchema(
  "notes",
  columns: [_noteId, _noteOwnerId, _noteBody],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [
    ForeignKey(["owner_id"], "people", ["id"], onDelete: "RESTRICT"),
  ],
);

final class NoteFields extends Fields {
  NoteFields(super.table);
  late final id = column(_noteId);
  late final ownerId = column(_noteOwnerId);
  late final body = column(_noteBody);
  Relation<models.Person, PersonFields> get owner =>
      Relation(personTable, parent: [ownerId], child: (row) => [row.id]);
}

final noteTable = Table<models.Note, NoteFields>(
  noteSchema,
  NoteFields.new,
  (row) => (
    row.id,
    row.ownerId,
    row.body,
  ).map((v0, v1, v2) => models.Note(id: v0, ownerId: v1, body: v2)),
);

/// Immutable input data; composition belongs to [notePatch], not field names.
final class NotePatch {
  final WriteValue<types0.PersonId, NoteFields> ownerId;
  final WriteValue<String, NoteFields> body;
  NotePatch._({required this.ownerId, required this.body});

  List<Assignment> _assignments(NoteFields fields) => [
    ...fields.ownerId.write(ownerId, fields),
    ...fields.body.write(body, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class NotePatchFactory {
  NotePatch call({types0.PersonId ownerId, String body});
  NotePatch values({
    WriteValue<types0.PersonId, NoteFields> ownerId = const .keep(),
    WriteValue<String, NoteFields> body = const .keep(),
  });
  NotePatch overlay(Iterable<NotePatch> layers);
  bool isEmpty(NotePatch input);
}

const NotePatchFactory notePatch = _NotePatchFactory();

final class _NotePatchFactory implements NotePatchFactory {
  const _NotePatchFactory();
  @override
  NotePatch call({
    Object? ownerId = _writeAbsent,
    Object? body = _writeAbsent,
  }) => NotePatch._(
    ownerId: _writeLiteral<types0.PersonId, NoteFields>(ownerId),
    body: _writeLiteral<String, NoteFields>(body),
  );
  @override
  NotePatch values({
    WriteValue<types0.PersonId, NoteFields> ownerId = const .keep(),
    WriteValue<String, NoteFields> body = const .keep(),
  }) => NotePatch._(ownerId: ownerId, body: body);
  @override
  NotePatch overlay(Iterable<NotePatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = NotePatch._(
        ownerId: WriteValue.overlay(earlier.ownerId, later.ownerId),
        body: WriteValue.overlay(earlier.body, later.body),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(NotePatch input) =>
      input.ownerId.isMissing && input.body.isMissing;
}

/// Immutable input data; composition belongs to [noteInsert], not field names.
final class NoteInsert {
  final WriteValue<int, NoteFields> id;
  final WriteValue<types0.PersonId, NoteFields> ownerId;
  final WriteValue<String, NoteFields> body;
  NoteInsert._({required this.id, required this.ownerId, required this.body}) {
    if (ownerId.isMissing) {
      throw ArgumentError.value(ownerId, 'ownerId', 'Must be supplied.');
    }
    if (body.isMissing) {
      throw ArgumentError.value(body, 'body', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(NoteFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.ownerId.write(ownerId, fields),
    ...fields.body.write(body, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class NoteInsertFactory {
  NoteInsert call({
    int id,
    required types0.PersonId ownerId,
    required String body,
  });
  NoteInsert values({
    WriteValue<int, NoteFields> id = const .keep(),
    required WriteValue<types0.PersonId, NoteFields> ownerId,
    required WriteValue<String, NoteFields> body,
  });
  NoteInsert overlay(NoteInsert earlier, Iterable<NotePatch> layers);
}

const NoteInsertFactory noteInsert = _NoteInsertFactory();

final class _NoteInsertFactory implements NoteInsertFactory {
  const _NoteInsertFactory();
  @override
  NoteInsert call({
    Object? id = _writeAbsent,
    required types0.PersonId ownerId,
    required String body,
  }) => NoteInsert._(
    id: _writeLiteral<int, NoteFields>(id),
    ownerId: .set(ownerId),
    body: .set(body),
  );
  @override
  NoteInsert values({
    WriteValue<int, NoteFields> id = const .keep(),
    required WriteValue<types0.PersonId, NoteFields> ownerId,
    required WriteValue<String, NoteFields> body,
  }) => NoteInsert._(id: id, ownerId: ownerId, body: body);
  @override
  NoteInsert overlay(NoteInsert earlier, Iterable<NotePatch> layers) {
    for (final later in layers) {
      earlier = NoteInsert._(
        id: earlier.id,
        ownerId: WriteValue.overlay(earlier.ownerId, later.ownerId),
        body: WriteValue.overlay(earlier.body, later.body),
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
    required types0.PersonId ownerId,
    required String body,
  });
}

final class _NoteCreator implements NoteCreator {
  final NoteTableSet _table;
  const _NoteCreator(this._table);
  @override
  Future<models.Note> call({
    Object? id = _writeAbsent,
    required types0.PersonId ownerId,
    required String body,
  }) async => _table.plan
      .insert(
        NoteInsert._(
          id: _writeLiteral<int, NoteFields>(id),
          ownerId: .set(ownerId),
          body: .set(body),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class NotePatcher {
  Future<int> call({types0.PersonId ownerId, String body});
}

final class _NotePatcher implements NotePatcher {
  final orm_model.ModelQuery<models.Note, NoteFields, NotePatch> _query;
  const _NotePatcher(this._query);
  @override
  Future<int> call({
    Object? ownerId = _writeAbsent,
    Object? body = _writeAbsent,
  }) => _query.update(
    NotePatch._(
      ownerId: _writeLiteral<types0.PersonId, NoteFields>(ownerId),
      body: _writeLiteral<String, NoteFields>(body),
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

final _personId = Column<types0.PersonId>(
  "id",
  types0.PersonId.codec,
  nullable: false,
  generated: true,
);
final _personEmail = Column<types0.Email>(
  "email",
  types0.Email.codec,
  nullable: false,
  generated: false,
);
final _personMembership = Column<types0.Membership>(
  "membership",
  Codecs.enumeration<types0.Membership>({
    types0.Membership.pending: "pending-payment",
    types0.Membership.active: "active",
    types0.Membership.cancelled: "closed",
  }),
  nullable: false,
  generated: false,
);
final _personPreviousMembership = Column<types0.Membership?>(
  "previous_membership",
  Codecs.enumeration<types0.Membership>({
    types0.Membership.pending: "pending-payment",
    types0.Membership.active: "active",
    types0.Membership.cancelled: "closed",
  }).nullable(),
  nullable: true,
  generated: false,
);
final _personTags = Column<List<String>>(
  "tags",
  types0.tagsCodec,
  nullable: false,
  generated: false,
);
final _personLocation = Column<types0.Location?>(
  "location",
  types0.locationCodec.nullable(),
  nullable: true,
  generated: false,
);
final _personAlternate = Column<types1.Email>(
  "alternate",
  types1.emailCodec,
  nullable: false,
  generated: false,
);
final _personDetails = Column<SqlJson?>(
  "details",
  Codecs.jsonDocument.nullable(),
  nullable: true,
  generated: false,
);
final personSchema = TableSchema(
  "people",
  columns: [
    _personId,
    _personEmail,
    _personMembership,
    _personPreviousMembership,
    _personTags,
    _personLocation,
    _personAlternate,
    _personDetails,
  ],
  primaryKey: ["id"],
  uniqueKeys: [
    ["email"],
  ],
  indexes: [],
  foreignKeys: [],
);

final class PersonFields extends Fields {
  PersonFields(super.table);
  late final id = column(_personId);
  late final email = column(_personEmail);
  late final membership = column(_personMembership);
  late final previousMembership = column(_personPreviousMembership);
  late final tags = column(_personTags);
  late final location = column(_personLocation);
  late final alternate = column(_personAlternate);
  late final details = column(_personDetails);

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Note, NoteFields> get notes =>
      Relation(noteTable, parent: [id], child: (row) => [row.ownerId]);
}

final personTable = Table<models.Person, PersonFields>(
  personSchema,
  PersonFields.new,
  (row) =>
      (
        (
          row.id,
          row.email,
          row.membership,
          row.previousMembership,
          row.tags,
        ).map(
          (id, email, membership, previousMembership, tags) => (
            id: id,
            email: email,
            membership: membership,
            previousMembership: previousMembership,
            tags: tags,
          ),
        ),
        (row.location, row.alternate, row.details).map(
          (location, alternate, details) =>
              (location: location, alternate: alternate, details: details),
        ),
      ).map(
        (left, right) => models.Person(
          id: left.id,
          email: left.email,
          membership: left.membership,
          previousMembership: left.previousMembership,
          tags: left.tags,
          location: right.location,
          alternate: right.alternate,
          details: right.details,
        ),
      ),
);

/// Immutable input data; composition belongs to [personPatch], not field names.
final class PersonPatch {
  final WriteValue<types0.Email, PersonFields> email;
  final WriteValue<types0.Membership, PersonFields> membership;
  final WriteValue<types0.Membership?, PersonFields> previousMembership;
  final WriteValue<List<String>, PersonFields> tags;
  final WriteValue<types0.Location?, PersonFields> location;
  final WriteValue<types1.Email, PersonFields> alternate;
  final WriteValue<SqlJson?, PersonFields> details;
  PersonPatch._({
    required this.email,
    required this.membership,
    required this.previousMembership,
    required this.tags,
    required this.location,
    required this.alternate,
    required this.details,
  });

  List<Assignment> _assignments(PersonFields fields) => [
    ...fields.email.write(email, fields),
    ...fields.membership.write(membership, fields),
    ...fields.previousMembership.write(previousMembership, fields),
    ...fields.tags.write(tags, fields),
    ...fields.location.write(location, fields),
    ...fields.alternate.write(alternate, fields),
    ...fields.details.write(details, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class PersonPatchFactory {
  PersonPatch call({
    types0.Email email,
    types0.Membership membership,
    types0.Membership? previousMembership,
    List<String> tags,
    types0.Location? location,
    types1.Email alternate,
    SqlJson? details,
  });
  PersonPatch values({
    WriteValue<types0.Email, PersonFields> email = const .keep(),
    WriteValue<types0.Membership, PersonFields> membership = const .keep(),
    WriteValue<types0.Membership?, PersonFields> previousMembership =
        const .keep(),
    WriteValue<List<String>, PersonFields> tags = const .keep(),
    WriteValue<types0.Location?, PersonFields> location = const .keep(),
    WriteValue<types1.Email, PersonFields> alternate = const .keep(),
    WriteValue<SqlJson?, PersonFields> details = const .keep(),
  });
  PersonPatch overlay(Iterable<PersonPatch> layers);
  bool isEmpty(PersonPatch input);
}

const PersonPatchFactory personPatch = _PersonPatchFactory();

final class _PersonPatchFactory implements PersonPatchFactory {
  const _PersonPatchFactory();
  @override
  PersonPatch call({
    Object? email = _writeAbsent,
    Object? membership = _writeAbsent,
    Object? previousMembership = _writeAbsent,
    Object? tags = _writeAbsent,
    Object? location = _writeAbsent,
    Object? alternate = _writeAbsent,
    Object? details = _writeAbsent,
  }) => PersonPatch._(
    email: _writeLiteral<types0.Email, PersonFields>(email),
    membership: _writeLiteral<types0.Membership, PersonFields>(membership),
    previousMembership: _writeLiteral<types0.Membership?, PersonFields>(
      previousMembership,
    ),
    tags: _writeLiteral<List<String>, PersonFields>(tags),
    location: _writeLiteral<types0.Location?, PersonFields>(location),
    alternate: _writeLiteral<types1.Email, PersonFields>(alternate),
    details: _writeLiteral<SqlJson?, PersonFields>(details),
  );
  @override
  PersonPatch values({
    WriteValue<types0.Email, PersonFields> email = const .keep(),
    WriteValue<types0.Membership, PersonFields> membership = const .keep(),
    WriteValue<types0.Membership?, PersonFields> previousMembership =
        const .keep(),
    WriteValue<List<String>, PersonFields> tags = const .keep(),
    WriteValue<types0.Location?, PersonFields> location = const .keep(),
    WriteValue<types1.Email, PersonFields> alternate = const .keep(),
    WriteValue<SqlJson?, PersonFields> details = const .keep(),
  }) => PersonPatch._(
    email: email,
    membership: membership,
    previousMembership: previousMembership,
    tags: tags,
    location: location,
    alternate: alternate,
    details: details,
  );
  @override
  PersonPatch overlay(Iterable<PersonPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = PersonPatch._(
        email: WriteValue.overlay(earlier.email, later.email),
        membership: WriteValue.overlay(earlier.membership, later.membership),
        previousMembership: WriteValue.overlay(
          earlier.previousMembership,
          later.previousMembership,
        ),
        tags: WriteValue.overlay(earlier.tags, later.tags),
        location: WriteValue.overlay(earlier.location, later.location),
        alternate: WriteValue.overlay(earlier.alternate, later.alternate),
        details: WriteValue.overlay(earlier.details, later.details),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(PersonPatch input) =>
      input.email.isMissing &&
      input.membership.isMissing &&
      input.previousMembership.isMissing &&
      input.tags.isMissing &&
      input.location.isMissing &&
      input.alternate.isMissing &&
      input.details.isMissing;
}

/// Immutable input data; composition belongs to [personInsert], not field names.
final class PersonInsert {
  final WriteValue<types0.PersonId, PersonFields> id;
  final WriteValue<types0.Email, PersonFields> email;
  final WriteValue<types0.Membership, PersonFields> membership;
  final WriteValue<types0.Membership?, PersonFields> previousMembership;
  final WriteValue<List<String>, PersonFields> tags;
  final WriteValue<types0.Location?, PersonFields> location;
  final WriteValue<types1.Email, PersonFields> alternate;
  final WriteValue<SqlJson?, PersonFields> details;
  PersonInsert._({
    required this.id,
    required this.email,
    required this.membership,
    required this.previousMembership,
    required this.tags,
    required this.location,
    required this.alternate,
    required this.details,
  }) {
    if (email.isMissing) {
      throw ArgumentError.value(email, 'email', 'Must be supplied.');
    }
    if (membership.isMissing) {
      throw ArgumentError.value(membership, 'membership', 'Must be supplied.');
    }
    if (tags.isMissing) {
      throw ArgumentError.value(tags, 'tags', 'Must be supplied.');
    }
    if (alternate.isMissing) {
      throw ArgumentError.value(alternate, 'alternate', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(PersonFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.email.write(email, fields),
    ...fields.membership.write(membership, fields),
    ...fields.previousMembership.write(previousMembership, fields),
    ...fields.tags.write(tags, fields),
    ...fields.location.write(location, fields),
    ...fields.alternate.write(alternate, fields),
    ...fields.details.write(details, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class PersonInsertFactory {
  PersonInsert call({
    types0.PersonId id,
    required types0.Email email,
    required types0.Membership membership,
    types0.Membership? previousMembership,
    required List<String> tags,
    types0.Location? location,
    required types1.Email alternate,
    SqlJson? details,
  });
  PersonInsert values({
    WriteValue<types0.PersonId, PersonFields> id = const .keep(),
    required WriteValue<types0.Email, PersonFields> email,
    required WriteValue<types0.Membership, PersonFields> membership,
    WriteValue<types0.Membership?, PersonFields> previousMembership =
        const .keep(),
    required WriteValue<List<String>, PersonFields> tags,
    WriteValue<types0.Location?, PersonFields> location = const .keep(),
    required WriteValue<types1.Email, PersonFields> alternate,
    WriteValue<SqlJson?, PersonFields> details = const .keep(),
  });
  PersonInsert overlay(PersonInsert earlier, Iterable<PersonPatch> layers);
}

const PersonInsertFactory personInsert = _PersonInsertFactory();

final class _PersonInsertFactory implements PersonInsertFactory {
  const _PersonInsertFactory();
  @override
  PersonInsert call({
    Object? id = _writeAbsent,
    required types0.Email email,
    required types0.Membership membership,
    Object? previousMembership = _writeAbsent,
    required List<String> tags,
    Object? location = _writeAbsent,
    required types1.Email alternate,
    Object? details = _writeAbsent,
  }) => PersonInsert._(
    id: _writeLiteral<types0.PersonId, PersonFields>(id),
    email: .set(email),
    membership: .set(membership),
    previousMembership: _writeLiteral<types0.Membership?, PersonFields>(
      previousMembership,
    ),
    tags: .set(tags),
    location: _writeLiteral<types0.Location?, PersonFields>(location),
    alternate: .set(alternate),
    details: _writeLiteral<SqlJson?, PersonFields>(details),
  );
  @override
  PersonInsert values({
    WriteValue<types0.PersonId, PersonFields> id = const .keep(),
    required WriteValue<types0.Email, PersonFields> email,
    required WriteValue<types0.Membership, PersonFields> membership,
    WriteValue<types0.Membership?, PersonFields> previousMembership =
        const .keep(),
    required WriteValue<List<String>, PersonFields> tags,
    WriteValue<types0.Location?, PersonFields> location = const .keep(),
    required WriteValue<types1.Email, PersonFields> alternate,
    WriteValue<SqlJson?, PersonFields> details = const .keep(),
  }) => PersonInsert._(
    id: id,
    email: email,
    membership: membership,
    previousMembership: previousMembership,
    tags: tags,
    location: location,
    alternate: alternate,
    details: details,
  );
  @override
  PersonInsert overlay(PersonInsert earlier, Iterable<PersonPatch> layers) {
    for (final later in layers) {
      earlier = PersonInsert._(
        id: earlier.id,
        email: WriteValue.overlay(earlier.email, later.email),
        membership: WriteValue.overlay(earlier.membership, later.membership),
        previousMembership: WriteValue.overlay(
          earlier.previousMembership,
          later.previousMembership,
        ),
        tags: WriteValue.overlay(earlier.tags, later.tags),
        location: WriteValue.overlay(earlier.location, later.location),
        alternate: WriteValue.overlay(earlier.alternate, later.alternate),
        details: WriteValue.overlay(earlier.details, later.details),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Person from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class PersonCreator {
  Future<models.Person> call({
    types0.PersonId id,
    required types0.Email email,
    required types0.Membership membership,
    types0.Membership? previousMembership,
    required List<String> tags,
    types0.Location? location,
    required types1.Email alternate,
    SqlJson? details,
  });
}

final class _PersonCreator implements PersonCreator {
  final PersonTableSet _table;
  const _PersonCreator(this._table);
  @override
  Future<models.Person> call({
    Object? id = _writeAbsent,
    required types0.Email email,
    required types0.Membership membership,
    Object? previousMembership = _writeAbsent,
    required List<String> tags,
    Object? location = _writeAbsent,
    required types1.Email alternate,
    Object? details = _writeAbsent,
  }) async => _table.plan
      .insert(
        PersonInsert._(
          id: _writeLiteral<types0.PersonId, PersonFields>(id),
          email: .set(email),
          membership: .set(membership),
          previousMembership: _writeLiteral<types0.Membership?, PersonFields>(
            previousMembership,
          ),
          tags: .set(tags),
          location: _writeLiteral<types0.Location?, PersonFields>(location),
          alternate: .set(alternate),
          details: _writeLiteral<SqlJson?, PersonFields>(details),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class PersonPatcher {
  Future<int> call({
    types0.Email email,
    types0.Membership membership,
    types0.Membership? previousMembership,
    List<String> tags,
    types0.Location? location,
    types1.Email alternate,
    SqlJson? details,
  });
}

final class _PersonPatcher implements PersonPatcher {
  final orm_model.ModelQuery<models.Person, PersonFields, PersonPatch> _query;
  const _PersonPatcher(this._query);
  @override
  Future<int> call({
    Object? email = _writeAbsent,
    Object? membership = _writeAbsent,
    Object? previousMembership = _writeAbsent,
    Object? tags = _writeAbsent,
    Object? location = _writeAbsent,
    Object? alternate = _writeAbsent,
    Object? details = _writeAbsent,
  }) => _query.update(
    PersonPatch._(
      email: _writeLiteral<types0.Email, PersonFields>(email),
      membership: _writeLiteral<types0.Membership, PersonFields>(membership),
      previousMembership: _writeLiteral<types0.Membership?, PersonFields>(
        previousMembership,
      ),
      tags: _writeLiteral<List<String>, PersonFields>(tags),
      location: _writeLiteral<types0.Location?, PersonFields>(location),
      alternate: _writeLiteral<types1.Email, PersonFields>(alternate),
      details: _writeLiteral<SqlJson?, PersonFields>(details),
    ),
  );
}

/// Named literal updates on a complete models.Person query.
extension PersonWrites
    on orm_model.ModelQuery<models.Person, PersonFields, PersonPatch> {
  /// Executes one update; omitted fields remain unchanged.
  PersonPatcher get patch => _PersonPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class PersonTableSet
    extends
        orm_model.ModelTable<
          models.Person,
          PersonFields,
          PersonInsert,
          PersonPatch
        > {
  PersonTableSet(QueryContext db)
    : super(
        db,
        personTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final PersonCreator create = _PersonCreator(this);

  orm_model.ModelQuery<models.Person, PersonFields, PersonPatch> byId(
    types0.PersonId id,
  ) => where((row) => row.id.eq(.value(id)));
}

final appSchema = List<TableSchema>.unmodifiable([noteSchema, personSchema]);

extension AppTables on QueryContext {
  NoteTableSet get note => NoteTableSet(this);
  PersonTableSet get person => PersonTableSet(this);
}
