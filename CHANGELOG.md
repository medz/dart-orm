## 6.0.0-beta.4

Breaking SQL API change: replace Named SQL declarations/generated bindings with
connection-independent `Sql` and optional `ResultShape` codecs. Delete query
`.queries.dart` outputs and `orm:queries` builder configuration. The old
`sqlQuery`, `SqlTemplate`, `SqlQueryDefinition` and `queries generate/check`
commands are removed; schema generation and migration history are unchanged.

- Execute through `db.raw` / `db.query`; reuse fragments, typed values and result
  mappings across sessions, transactions and explicit database dialects.
- Validate required result labels even for zero rows; retain typed cursor
  streaming, committed-change watches and native preparation with `checkSqlQuery`.
- Use ordinary Dart functions for query parameters and return types, with no
  query-specific generator or implicit CTE wrapper.

Breaking PostgreSQL schema change: table identities now include the database
schema, including `public`. Regenerate clients and snapshots and review the
required migration. Old unqualified snapshots are not automatically normalized;
generated table replacement requires explicit destructive opt-in and deletes data.

- Discover PostgreSQL models in `schema/{schema}/*.dart` and other supported
  databases in `schema/*.dart`, alongside an optional default `schema.dart`.
- Generate schema-grouped clients when PostgreSQL models use a non-default
  namespace. Preserve mixed-case identifiers and qualify table references,
  cross-schema relationships, migrations and catalog verification explicitly.
- Reject dotted model table names and conflicting declarations. Keep snapshots
  stable when definitions are split or renamed within the same database schema.
- PostgreSQL cursor tokens now identify schema-qualified tables, including
  `public`. Regenerated clients reject tokens issued with the earlier unqualified
  table identity; applications that persist cursors must reissue them.

## 6.0.0-beta.3

Breaking schema authoring change: replace annotated entities and hand-written row
types with `model(...)`, then regenerate clients. Table and column names still
identify the physical schema; keep existing migration history unchanged.

- Add `model(...)` with named Record column declarations, generating nominal
  rows and typed queries from one definition without annotations.
- Support model-local keys, indexes, checks and relationships, including self,
  composite and alternate-key references; follow exported/cross-file models.
- Name relations with Record fields. Declare reverse navigation on its own model,
  reject ambiguous references, and select target keys with named column mappings.
- Report Record schema errors with source locations and diagnostic codes. Keep
  snapshots independent of application types and preserve migration histories.
- Replace entity declarations and storage annotations with `model(...)`; remove
  the previous schema reader. Catalog import and project initialization emit the
  same Record schema syntax.
- Declare named SQL result and parameter columns with the same helpers and
  generate their result classes alongside query methods.

## 6.0.0-beta.2

- Replace shared `part` libraries with independent modules and explicit public
  exports. Internal compiler and execution details stay outside the documented API.
- Make `first()` require a row; use `firstOrNull()` for the previous optional
  behavior. Add `singleOrNull()` to queries and returning mutations.
- Keep physical schema metadata in `schema_model.dart`; `schema.dart` exposes
  model declarations, value types and declaration options.
- Give MySQL and MariaDB their own driver/configuration exports; import the
  corresponding engine entrypoint instead of obtaining both from `mysql.dart`.
- Rebuild the guides and public Dartdoc, including API categories, resource
  ownership and execution boundaries. Remove archived exploration artifacts.

## 6.0.0-beta.1

First beta of the new Dart-native ORM. Requires Dart 3.13 or newer.

This is a breaking replacement for the Prisma-based 5.x client. Prisma schema
files, generated clients, engine binaries and the separate `orm_flutter` adapters
are not used by this implementation. Existing applications need an explicit
model/API migration; updating the dependency alone is not sufficient.

- Declare immutable Dart models once and generate typed create, patch, query,
  relationship and projection APIs.
- Use schema metadata, database drivers, raw sessions, typed SQL, ORM execution
  and migrations as independent libraries in one package.
- Connect to SQLite, PostgreSQL, MySQL and MariaDB using native Dart adapters.
- Use one SQLite entrypoint for native Dart, Flutter and the browser. Flutter Web
  bundles the worker and WASM assets automatically.
- Keep snapshots and immutable, single-engine migration histories in Dart source,
  including catalog verification, reviewed renames and resumable backfills.
- Initialize, generate and manage migrations with typed `orm.config.dart` and
  the `dart run orm` CLI. Optional build_runner outputs Dart source only.
- Add typed selections, explicit relation loading, transactions, query
  subscriptions, SQL inspection and capability-checked execution controls.

See [database and platform boundaries](https://github.com/medz/dart-orm/blob/main/doc/capabilities.md) before adopting the
beta. MySQL/MariaDB DDL is non-atomic. Cancellation and streaming depend on the
selected driver; the default Linux SQLite asset does not expose interruption.

Earlier 5.x releases remain available in the
[release archive](https://github.com/medz/dart-orm/releases/tag/orm-v5.3.4).
