## 6.0.0-beta.12 (2026-10-09)

- Keep PostgreSQL typed reads, counts, streams, updates, atomic arithmetic and
  deletes on the selected physical table with ONLY. Inherited rows cannot extend
  the scope or be modified before a multirow error is reported.
- Verify both sides of native foreign-key constraint triggers and the active
  replication role. Reject disabled or replica-only checks before saving or
  resuming migration history; ordinary and ALWAYS checks remain supported.
- Reject partitions and either side of table inheritance in frozen PostgreSQL
  histories, including unmanaged neighbors, before pending DDL. Existing batch
  query counts remain unchanged; catalog checks do not scan PostgreSQL data.
- Export native PostgreSQL exceptions and SQLite exceptions plus primary and
  extended error-code constants through the public driver modules. SQL failures
  retain their types, codes, metadata and transaction rollback behavior.
- From beta.11, update the dependency; generated clients and reviewed migration
  definitions and fingerprints remain unchanged. Review existing topology and
  enforcement drift before resuming a history. Raw SQL keeps native semantics.

## 6.0.0-beta.11 (2026-10-09)

- Add typed `count()` to query scopes and generated tables. One SELECT returns
  one integer without transferring or decoding model fields. Limit and offset
  remain inside the counted scope; sorting does not change cardinality.
- Return a selected user page and filtered total from the same read-only snapshot.
  Reuse one typed filter definition for two observable SELECTs, including empty
  pages with a nonzero total. The shop search example returns `users` and `total`.
- Preserve the first PostgreSQL SQL error and stack when automatic rollback also
  fails. Broken connections are discarded and subsequent work uses a replacement.
- Require native `postgres` 3.5.20 or newer for upstream cancellation and timeout
  fixes. Configure query/connect deadlines explicitly; close waits for admitted
  application callbacks and does not impose an application-work deadline.
- From beta.10, update the dependency and regenerate to expose `count()`.
  Existing generated methods remain usable. Keep reviewed migration definitions
  and fingerprints unchanged; adapt copied search example code to its record.

## 6.0.0-beta.10 (2026-10-09)

- Capture byte contents when filters are constructed and statements are called.
  Reusing caller buffers cannot change existing queries or queued writes.
- Keep filter-owned byte values read-only, including derived buffer views.
- Reuse PostgreSQL connections after business failure only when all issued SQL
  was inside transactions that rolled back without committing. SQL/cleanup
  failures, commits and work outside a transaction discard the failed callback's
  connection while preserving the original cause and stack.
- Normal callbacks retain native session state. Use transaction-scoped settings
  for request state and manage session advisory locks explicitly.
- Enforce one PostgreSQL statement per call using the extended protocol,
  regardless of pool query mode. Reject prepared transactions before execution.
- From beta.9, update the dependency; generated clients and reviewed migration
  definitions and fingerprints remain unchanged.

## 6.0.0-beta.9 (2026-10-09)

- Add generated typed `whereAny` filters: fields within a group use OR, while
  separate `where` and `whereAny` groups use AND. Empty groups fail before SQL.
- Search active users by username or nickname prefix in one SELECT with typed
  projections, database sorting and pagination.
- Batch PostgreSQL migration catalog reads within the driver parameter limit,
  retaining all schema, constraint, table identity and migration integrity checks.
- From beta.8, regenerate clients to use `whereAny`; keep reviewed migration
  definitions and fingerprints unchanged.

## 6.0.0-beta.8 (2026-10-09)

- Validate complete generated models against the runtime engine before taking driver ownership; verify pending migration markers and the final catalog after marker triggers before committing DDL.
- Fixed driver schemas keep typed SQL on persistent managed tables across PostgreSQL pooled temporary objects and changed search_path without adding query roundtrips. Reject NUL string defaults before SQL or output replacement.
- Reimplement the ORM with independent schema, query, database, driver,
  migration and development modules. Cross-module imports use public entrypoints.
- Generate typed tables with direct named-record selections, nullable partial
  updates, guarded arithmetic and explicit transaction sessions.
- Support native SQLite and PostgreSQL, with engine-specific frozen Dart
  migration histories and catalog verification.
- Add a complete shop example covering relationship batching, integer-cent
  totals, atomic stock updates, idempotent requests and rollback.
- This is a breaking rewrite; previous generated clients and
  migration definitions have no compatibility layer.
- Use Dart 3.13 primary constructors for concise model declarations and typed
  unique-key claims for idempotent business writes without handwritten SQL.
- Reject transforming row constructors and unsafe generated-file aliases.
  Preserve microsecond date ordering using integer timestamps in SQLite.
- Draft standalone reviewed Dart migrations without copying schema by hand.
- Reject engine identifier collisions and PostgreSQL truncation before SQL.
  Require PostgreSQL foreign keys to be enforced and validated, and unique
  indexes to be valid, ready and immediate. Reject incompatible internal
  migration tables before application migration SQL runs.
- Verify migrations against persistent tables and reject temporary shadows.
  PostgreSQL requires permanent logged managed tables.
- Verify SQLite primary-key nullability using actual rowid semantics.
- Check existing foreign-key data in managed SQLite tables when applying or
  resuming migrations.
- Resolve SQLite table, column and foreign-key names consistently in migration
  histories using ASCII case-insensitive identifier matching.

## 6.0.0-beta.7

