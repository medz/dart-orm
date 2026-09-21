import 'package:orm/schema.dart';

import 'types.dart' as domain;

import 'alternate.dart' as alt;

final Model person = model(
  "people",
  (
    id: custom(domain.PersonId.codec).identity(),
    email: custom(domain.Email.codec),
    membership: enumeration(
      domain.Membership.values,
      labels: {
        domain.Membership.pending: "pending-payment",
        domain.Membership.active: "active",
        domain.Membership.cancelled: "closed",
      },
    ),
    previousMembership: enumeration(
      domain.Membership.values,
      labels: {
        domain.Membership.pending: "pending-payment",
        domain.Membership.active: "active",
        domain.Membership.cancelled: "closed",
      },
    ).nullable(),
    tags: custom(domain.tagsCodec),
    location: custom(domain.locationCodec).nullable(),
    alternate: custom(alt.emailCodec),
    details: json().nullable(),
  ),
  uniqueKeys: (r) => [r.email],
  relations: (r) => (notes: referencedBy(() => note, on: (ownerId: r.id))),
);

final Model note = model(
  "notes",
  (
    id: integer().identity(),
    ownerId: custom(domain.PersonId.codec),
    body: text(),
  ),
  relations: (r) =>
      (owner: references((id: r.ownerId), () => person, onDelete: .restrict)),
);
