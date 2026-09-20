# Capability review

The acceptance scope comes from the [original design](../research/new-dart-orm-design.md).
Its common relational lifecycle is implemented in one package. Optional backend
extensions and untested deployment targets are not implied by a generic driver
or a successful test on another platform.

## Values and physical storage

| Design §5 requirement | Implementation and evidence | Explicit boundary |
| --- | --- | --- |
| Integer widths and web-safe exact values | `IntegerBits`, integer/BigInt codecs, integer/native/browser checks, catalog metadata and reviewed migrations | Native `int` is signed 64-bit; JS-safe `int` is narrower. BigInt uses exact digits, but SQLite BigInt text does not promise numeric ordering/arithmetic. |
| Exact decimal | Exact storage, comparisons, keys and generated/imported metadata on all four engines; arithmetic, aggregates/windows and rounding on SQLite/PostgreSQL | MySQL/MariaDB reject operations that can silently lose precision, including arithmetic, SUM, explicit narrowing and decimal set operations. See [engine limits](mysql.md) and [reproductions](../research/mysql-precision-boundaries.md). |
| Distinct instant/date/time/local timestamp | UTC DateTime, LocalDate/LocalTime/LocalDateTime, explicit temporal precision, native binary decoding, SQLite collations, catalog/import/migration tests and browser transport | An IANA zone name is a separate application value, not an instant or local clock value. Calendar SQL arithmetic and timezone-rule conversion have no typed API. |
| JSON versus arbitrary objects | SqlJson distinguishes JSON null from SQL NULL; explicit domain codecs validate custom objects, including generated create/result/relationship types | A Dart Map is not an automatic entity mapping. Backend-specific JSON path APIs are extensions. |
| Stable enum text | EnumValue labels and checked enum codecs; generated/native/negative tests | Native PostgreSQL enums require separate metadata and migration support. |
| Binary and custom IDs | Uint8List and public const UseCodec declarations, checked domain codecs, generated type failures, native/browser reads/writes/relations | A codec's semantic change is not automatically a DDL change. Custom equality/order must match the declared storage. |

The authoritative contracts and tests are indexed in [types](types.md),
[decimals](decimals.md) and the [acceptance map](acceptance.md). The design's time
contract specifies storage distinctions and precise codecs; it does not define a
timezone database or a calendar SQL function family. Earlier progress notes
listed those possible extensions as open-ended follow-up work. They remain
explicitly unimplemented rather than being counted as delivered functionality.

Catalog import recognizes supported physical representations without sampling
data to guess semantics. Ordinary SQLite INTEGER/TEXT cannot prove a boolean,
enum, timestamp, BigInt or JSON domain. Unsupported VARCHAR/arrays/domains and
unsupported identity/table forms produce explicit issues instead of silently
changing their meaning. Reviewed annotations/codecs and migrations remain part
of adopting an existing database; import is not a universal database backup.

## Query and execution contract

| Required family | Evidence and available behavior | Boundary |
| --- | --- | --- |
| Scalars, Records, DTOs and dynamic selection | `selection_test`, generated/native tests; mappers run only after rows arrive | Dynamic field sets return a dynamic map, not invented static fields. |
| Conditions, ordering and pagination | Database/type/cursor suites, stable unique tie breakers, explicit NULL order | Offset pages do not provide a snapshot; cursor order needs declared keys. |
| Joins, grouping/HAVING, subqueries, CTEs, windows, UNION | `test/support/advanced.dart`, set and numeric suites on both backends; SQL scope and aggregate validation | INTERSECT/EXCEPT and arbitrary database functions do not have dedicated typed methods. Parameterized raw/named SQL is the formal extension path. |
| Relations and relation ordering | Joined or batched to-one; batched collections, composite/self/multiple edges, many-to-many payloads, per-parent limits, any/none/every/count | Order root rows through a typed alias or correlated count. Loaded Record fields are not SQL expressions. No cross-database relation or invisible lazy I/O. |
| Writes and transactions | Generated create/patch, explicit NULL/default, computed/client defaults, batch/upsert/RETURNING, savepoints, rollback, escaped-session rejection | No graph tracking, implicit flush or distributed transaction. |
| Failure handling and streaming | Real interruption, unknown commit, bounded acquisition/retries, real cursors and awaited cleanup | An external side effect is not rolled back by SQL or safe to repeat automatically. Web interruption and MySQL/MariaDB streaming/cancellation are unsupported and rejected. |
| Plans and observations | SQL/column/key/join/batch descriptions and actual acquisition/query/decode events | No general optimizer, result cache or hidden EXPLAIN ANALYZE. Timing scopes are documented, not total CPU attribution. |

