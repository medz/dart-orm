# Prisma 8 reassessment

Research date: 2026-09-19. This report separates verified upstream behavior
from decisions for this Dart package. It supplements the original design;
it does not adopt Prisma's API or artifact format as this package's contract.

## Verified release state

Prisma 8 is a **release candidate**, with general availability expected in
October 2026. Live npm registry reads on the research date returned:

| Package | `latest` |
| --- | --- |
| `prisma` CLI | `8.0.0-rc.15` |
| `@prisma/orm-postgres` | `8.0.0-rc.11` |

The CLI and database libraries are versioned separately. A headline saying
“Prisma 8 is here” does not mean all version 7 features have shipped in 8.

Sources: [release status](https://www.prisma.io/docs/orm/release-status),
[CLI registry tags](https://registry.npmjs.org/-/package/prisma/dist-tags),
[PostgreSQL registry tags](https://registry.npmjs.org/-/package/@prisma%2form-postgres/dist-tags).

| Database | Prisma 8 status on this date |
| --- | --- |
| PostgreSQL | Release candidate |
| MongoDB | Early access; ORM transactions are not available |
| SQLite | Experimental package |
| MySQL | Planned next; no Prisma 8 library yet |
| MariaDB, SQL Server, CockroachDB | Planned; no Prisma 8 library yet |

This is the version 8 matrix, not the older version 7 compatibility matrix.
Hosted PostgreSQL services use the PostgreSQL connection path; hosting does
not establish support for every extension or PostgreSQL-compatible engine.
Source: [supported databases](https://www.prisma.io/docs/orm/supported-databases).

The old `prisma-next` repository is archived. Current source resolves to
[`prisma/orm`](https://github.com/prisma/orm), including requests through the
`prisma/prisma` redirect. Source inspection below is pinned to commit
`ad23f6f47f7964a12f07899c39d2449f1d5b99ea` (2026-09-18), which is a main-branch
snapshot rather than proof that every source feature is in the published RC.

## What the architecture actually provides

Prisma separates a model/storage contract, query construction, runtime
execution, target-specific SQL behavior, driver I/O, and migration tooling.
ORM queries, SQL-builder queries, and raw SQL converge on an inspectable
plan. The runtime executes that plan; a driver manages database access.
Authoring and migration code are kept out of runtime dependencies. The
repository checks import boundaries rather than relying on folder names.

The application-facing PostgreSQL package has public subpaths for
`contract`, `contract-builder`, `builder`, `orm-client`, `family-runtime`,
`adapter`, `driver`, `migration`, and `config`. Its own description presents
it as the one package a PostgreSQL application installs. Internal packages
and public subpaths are different concepts: independent use does not
require making application developers assemble dozens of packages.

Sources: [architecture](https://github.com/prisma/orm/blob/ad23f6f47f7964a12f07899c39d2449f1d5b99ea/ARCHITECTURE.md),
[dependency boundaries](https://github.com/prisma/orm/blob/ad23f6f47f7964a12f07899c39d2449f1d5b99ea/docs/architecture%20docs/Package-Layering.md),
[public package exports](https://github.com/prisma/orm/blob/ad23f6f47f7964a12f07899c39d2449f1d5b99ea/packages/9-public/%40prisma/orm-postgres/package.json).

Two details qualify the older announcement's claims:

- The current PostgreSQL runtime reference says `for await` still loads all
  rows first. An async iterable alone is not evidence of bounded memory.
- The default `verifyMarker: 'onFirstUse'` reports a contract mismatch as a
  warning and continues. A marker check is also not a live catalog audit.

Source: [transactions and runtime reference](https://www.prisma.io/docs/orm/reference/transactions-and-runtime).
Our existing explicit sessions, backpressure, cancellation, and capability
checks should retain their measured guarantees through this refactor.

## Model declaration and typed use

Prisma accepts either its schema language or a TypeScript builder. Both
produce a deterministic contract JSON file plus TypeScript declarations.
The TypeScript builder supports composition and data-driven declarations;
relations are added through model handles. The documentation still
recommends the schema language for its brevity when composition is not
needed. This is not evidence that the TypeScript object syntax transfers
unchanged to Dart.

Source: [TypeScript contract authoring](https://www.prisma.io/docs/orm/contract-authoring/typescript-schema-builder).

The query surfaces deliberately separate model names (`db.orm.public.User`)
from table names (`db.sql.public.user`). Selections determine result types.
Raw queries supply column codecs or an explicit result shape. This gives
applications an escape route for SQL that the ORM cannot express while
preserving value parameterization and decoding.

Sources: [ORM client](https://www.prisma.io/docs/orm/reference/orm-client),
[SQL query builder](https://www.prisma.io/docs/orm/reference/sql-query-builder),
[raw queries](https://www.prisma.io/docs/orm/reference/raw-queries).

### Dart decision

Support an ordinary immutable **Dart class** as a first-class model source.
Fields keep their Dart types and annotations; a validated constructor gives
the generator a direct way to reconstruct the class. Generate typed column
handles, creates, patches, and relationships from that source. Preserve
record declarations as a compact alternative and records as projection
results. Both declaration forms must produce the same runtime semantics.

Important boundaries:

- A model class describes values. It does not own a connection, issue SQL
  from getters, or hide lazy relation loading.
- Table identity remains explicit and independent of a class or record
  type. Two tables may store the same Dart shape.
- Constructor mapping is checked during generation. Unsupported constructor
  shapes must produce a source-located error, not a runtime cast failure.
- Typed selectors use generated Dart members. Do not translate Prisma's
  string-key projections into stringly typed Dart maps or claim that Dart
  can infer new record members from arbitrary runtime data.
- Low-level query construction accepts typed table/column declarations
  without requiring a model class or code generation.
- All authoring forms converge on one storage description. Data-driven
  configuration is not a second competing schema or a parallel execution
  implementation.

These are design choices for Dart and this repository, not Prisma features.
Static generation is useful here; eliminating all generated Dart would work
against directly typed members and predictable AOT/Flutter behavior.

## Six useful layers, one product package

Use independently importable public libraries with tested import boundaries.
The following are responsibilities, not a requirement to create six Pub
packages or a plugin registration framework.

| Layer | Responsibility | Must work independently |
| --- | --- | --- |
| Values and contract | SQL value codecs, errors, engine capabilities, storage description | Use values and describe storage without a driver or ORM |
| SQL construction | Typed columns, expressions, selections, compilation | Build and inspect parameterized SQL without a connection or generated model |
| Driver and runtime | Connections, leases, cursors, transactions, cancellation | Execute parameterized SQL without ORM/model imports |
| ORM | Typed model queries, relation loading, creates and patches | Add model convenience over the same SQL/runtime behavior |
| Schema and migrations | Authoring, frozen snapshots, catalog checks, planning and history execution | Use migration tools with driver/runtime without generated application models |
| CLI | Project discovery, arguments, display, exit status | Call public tooling APIs; contain no second migration implementation |

Dependencies point toward shared value/contract types. SQL construction and
driver I/O are peers consuming the same small statement/result contracts;
neither should depend on ORM. ORM composes them. Migrations consume storage
and execution interfaces, not the application's live model objects. CLI
consumes migration/generation services. Keep analysis and filesystem imports
out of runtime libraries.

Before calling this modularity complete, prove concrete independent usage:
compile SQL without opening a database; execute driver SQL without importing
`orm.dart`; run migrations without generated entities; and import the
portable runtime on Web without pulling native or CLI libraries. A facade
that merely hides names while all files remain in one Dart `part` library
does not establish independent implementation boundaries.

## Migrations: borrow checks, keep Dart artifacts

Prisma migrations have start/end contract hashes and form a graph. In the
current release candidate, branch reconciliation needs explicit migrations
from each branch state to the merged state; squash and split are not yet
implemented. The live database marker records a state, while the ledger
records executed migrations. Reading the marker does not inspect the actual
tables.

Source: [migration graph and its current limits](https://www.prisma.io/docs/orm/migrations/the-migration-graph).

Prisma authors `migration.ts` but executes compiled operations from
`ops.json`. Historical snapshots type its data transformations. Prechecks
and postchecks support verification and recovery, but recompilation is
required after a source edit. PostgreSQL currently executes a migration run
inside one transaction, so this route cannot execute `CREATE INDEX
CONCURRENTLY`.

Source: [editing a migration](https://www.prisma.io/docs/orm/migrations/editing-a-migration).

For this package, retain **Dart source snapshots and migration definitions**,
static registration, frozen historical types, reviewed fingerprints, and
one engine per history. Borrow inspectable operations, explicit preconditions,
catalog verification, and precise recovery states. Do not restore the
rejected JSON workflow or add a migration graph without a demonstrated need.
Schema rollback also cannot promise recovery of deleted application data.

Database support changes migration execution semantics. SQLite rebuilds,
PostgreSQL transactional DDL, and MySQL/MariaDB implicit DDL commits need
their own checks and recovery behavior. A shared verb must not advertise
identical atomicity across those engines.

## CLI: intent and predictable output

Prisma separates offline contract emission and migration planning from
database initialization, verification, and migration execution. `migration
plan` reports an unknown origin instead of silently generating full creation
steps when existing history makes that assumption unsafe. Global flags
support explicit output formats, config paths, noninteractive operation,
help, and structured diagnostics.

Sources: [migration plan](https://www.prisma.io/docs/cli/migration-plan),
[global flags](https://www.prisma.io/docs/cli/global-flags).

For Dart, expose a small, discoverable command tree: project setup, model
generation, schema inspection, migration plan/check/status/apply. Keep
preview and execution distinct, retain source paths in errors, never print
credentials, reject unknown options, and return stable nonzero exit codes
for misuse or failed checks. Help should contain the next useful command.
Structured CLI output is optional presentation; it does not make JSON a
schema or migration storage format.

## Database delivery decision

The user has requested real SQLite, PostgreSQL, MySQL, and MariaDB support
and acceptance. Implement and validate each; do not inherit Prisma 8's
current database limits or claim compatibility based only on a shared wire
protocol.

MySQL and MariaDB can share a transport implementation where justified,
while identifying the actual server and retaining distinct capability and
migration decisions. Acceptance must cover real values, transactions,
rollback, generated keys, nulls, large integers/decimals, temporal values,
errors, and schema evolution. SQLite Web remains a separately verified
platform within the SQLite implementation. SQL Server and document stores
remain outside the accepted implementation scope until explicitly added.

## Adoption checklist

Adopt: one package with usable lower layers; model/storage identity
separation; class and record authoring through one generator; common SQL
execution contracts; visible query plans; engine-specific capabilities;
small CLI workflows with inspectable results.

Do not copy: the JSON artifact requirement, TypeScript type-level syntax,
the full multidimensional package/SPI topology, eager claims of streaming,
warning-only verification, or roadmap features presented as delivered
database support. Preserve existing correctness guarantees while reducing
the amount of ORM machinery a low-level caller must import or understand.
