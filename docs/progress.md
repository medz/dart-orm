# Implementation status

The active goal is the complete ORM described in `research/new-dart-orm-design.md`.
This file records verified delivery, not planned capabilities presented as working.

## Completed

- Reset the `next` branch contents, preserving the design research and license.
- Establish one Dart 3.13 package and local-only commit policy.

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

## Environment

Use the standalone SDK if the Flutter launcher tries to update its cache:
`/Users/seven/workspace/flutter/bin/cache/dart-sdk/bin/dart`.