See [query examples](queries.md), [relationships](relations.md),
[execution](execution.md) and [observability](observability.md).

SQLite cancellation is a build capability, not a promise for every native target.
The default Linux asset in `sqlite3` 3.6.0 hides `sqlite3_interrupt`; it rejects
statement cancellation, execution deadlines and bounded retries before SQL starts.
Ordinary transactions and streaming still work. macOS and Android interruption
have separate runtime evidence; see [execution](execution.md).

## Migration and database adoption

Each history fixes one database engine, even when empty. A saved migration contains
one step list and only that engine's frozen physical expressions. Mixed histories
and mismatched connections fail before migration SQL. PostgreSQL migration
execution requires 18+, and SQLite opening requires 3.35+; arbitrary reviewed SQL
can require additional capabilities.

MySQL 8.4+ and MariaDB 10.6+ use separate driver identities. Migration execution
requires MySQL 8.4+ or MariaDB 11.8+. Their DDL can commit implicitly: checked
before/after table metadata and durable checkpoints support recovery, while
backfill writes and completion checkpoints
share a transaction. See [MySQL/MariaDB migrations](mysql-migrations.md). Current
live acceptance uses MySQL 8.4 and MariaDB 11.8; the MariaDB driver's lower
connection minimum has not received that full acceptance suite.

Saved migrations contain immutable snapshots, operations, predecessor checksums
and explicit renames/conversions. Tests exercise fresh replay, older-version
upgrades, safe SQLite rebuilds, PostgreSQL constraint/catalog behavior, baseline,
drift, version compatibility, durable backfills and nontransactional recovery.
The migration CLI and real build_runner process workflows test application-facing
commands, including failure repair and stale-output cleanup.

Unmanaged views, triggers, specialized indexes, policies and table options require
review. PostgreSQL policy reports now retain roles, command, mode and expressions,
plus enabled/forced row-security flags. Actual triggers are created and exercised
after read-only import/verification on both backends. Baseline verifies declared
schema facts and returns unmanaged metadata; it does not recreate or certify
grants, every extension, authorization behavior or the whole database environment.

## Platform and tooling scope

Native SQLite and PostgreSQL are checked against SQLite 3.53.4/PostgreSQL 18.4.
MySQL 8.4 and MariaDB 11.8 have separate live driver, typed query, import,
transaction and migration-recovery suites.
Browser reports cover real Chrome JS and Dart WASM, worker memory/OPFS storage,
reopen, interruption recovery, upgrade and watch. Android Flutter checks cover
actual debug-to-AOT APK replacement and independent-process restart. These do
not certify every database version, browser, physical device, iOS or macOS Flutter.
Current source/validation revisions are recorded in [progress](progress.md).
Each platform capture is tied to its recorded source revision; consult the latest
acceptance record before relying on a historical platform result.

Driver configuration is typed and explicit. PostgreSQL reuses its driver's pool,
offers borrowed-pool ownership and certificate-verifying TLS by default; SQLite
owns one background connection behind a unified native/browser entrypoint.
Memory and named persistent settings are shared; native paths remain explicit.
Flutter Web bundles default assets, with optional browser resource overrides. URL options are
not silently merged with typed settings. MySQL/MariaDB own one queued physical
connection each, with certificate-verifying TLS by default and explicit capability
limits. Unsupported transports, serverless sessions, replica routing and additional
connection-pool variants need their own adapters and verification.

Generation and completion measurements cover 10/100/1000 models. The declaration
experiment normalized three input forms to identical generated APIs. The current
package supports ordinary immutable model classes with nominal results, alongside
Record declarations; see [authoring](authoring.md). Named Record field rename is unavailable
in the checked SDK. The captured same-session class rename timeout has a checked
server-restart path; it is not described as a working general IDE workflow.
Runtime cost reports compare identical SQL/driver/result workloads, including a
controlled TCP delay, with their sampling and allocation limits stated explicitly.
