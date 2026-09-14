# Implementation status

The active goal is the complete ORM described in `research/new-dart-orm-design.md`.
This file records verified delivery, not planned capabilities presented as working.

## Completed

- Reset the `next` branch contents, preserving the design research and license.
- Establish one Dart 3.13 package and local-only commit policy.
- Typed scalar expressions, 2–6-field composable projections and dynamic field maps.
- Immutable filters, order, offset/limit, count/exists, basic aggregation and mutations.
- Parameter binding, table occurrence scope checking, explicit default/null changes.
- Native SQLite worker with verified foreign keys, journal mode and parameter limit.
- PostgreSQL driver with a single pool owner, TLS settings and explicit borrowed pools.
- Transaction lifecycle, rollback, savepoints, pending work checks and query observation.

## Delivery sequence

1. Typed schema metadata, SQL expressions, projections, query and mutation execution.
2. Native SQLite worker and PostgreSQL drivers, explicit transactions and savepoints.
3. Record schema generator, typed table entry points and relationship declarations.
4. Batched relationship projections, root and per-parent pagination, nested relations.
5. Migration snapshots, dialect DDL, history/checksums, introspection and drift checks.
6. Advanced SQL, custom codecs, streaming, observation, Web adapter and capabilities.
7. CLI, examples, user documentation, real-database and platform acceptance checks.

## Validation

The research type proof was analyzed and ran with JIT and AOT; JavaScript compilation
also passed. These checks do not constitute a working ORM or browser validation.

The first execution slice passes static analysis and 18 integration checks against
native SQLite and a disposable PostgreSQL 18.4 instance. Coverage includes CRUD,
projection, SQL injection-shaped input, pagination, rollback/savepoint recovery,
unawaited work, escaped sessions and closing during active work. The table metadata
in these tests is hand-written; generation and relationships are not implemented yet.

## Environment

Use the standalone SDK if the Flutter launcher tries to update its cache:
`/Users/seven/workspace/flutter/bin/cache/dart-sdk/bin/dart`.