Breaking beta API change: regenerate clients and update imports, database setup,
selections and writes. Keep reviewed migration definitions and fingerprints.
See the [tagged beta.7 migration guide](https://github.com/medz/dart-orm/blob/orm-v6.0.0-beta.7/doc/upgrade-beta7.md) and
[tagged API guide](https://github.com/medz/dart-orm/blob/orm-v6.0.0-beta.7/doc/api.md) for that release's workflow.

- Separate engine-created `SqlDatabase` from the ORM view created with
  `Database.fromSql`. Public entrypoints have explicit ownership; remove the
  `runtime.dart` and `drivers/*.dart` facades.
- Adjust direct imports in existing migration and registry libraries after the
  module split. Preserve applied operations, frozen schema declarations and
  saved checksums; import edits do not require accepting new fingerprints.
- Preserve typed model patches across filters and helper functions. Literal
  `create` and `patch` calls distinguish omission from explicit null; generated
  insert/patch inputs compose through `overlay` and `WriteValue` intents.
- Execute ordinary model writes immediately and expose advanced descriptions
  through `.plan`. Each plan terminal prepares fresh values; explicit `prepare()`
  captures values for replay, including read-only byte snapshots. Reject known
  invalid mutation shapes before input callbacks and client defaults.
- Keep `Selection<R>` for arbitrary result assembly. Add `@Projection` classes
  and named records whose generated `.sql(...)` bindings retain typed output
  fields for CTEs and set operations. Import `sql.dart` for query selection.
- Query CTEs directly after `asCte`; remove the old `.query` hop. Use generated
  `.sql(...)` projections for named output fields or `ref(...)` for exported
  expressions.
- Preserve relationship batching, explicit session ownership and transaction
  boundaries across typed model operations. Decode owned batch RETURNING
  results before committing.

- Switch project-owned code to the MIT License, copyright © 2022–2026 Seven Du,
  in this first MIT release, `6.0.0-beta.7`. Earlier releases and
  historical tags retain their original licenses.

## 6.0.0-beta.6

- Add optional plain mixins for shared annotated storage fields and business methods. Named constructor parameters must assign same-name, same-type mixin fields directly; original DTO identity, defaults and typed relations are preserved. Ordinary models remain supported without mixins. Reject ambiguous field/accessor conflicts, repeated metadata, transforming constructors and unsupported inheritance.

## 6.0.0-beta.5

Breaking model and configuration API change: replace Record declarations with
ordinary annotated DTOs and `OrmConfig` entrypoints with `void defineConfig`.
Regenerate clients and migrate application configuration. Keep historical
migration files unchanged.

- Replace Record declarations with ordinary annotated DTOs in `package:orm/schema.dart`, preserving original class identity and business methods in full-row results. Regenerate clients; the old declaration helpers are removed.
- Add `void defineConfig` in `package:orm/config.dart` for generation without existing client, snapshot or migration registry imports. Configuration paths are relative to the configuration file.
- Keep omitted create values distinct from explicit values/null with typed `Change`; constructor constants provide client-only fallbacks. Explicit client/database defaults and generated identities take precedence.
- Resolve PostgreSQL namespaces independently of source folders. Set explicit namespace metadata when migrating old folder-based declarations. Replace `OrmConfig` project entrypoints with `defineConfig`; frozen migration files and the production `runMigrationCli` API remain independent and unchanged.
- Use the exact DTO class name as the default physical table name; set `@Model(table: ...)` to retain an existing table identity.
- Enforce independent model libraries in standalone/CLI and build_runner generation, including exported and related models. Reject `part` and `part of` with a source-level diagnostic before writing outputs.
- Normalize nullable SQL NULL defaults during catalog verification without changing constructor-default precedence, saved snapshots or migration checksums.
- Reject `@DatabaseDefault` on a generated identity during annotation validation. Explicit `@ClientDefault` remains supported on identities.

Breaking filter API refactor: regenerate clients and migrate application queries.
There are no compatibility aliases. This changes query construction only; keep
historical migration files unchanged.

- Use `allOf([a, b])` and `anyOf([a, b])` for boolean groups in place of
  `a.and(b)` and `a.or(b)`. Negation remains `.not()`; successive `where` calls
  still combine complete predicates with AND.
- All six comparisons use one typed operand API: replace `field.eq(value)` with
  `field.eq(.value(value))`, and `field.equals(other)` with `field.eq(other)`.
  Apply the same literal wrapper to `ne/gt/gte/lt/lte`. Field operands use their
  SQL expressions directly; literal operands use the compared expression's codec.
- Empty AND is TRUE and empty OR is FALSE. Nullable text fields support the same
  predicates as non-null text; literal `contains/startsWith/endsWith` escape SQL
  wildcards while `like` retains pattern semantics.
- Relationship filters remain `.where(predicate).any()/none()/count()`. Invalid
  relationship aggregates/windows and nested occurrence reuse fail before SQL.
  MySQL self-referencing typed updates/deletes report
  `CAPABILITY.MUTATION_SELF_REFERENCE`; use explicit key selection when needed.
- Expand the query cookbook and guides with nested groups, field comparisons,
  relation scopes, universal predicates, and relationship-filtered CRUD.

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

See [database and platform boundaries](https://github.com/medz/dart-orm/blob/orm-v6.0.0-beta.1/doc/capabilities.md) before adopting the
beta. MySQL/MariaDB DDL is non-atomic. Cancellation and streaming depend on the
selected driver; the default Linux SQLite asset does not expose interruption.

Earlier 5.x releases remain available in the
[release archive](https://github.com/medz/dart-orm/releases/tag/orm-v5.3.4).
