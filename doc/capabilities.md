# Capabilities and limits

Choose an engine and platform explicitly. The shared query API does not make
backend behavior identical: connections expose their actual capabilities and
reject unsupported operations before execution where possible.

## Values and physical storage

| Value | Supported representation | Boundary |
| --- | --- | --- |
| Integers | Explicit integer widths and exact BigInt codecs | Native `int` is signed 64-bit; JS-safe `int` is narrower. SQLite stores BigInt as text, which does not provide numeric ordering or arithmetic. |
| Decimal | Exact storage, comparison, keys and schema metadata on all four engines | SQLite/PostgreSQL support exact arithmetic, aggregates, windows and rounding. MySQL/MariaDB reject operations that can silently lose precision; see [engine limits](https://github.com/medz/dart-orm/blob/main/doc/mysql.md). |
| Time | UTC `DateTime`, `LocalDate`, `LocalTime`, `LocalDateTime` and explicit temporal precision | An IANA zone name is a separate application value. Calendar SQL arithmetic and timezone-rule conversion have no typed API. |
| JSON | `SqlJson` distinguishes JSON null from SQL NULL | A Dart Map is not an entity mapping. Backend-specific JSON path operations require explicit SQL. |
| Enum | Checked enum codecs and explicit text labels | Native PostgreSQL enums need separate metadata and migration support. |
| Binary and custom IDs | `Uint8List` and public const codecs | Codec changes do not automatically produce DDL. Domain equality and ordering must match the chosen storage. |

See [types and codecs](https://github.com/medz/dart-orm/blob/main/doc/types.md) and [decimals](https://github.com/medz/dart-orm/blob/main/doc/decimals.md) for exact conversion,
precision and nullability rules. Catalog import reads physical metadata without
sampling rows to guess domain semantics. Ordinary SQLite INTEGER/TEXT cannot
prove a boolean, enum, timestamp, BigInt or JSON domain. Unsupported column and
table forms produce review issues. Import does not recreate an entire database.

## Queries and execution

| Operation | Behavior | Boundary |
| --- | --- | --- |
| Selection | Scalar, positional/named Record, DTO and runtime field selection | Mappers execute after rows arrive. Runtime field sets return a dynamic map. |
| Pagination | Offset/limit and typed keyset cursors with unique tie breakers | Offset pages are not snapshots; nullable cursor fields need explicit NULL ordering. |
| SQL composition | Joins, grouping/HAVING, subqueries, CTEs, windows and UNION | Scope and aggregate rules are validated. INTERSECT/EXCEPT and arbitrary functions require raw or named SQL. |
| Relationships | Joined or batched to-one values, batched collections, composite/self keys and per-parent limits | No cross-database navigation or lazy property reads that issue hidden SQL. |
| Writes | Generated create/patch, omitted versus NULL/default values, expression writes, batches, upsert and RETURNING where supported | No tracked object graph or implicit flush. Computed fields are read-only. |
| Transactions | Explicit session ownership, savepoints, rollback and bounded opt-in retries | External side effects are not rolled back or made safe to repeat. Distributed transactions are not supported. |
| Observation | Query descriptions and acquisition/query/decode events | No general optimizer or result cache. Timings have explicit scopes, not total CPU attribution. |

Choose `first()`/`single()` when absence is an error and `firstOrNull()`/
`singleOrNull()` when it is expected. Both single-result variants reject multiple
rows. See [queries](https://github.com/medz/dart-orm/blob/main/doc/queries.md), [relationships](https://github.com/medz/dart-orm/blob/main/doc/relations.md),
[execution](https://github.com/medz/dart-orm/blob/main/doc/execution.md) and [observability](https://github.com/medz/dart-orm/blob/main/doc/observability.md).

SQLite interruption depends on its compiled library. The default Linux asset in
`sqlite3` 3.6.0 does not expose `sqlite3_interrupt`; statement cancellation,
execution deadlines and bounded retries are rejected before SQL starts. Ordinary
transactions and cursor streaming still work. Browser SQLite has no synchronous
statement interruption either.

MySQL/MariaDB do not support cursor streaming or cancellation tokens. Their
statement timeout discards the connection, and a submitted write can have an
unknown outcome. Do not infer rollback from a timeout or connection loss. See
[MySQL and MariaDB](https://github.com/medz/dart-orm/blob/main/doc/mysql.md) for transaction and numeric restrictions.

## Migrations and database adoption

Each history fixes one engine, including an empty history. A saved migration has
one step list, its reviewed fingerprint and only that engine's frozen expressions.
Mixed histories and mismatched connections fail before migration SQL. Changing a
connection URL does not translate a history.

SQLite opening requires 3.35+ and PostgreSQL migration execution requires 18+.
MySQL connections and migrations require 8.4+; MariaDB connections require 10.6+
and migrations require 11.8+. The MariaDB driver's lower connection minimum has
not received the full 11.8 validation matrix. Reviewed SQL can require additional
server features beyond these minimum gates.

MySQL/MariaDB DDL can commit implicitly. Checked before/after metadata and durable
checkpoints support recovery; backfill writes and their completion checkpoints
share a transaction. See [migration recovery](https://github.com/medz/dart-orm/blob/main/doc/mysql-migrations.md). SQLite rebuilds
and PostgreSQL DDL use their respective transactional behavior.

Renames and conversions require explicit decisions. Catalog verification checks
declared schema facts and reports unmanaged objects such as views, triggers,
specialized indexes, policies and table options. PostgreSQL reports include policy
roles, command, mode and expressions plus enabled/forced row-security flags.
Baseline does not certify grants, every extension, authorization behavior or the
entire database environment. See [migrations](https://github.com/medz/dart-orm/blob/main/doc/migrations.md) and [importing](https://github.com/medz/dart-orm/blob/main/doc/importing.md).

## Connections, platforms and tools

PostgreSQL uses its driver's pool and supports borrowed-pool ownership. SQLite
owns one background connection, with native and browser implementations behind a
single public entrypoint. MySQL/MariaDB own one queued physical connection each.
Server drivers verify TLS certificates by default; typed settings and URL options
are not silently combined.

SQLite memory and persistent options share one API. Native applications choose
an application-owned path; browsers choose a named OPFS database. Flutter Web
bundles matching worker/WASM resources. [SQLite Web](https://github.com/medz/dart-orm/blob/main/doc/sqlite-web.md) documents
resource overrides, secure-context requirements and exclusive ownership.

| Platform | Scope |
| --- | --- |
| Native Dart | SQLite, PostgreSQL, MySQL and MariaDB adapters; engine restrictions above apply |
| Browser | SQLite in Chrome JS/WASM; secure context and worker/OPFS requirements apply |
| Flutter | SQLite on Android and Flutter Web; persistence and resource ownership follow the platform driver |
| Other browsers and devices | Safari, Firefox, physical-device and iOS/macOS Flutter behavior are not verified |

Record schema generation has been exercised with SQLite and PostgreSQL. Its
integration with MySQL/MariaDB, browser and Flutter clients is not yet verified.
Remote/serverless transports, replica routing and alternative pools require
separate adapters.

Record schemas generate immutable model classes and typed queries.
Editor completion checks local fields; cross-model mapping names and schema
semantics are checked during generation. Regenerate and analyze after edits.
See [generation](https://github.com/medz/dart-orm/blob/main/doc/generation.md) for
build/watch behavior and [performance](https://github.com/medz/dart-orm/blob/main/doc/performance.md)
for workload-specific cost measurements.
