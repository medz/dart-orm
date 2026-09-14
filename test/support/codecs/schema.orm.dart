// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/orm.dart';

import "schema.dart" as models;
import "types.dart" as types0;
import "alternate.dart" as types1;

final _peopleId = Column<types0.PersonId>(
  "id",
  types0.PersonId.codec,
  nullable: false,
  generated: true,
);
final _peopleEmail = Column<types0.Email>(
  "email",
  types0.Email.codec,
  nullable: false,
  generated: false,
);
final _peopleMembership = Column<types0.Membership>(
  "membership",
  Codecs.enumeration<types0.Membership>({
    types0.Membership.pending: "pending-payment",
    types0.Membership.active: "active",
    types0.Membership.cancelled: "closed",
  }),
  nullable: false,
  generated: false,
);
final _peoplePreviousMembership = Column<types0.Membership?>(
  "previous_membership",
  Codecs.enumeration<types0.Membership>({
    types0.Membership.pending: "pending-payment",
    types0.Membership.active: "active",
    types0.Membership.cancelled: "closed",
  }).nullable(),
  nullable: true,
  generated: false,
);
final _peopleTags = Column<List<String>>(
  "tags",
  types0.tagsCodec,
  nullable: false,
  generated: false,
);
final _peopleLocation = Column<types0.Location?>(
  "location",
  types0.locationCodec.nullable(),
  nullable: true,
  generated: false,
);
final _peopleAlternate = Column<types1.Email>(
  "alternate",
  types1.emailCodec,
  nullable: false,
  generated: false,
);
final _peopleDetails = Column<SqlJson?>(
  "details",
  Codecs.jsonDocument.nullable(),
  nullable: true,
  generated: false,
);
final peopleSchema = TableSchema(
  "people",
  columns: [
    _peopleId,
    _peopleEmail,
    _peopleMembership,
    _peoplePreviousMembership,
    _peopleTags,
    _peopleLocation,
    _peopleAlternate,
    _peopleDetails,
  ],
  primaryKey: ["id"],
  uniqueKeys: [
    ["email"],
  ],
  indexes: [],
  foreignKeys: [],
);

final class PeopleFields extends Fields {
  PeopleFields(super.table);
  late final id = column(_peopleId);
  late final email = column(_peopleEmail);
  late final membership = column(_peopleMembership);
  late final previousMembership = column(_peoplePreviousMembership);
  late final tags = column(_peopleTags);
  late final location = column(_peopleLocation);
  late final alternate = column(_peopleAlternate);
  late final details = column(_peopleDetails);
  Relation<models.Note, NotesFields> get notes =>
      Relation(notesTable, parent: [id], child: (row) => [row.ownerId]);
}

final peopleTable = Table<models.Person, PeopleFields>(
  peopleSchema,
  PeopleFields.new,
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
        (left, right) => (
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

final class PeopleTableSet extends TableSet<models.Person, PeopleFields> {
  PeopleTableSet(Database<Backend> db) : super(db, peopleTable);
  Future<models.Person> create({
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
  Query<models.Person, PeopleFields> byId(types0.PersonId id) =>
      where((row) => row.id.eq(id));
}

extension PeopleUpdates on Query<models.Person, PeopleFields> {
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

final _notesId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _notesOwnerId = Column<types0.PersonId>(
  "owner_id",
  types0.PersonId.codec,
  nullable: false,
  generated: false,
);
final _notesBody = Column<String>(
  "body",
  Codecs.text,
  nullable: false,
  generated: false,
);
final notesSchema = TableSchema(
  "notes",
  columns: [_notesId, _notesOwnerId, _notesBody],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [
    ForeignKey(["owner_id"], "people", ["id"], onDelete: "RESTRICT"),
  ],
);

final class NotesFields extends Fields {
  NotesFields(super.table);
  late final id = column(_notesId);
  late final ownerId = column(_notesOwnerId);
  late final body = column(_notesBody);
  Relation<models.Person, PeopleFields> get owner =>
      Relation(peopleTable, parent: [ownerId], child: (row) => [row.id]);
}

final notesTable = Table<models.Note, NotesFields>(
  notesSchema,
  NotesFields.new,
  (row) => (
    row.id,
    row.ownerId,
    row.body,
  ).map((id, ownerId, body) => (id: id, ownerId: ownerId, body: body)),
);

final class NotesTableSet extends TableSet<models.Note, NotesFields> {
  NotesTableSet(Database<Backend> db) : super(db, notesTable);
  Future<models.Note> create({
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
  Query<models.Note, NotesFields> byId(int id) => where((row) => row.id.eq(id));
}

extension NotesUpdates on Query<models.Note, NotesFields> {
  Future<int> patch({
    Change<types0.PersonId> ownerId = const Change.keep(),
    Change<String> body = const Change.keep(),
  }) => update(
    (row) => [...row.ownerId.change(ownerId), ...row.body.change(body)],
  ).execute();
}

final appSchema = <TableSchema>[peopleSchema, notesSchema];

extension AppTables<B extends Backend> on Database<B> {
  PeopleTableSet get people => PeopleTableSet(this);
  NotesTableSet get notes => NotesTableSet(this);
}
