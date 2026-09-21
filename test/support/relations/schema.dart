import 'package:orm/schema.dart';

final Model account = model(
  "accounts",
  (
    tenant: integer(),
    id: integer(),
    label: text().nullable(),
    note: text().nullable(),
    managerId: integer().nullable(),
    marker: text(name: "_ORM_PRESENT").nullable(),
  ),
  primaryKey: (r) => (r.tenant, r.id),
  relations: (r) => (
    manager: references(
      (tenant: r.tenant, id: r.managerId),
      () => account,
      onDelete: .restrict,
    ),
    reports: referencedBy(
      () => account,
      on: (tenant: r.tenant, managerId: r.id),
    ),
    events: referencedBy(() => event, on: (tenant: r.tenant, owner: r.id)),
    reviews: referencedBy(() => event, on: (tenant: r.tenant, reviewer: r.id)),
  ),
);

final Model event = model(
  "events",
  (
    id: integer(),
    tenant: integer().nullable(),
    owner: integer().nullable(),
    reviewer: integer().nullable(),
    title: text(),
    score: integer(),
  ),
  primaryKey: (r) => r.id,
  relations: (r) => (
    author: references(
      (tenant: r.tenant, id: r.owner),
      () => account,
      onDelete: .restrict,
    ),
    reviewerAccount: references(
      (tenant: r.tenant, id: r.reviewer),
      () => account,
      onDelete: .restrict,
    ),
  ),
);
