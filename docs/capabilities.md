# Capability review

The acceptance scope comes from the [original design](../research/new-dart-orm-design.md).
Its common relational lifecycle is implemented in one package. Optional backend
extensions and untested deployment targets are not implied by a generic driver
or a successful test on another platform.

## Values and physical storage

| Design §5 requirement | Implementation and evidence | Explicit boundary |
| --- | --- | --- |
| Integer widths and web-safe exact values | `IntegerBits`, integer/BigInt codecs, integer/native/browser checks, catalog metadata and reviewed migrations | Native `int` is signed 64-bit; JS-safe `int` is narrower. BigInt uses exact digits, but SQLite BigInt text does not promise numeric ordering/arithmetic. |
| Exact decimal | Decimal arithmetic, comparisons, keys, aggregates/windows, precision/rounding, generated/imported metadata and migration/backfill checks | Finite values only; use the documented precision/range. No implicit conversion to approximate double. |
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
| Failure handling and streaming | Real interruption, unknown commit, bounded acquisition/retries, real cursors and awaited cleanup | An external side effect is not rolled back by SQL or safe to repeat automatically. Web interruption remains unsupported and is rejected. |
| Plans and observations | SQL/column/key/join/batch descriptions and actual acquisition/query/decode events | No general optimizer, result cache or hidden EXPLAIN ANALYZE. Timing scopes are documented, not total CPU attribution. |

See [query examples](queries.md), [relationships](relations.md),
[execution](execution.md) and [observability](observability.md).

## Migration and database adoption

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
Browser reports cover real Chrome JS and Dart WASM, worker memory/OPFS storage,
reopen, interruption recovery, upgrade and watch. Android Flutter checks cover
actual debug-to-AOT APK replacement and independent-process restart. These do
not certify every database version, browser, physical device, iOS or macOS Flutter.
The PostgreSQL catalog metadata change affects its PostgreSQL SQL branch; the
recorded SQLite web/Android execution paths and platform adapters are unchanged.

Driver configuration is typed and explicit. PostgreSQL reuses its driver's pool,
offers borrowed-pool ownership and certificate-verifying TLS by default; SQLite
owns one background connection with explicit memory/file/read-only settings.
The web driver has separate worker/persistence configuration. URL options are
not silently merged with typed settings. Unsupported transports, serverless
sessions, MySQL, replica routing and connection-pool variants need their own
adapters and verification.

Generation and completion measurements cover 10/100/1000 models. The declaration
experiment normalizes three input forms to identical generated APIs while the
public package ships Record authoring. Named Record field rename is unavailable
in the checked SDK. The captured same-session class rename timeout has a checked
server-restart path; it is not described as a working general IDE workflow.
Runtime cost reports compare identical SQL/driver/result workloads, including a
controlled TCP delay, with their sampling and allocation limits stated explicitly.
