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
- Analyzer-based record generator, scalar annotations, composite keys, indexes and FK validation.
- Generated table accessors, named create parameters, byId, typed patches and schema snapshots.
- Batched and nested relation projections, per-parent SQL window pagination, optional/required relations.
- Correlated relation any/none/every/count; UNKNOWN fails every, and empty sets satisfy it.
- Dialect DDL, cyclic PostgreSQL FK creation, immutable migration checksums and atomic history.
- Concurrent migration serialization, read-only planning, column inspection and column drift checks.
- Runnable generated-client example with migrations, transactions and relationship selection.
- Atomic upsert with declared unique targets and typed existing/incoming field expressions.
- Batch inserts with parameter-aware chunks, optional field shapes, returning and all-chunk rollback.

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

Static analysis is clean. The complete suite passes 49 checks with native SQLite
and a disposable PostgreSQL 18.4 instance enabled. It exercises generation,
composite-key source validation, projections, relations, per-parent pagination,
transactions, migration rollback/history and the generated application client.
`dart run example/main.dart` runs successfully against a real in-memory SQLite DB.

## Still required for the goal

- Advanced joins/subqueries/CTE/window/union and keyset pagination.
- Aggregation legality checks, composite-key relation batching acceptance and join-based to-one loading.
- Migration diff/rename/rebuild, baseline, full constraint/index drift and nontransactional recovery.
- Complete migration CLI and build integration; custom codec/schema authoring.
- Cancellation, retry classification, genuine streaming and backend capability coverage.
- Browser worker/persistence adapter and real browser verification; native Flutter/AOT checks.
- User documentation, performance measurements and complete acceptance review.

Current to-one relation projections use batching, not joins. `verifyColumns` checks
column names/types/nullability only and is deliberately not named full schema verification.
The migration runner currently accepts transactional migrations only. These are
implementation stages, not a reduction of the active goal.

The mutation additions pass 36 shared SQLite/PostgreSQL integration checks in
`database_test.dart` (eight more than the previous relation suite). Full analysis
and the expanded complete suite are required before the next milestone closes.

## Environment

Use the standalone SDK if the Flutter launcher tries to update its cache:
`/Users/seven/workspace/flutter/bin/cache/dart-sdk/bin/dart`.
