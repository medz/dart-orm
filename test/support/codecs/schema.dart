import 'package:orm/values.dart';
import 'package:orm/schema.dart';

import 'types.dart' as domain;

import 'alternate.dart' as alt;

@Model(table: "people")
@Unique(["email"])
@Relation(
  target: Note,
  name: "notes",
  fields: ["id"],
  keys: ["ownerId"],
  constraint: false,
)
final class Person({
  @Id(generated: true)
  @Column(name: "id", codec: domain.PersonId.codec)
  required final domain.PersonId id,
  @Column(name: "email", codec: domain.Email.codec)
  required final domain.Email email,
  @Column(
    name: "membership",
    labels: {
      domain.Membership.pending: "pending-payment",
      domain.Membership.active: "active",
      domain.Membership.cancelled: "closed",
    },
  )
  required final domain.Membership membership,
  @Column(
    name: "previous_membership",
    labels: {
      domain.Membership.pending: "pending-payment",
      domain.Membership.active: "active",
      domain.Membership.cancelled: "closed",
    },
  )
  required final domain.Membership? previousMembership,
  @Column(name: "tags", codec: domain.tagsCodec)
  required final List<String> tags,
  @Column(name: "location", codec: domain.locationCodec)
  required final domain.Location? location,
  @Column(name: "alternate", codec: alt.emailCodec)
  required final alt.Email alternate,
  @Column(name: "details") required final SqlJson? details,
});

@Model(table: "notes")
@Relation(
  target: Person,
  name: "owner",
  fields: ["ownerId"],
  keys: ["id"],
  onDelete: .restrict,
)
final class Note({
  @Id(generated: true) @Column(name: "id") required final int id,
  @Column(name: "owner_id", codec: domain.PersonId.codec)
  required final domain.PersonId ownerId,
  @Column(name: "body") required final String body,
});
