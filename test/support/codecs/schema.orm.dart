// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';

export "types.dart" show PersonId, Membership, Location;
import "types.dart" as types0;
import "alternate.dart" as types1;

/// A complete immutable row from "people".
final class Person({
  required final types0.PersonId id,
  required final types0.Email email,
  required final types0.Membership membership,
  required final types0.Membership? previousMembership,
  required final List<String> tags,
  required final types0.Location? location,
  required final types1.Email alternate,
  required final SqlJson? details,
});
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
  Relation<Note, NoteFields> get notes =>
      Relation(noteTable, parent: [id], child: (row) => [row.ownerId]);
}

final personTable = Table<Person, PersonFields>(
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
        (left, right) => Person(
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

final class PersonTableSet extends TableSet<Person, PersonFields> {
  PersonTableSet(QueryContext db) : super(db, personTable) {
    db.registerSchema(appSchema);
  }
  Future<Person> create({
    Change<types0.PersonId> id = const Change.keep(),
    required types0.Email email,
    required types0.Membership membership,
    types0.Membership? previousMembership,
    required List<String> tags,
    types0.Location? location,
    required types1.Email alternate,
    SqlJson? details,
  }) => createRow(
    (row) => [
      ...row.id.change(id),
      row.email.set(email),
      row.membership.set(membership),
      row.previousMembership.set(previousMembership),
      row.tags.set(tags),
      row.location.set(location),
      row.alternate.set(alternate),
      row.details.set(details),
    ],
  );
  Query<Person, PersonFields> byId(types0.PersonId id) =>
      where((row) => row.id.eq(id));
}

extension PersonUpdates on Query<Person, PersonFields> {
  Future<int> patch({
    Change<types0.Email> email = const Change.keep(),
    Change<types0.Membership> membership = const Change.keep(),
    Change<types0.Membership?> previousMembership = const Change.keep(),
    Change<List<String>> tags = const Change.keep(),
    Change<types0.Location?> location = const Change.keep(),
    Change<types1.Email> alternate = const Change.keep(),
    Change<SqlJson?> details = const Change.keep(),
  }) => update(
    (row) => [
      ...row.email.change(email),
      ...row.membership.change(membership),
      ...row.previousMembership.change(previousMembership),
      ...row.tags.change(tags),
      ...row.location.change(location),
      ...row.alternate.change(alternate),
      ...row.details.change(details),
    ],
  ).execute();
}

/// A complete immutable row from "notes".
final class Note({
  required final int id,
  required final types0.PersonId ownerId,
  required final String body,
});
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
  Relation<Person, PersonFields> get owner =>
      Relation(personTable, parent: [ownerId], child: (row) => [row.id]);
}

final noteTable = Table<Note, NoteFields>(
  noteSchema,
  NoteFields.new,
  (row) => (
    row.id,
    row.ownerId,
    row.body,
  ).map((v0, v1, v2) => Note(id: v0, ownerId: v1, body: v2)),
);

final class NoteTableSet extends TableSet<Note, NoteFields> {
  NoteTableSet(QueryContext db) : super(db, noteTable) {
    db.registerSchema(appSchema);
  }
  Future<Note> create({
    Change<int> id = const Change.keep(),
    required types0.PersonId ownerId,
    required String body,
  }) => createRow(
    (row) => [
      ...row.id.change(id),
      row.ownerId.set(ownerId),
      row.body.set(body),
    ],
  );
  Query<Note, NoteFields> byId(int id) => where((row) => row.id.eq(id));
}

extension NoteUpdates on Query<Note, NoteFields> {
  Future<int> patch({
    Change<types0.PersonId> ownerId = const Change.keep(),
    Change<String> body = const Change.keep(),
  }) => update(
    (row) => [...row.ownerId.change(ownerId), ...row.body.change(body)],
  ).execute();
}

final appSchema = List<TableSchema>.unmodifiable([personSchema, noteSchema]);

extension AppTables on QueryContext {
  PersonTableSet get person => PersonTableSet(this);
  NoteTableSet get note => NoteTableSet(this);
}
