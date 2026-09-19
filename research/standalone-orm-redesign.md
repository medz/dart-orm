# Standalone Dart ORM redesign

Decision date: 2026-09-19. This is a development redesign, not a compatibility
release. The user's accepted database scope is SQLite (including Flutter/Web),
PostgreSQL, MySQL and MariaDB. The implementation remains one product package.

## Product contract

- Declare an immutable Dart model once; generated reads return that nominal type.
  Records remain useful for projections and explicit structural data shapes.
- Keep model rows, insert inputs, patches and relation projections distinct.
  Generated IDs are required in a persisted row but omitted from create inputs;
  updates distinguish keeping a value from writing SQL NULL.
- Every layer can be used without the layer above it. This is an import-graph
  requirement, not merely a filtered export list.
- Preserve bound parameters, identifier quoting, alias scope checks, explicit
  transactions and observable relationship query counts.
- A database engine is selected explicitly. Capabilities and physical schema
  behavior reflect that engine, including differences between MySQL and MariaDB.
- Current schema, configuration and immutable migration history are Dart source.
  No compatibility reader for retired artifact formats is introduced.

## Library boundaries

| Library | Responsibility | Must not depend on |
| --- | --- | --- |
| `values.dart` | Codecs, exact numbers, calendar values and errors | Drivers, queries, models, tooling |
| `driver.dart` | Commands, rows, cursors, connection leases and capabilities | ORM, schema generation, migrations |
| `schema_model.dart` | Physical columns, keys, indexes and constraints | Connections, ORM, analyzer |
| `schema.dart` | Typed application declarations | ORM execution and generation |
| `runtime.dart` | Raw execution, sessions, transactions, cancellation and observations | Query builder, generated models |
| SQL construction | Typed expressions, query descriptions, compilation and decoding plans | Concrete drivers and connected databases |
| `orm.dart` | Bound typed queries, relationship loading and subscriptions | Platform drivers and development tools |
| `migrate.dart` | Frozen histories, diff, catalog verification and execution | Application models and ORM queries |
| Generation/CLI | Static analysis, reproducible source output and project commands | Application runtime initialization for offline work |

Concrete adapters consume the driver contract. Convenience entrypoints may
compose adapters with the ORM, but a separate direct driver import must retain
the lower-level dependency boundary. A single package still resolves its declared
development dependencies; independent imports do not imply separate pub downloads.

## Implementation sequence

1. Extract values, physical metadata, driver contracts and the existing transaction
   state machine into actual libraries. Keep one transaction implementation.
2. Read primary-constructor models directly and materialize the user's class in
   generated typed selections. Preserve table identity independently of row type.
3. Make SQL construction and compilation usable without opening a database or
   constructing a fake driver. Preserve alias scope and explicit session ownership.
4. Implement MySQL/MariaDB adapters, SQL dialects, catalog and migration behavior.
   Treat nontransactional DDL, generated IDs, returning, exact values and errors
   explicitly; do not advertise SQLite/PostgreSQL semantics for these engines.
5. Provide a coherent CLI onboarding/configuration/generation/migration workflow
   using typed Dart configuration and static history imports.
6. Update user-facing examples and boundary documentation. Verify isolated layer
   consumers, negative type cases and actual database/platform behavior.
7. Commit reviewable changes, push, open a PR against `main`, request Codex review,
   address findings, and merge only the verified reviewed head.

## Acceptance evidence

Required evidence includes import-graph checks, standalone layer consumers,
nominal model CRUD/relations/projections, invalid types rejected by analysis,
CLI setup through migration replay, real SQLite/PostgreSQL/MySQL/MariaDB tests,
and refreshed SQLite Web assets with Dart and Flutter JS/WASM acceptance.
Existing validation records remain historical baselines. New records identify
the tested versions and any unsupported feature or deployment target explicitly.
