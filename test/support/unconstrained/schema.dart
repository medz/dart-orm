import 'package:orm/schema.dart';

final Model account = model(
  "accounts",
  (
    tenant: integer(),
    id: integer(),
    label: text(name: "display_label").nullable(),
    managerId: integer().nullable(),
  ),
  primaryKey: (r) => (r.tenant, r.id),
  relations: (r) => (
    entries: referencedBy(() => entry, on: (tenant: r.tenant, owner: r.id)),
    matches: referencedBy(() => entry, on: (tenant: r.tenant, label: r.label)),
    manager: references(
      (tenant: r.tenant, id: r.managerId),
      () => account,
      constraint: false,
    ),
    reports: referencedBy(
      () => account,
      on: (tenant: r.tenant, managerId: r.id),
    ),
  ),
);

final Model entry = model(
  "entries",
  (
    id: integer(),
    tenant: integer().nullable(),
    owner: integer().nullable(),
    label: text(name: "lookup_label").nullable(),
  ),
  primaryKey: (r) => r.id,
  relations: (r) => (
    ownerAccount: references(
      (tenant: r.tenant, id: r.owner),
      () => account,
      constraint: false,
    ),
    matchingAccounts: references(
      (tenant: r.tenant, label: r.label),
      () => account,
      constraint: false,
    ),
  ),
);

final Model reading = model(
  "readings",
  (id: integer(), value: real()),
  primaryKey: (r) => r.id,
  relations: (r) =>
      (peers: references((value: r.value), () => reading, constraint: false)),
);
