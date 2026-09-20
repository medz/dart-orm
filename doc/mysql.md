# MySQL and MariaDB

The native drivers use `mysql_client_plus` and require MySQL 8.4+ or MariaDB
10.6+. SQLite, PostgreSQL, MySQL and MariaDB remain distinct database engines.
Opening a MySQL driver against MariaDB, or the reverse, fails before use.

## Use the driver alone

```dart
import 'package:orm/drivers/mysql.dart';

final driver = await MysqlDriver.open(
  MysqlOptions(url: Uri.parse('mysql://user:password@localhost/app')),
);
try {
  final result = await driver.run(
    (connection) => connection.execute(
      SqlCommand('SELECT name FROM users WHERE id = ?', [42]),
    ),
  );
  print(result.rows);
} finally {
  await driver.close();
}
```

For MariaDB, import `package:orm/drivers/mariadb.dart` and use
`MariadbDriver.open(MariadbOptions(...))`. Its URL may use `mariadb://` or
`mysql://`; the server identity must still be MariaDB. These libraries do not
import ORM models, query builders, generation, or migration tooling.

All parameterized statements use the server's binary prepared-statement
protocol. Statements without parameters use the text protocol; the upstream
client's prepare operation cannot complete zero-parameter, zero-column
statements such as DDL and `ROLLBACK`. The driver never uses the client's named
parameter interpolation. Result columns preserve their order and duplicate
names; generated identities come from the server response as `lastInsertId`.

## Typed queries and mutations

Import `package:orm/mysql.dart` and open `mysql(MysqlOptions(...))` for a
`Database<Mysql>`, or use `package:orm/mariadb.dart` and
`mariadb(MariadbOptions(...))`. The independent `SqlBuilder` can also compile
the same queries without opening a connection. Bind values separately; the
compiler orders positional parameters by their final SQL occurrence.

Neither adapter advertises `RETURNING`. `createRow` instead inserts and reads
the result by primary key on the same transaction connection. It starts a
transaction when necessary and reuses an existing transaction. Primary keys
must be supplied as literal assignments, with at most one omitted generated
identity; tables without a primary key and keys computed by arbitrary SQL are
rejected before insertion. Precision-coerced primary-key assignments are also
currently rejected because the stored key can differ from the input. A failed
read or decode marks the transaction failed, even if application code catches
the exception. Plain `insert(...).execute()` remains available when no returned
row is needed.

Use `onDuplicateKeyUpdate` explicitly for native MySQL/MariaDB upserts. Any
duplicate primary or unique key can cause the update; callers cannot select a
particular conflict target. `onConflictUpdate` and `onConflictDoNothing` are
rejected. A self-assignment would still run update triggers, so it is not a
substitute for doing nothing. Affected-row counts follow the server's insert
and update semantics.

Typed JSON parameters are parsed as JSON expressions, and final projections
convert JSON to character text only when crossing the driver decoding
boundary. CTEs, scalar subqueries, and UNION operands retain native SQL values.
Use `Codecs.jsonDocument.nullable()` to distinguish `SqlJson(null)` from SQL
`null`. Direct `.distinct()` with a JSON result is rejected: deduplicate native
values inside a CTE, then read that CTE so the character conversion happens
afterwards:

```dart
final unique = db.table(documents)
    .select((row) => row.document)
    .distinct()
    .asCte('unique_documents');
final values = await unique.query.get();
```

JSON equality follows the selected engine. MySQL has native JSON storage;
MariaDB stores JSON as validated text. The ORM does not promise identical
object ordering, duplicate-key, or comparison behavior across engines.

Exact decimals use at most 65 digits and scale 0–30, with scale no larger
than precision. Big integers use `DECIMAL(65,0)`. Typed parameters are cast to
decimal storage so comparisons do not fall back to floating point. Column
constraints and MIN/MAX are available within engine limits. Explicit decimal `rounded`, `divide`,
`divideExpression`, and `average` reject unsupported exact-rounding semantics
instead of substituting approximate arithmetic. Decimal addition, subtraction and
multiplication and SUM reject `CAPABILITY.DECIMAL_PRECISION`: native arithmetic can
silently truncate fractional digits even when neither input exceeds the storage
limit, and a native SUM can saturate when materialized by a subquery. The
`exactDecimal` capability describes lossless values and comparisons, not all
arithmetic operators. Explicit expression `constrained` and decimal UNION/UNION ALL
are also rejected because the engines may silently clamp or narrow precision.
Assignments rely on the declared column and strict SQL mode rather than first
casting into a narrower intermediate value. Explicit `sql(...)` expressions remain available for applications that
accept the selected engine's bounded arithmetic semantics.

Temporal column precision is enforced by the selected engine on assignment;
rounding or truncation follows that engine and its session modes. Explicit
expression `withPrecision` is rejected because its cross-engine rounding
contract is not implemented for these engines.

## Connection ownership and limits

Each driver owns one physical connection. It queues complete `run` callbacks,
so transactions cannot interleave with another lease. Statements inside one
callback must be awaited before the next statement starts. A connection
cannot be used after its callback completes. `close()` waits for already
accepted work, and every concurrent close caller waits for the same result.

Lease release runs `ROLLBACK`, including after a successful callback, because
raw callers may leave a transaction open. Commit explicitly to persist a
transaction. This cleanup is one additional database round trip per lease;
several statements can share a lease. Session variables and temporary tables
belong to the connection and are not recreated for each lease.
Raw callers that change `autocommit`, `sql_mode` or `time_zone` must restore
the driver's documented settings before leaving that lease. In particular,
leaving autocommit disabled makes later writes part of an uncommitted transaction
that lease cleanup rolls back. Use managed transactions for application writes.

Results are materialized. `streaming` and `cancellation` capabilities are
false; requesting either reports an unsupported capability. `statementTimeout`
is true: `ExecutionOptions(timeout: ...)` bounds an individual statement through
the raw runtime and ORM, overriding the driver's `queryTimeout` default.
Query timeouts discard the connection. A timeout or connection loss does not
prove a write failed or rolled back, so an uncertain write must not be retried
automatically. Open a new driver after invalidation or disconnection; there is
no implicit reconnect. Transaction deadlines, cancellation tokens and retry
policies still require actual cancellation and remain unsupported.

The underlying client does not expose the server transaction status flags,
so `transactionActive` is `null`. The driver does not guess state from SQL
text. `SqlDatabase` and ORM transactions therefore check every statement,
including SQL executed on a connection borrowed through `tx.run`. Only one
SELECT, INSERT, UPDATE, DELETE, REPLACE, WITH, SHOW, DESCRIBE or EXPLAIN statement
is accepted. DDL, manual transaction control, SET, CALL, dynamic execution,
executable comments, multiple statements and ambiguous quoted backslash
escapes fail with `TRANSACTION.STATEMENT` before reaching the server. Use
`transaction()` and `savepoint()` for transaction boundaries, and bind values
separately. A caught statement failure still prevents committing that scope;
a savepoint can isolate a recoverable failure.

MySQL/MariaDB DDL may implicitly commit and cannot be made atomic by a Dart
callback. Run DDL outside runtime transactions, using the engine-specific
migration workflow. The independent low-level driver executes raw SQL without
this runtime guard and leaves transaction control to its caller.

## TLS and session behavior

`MysqlTls.verifyFull` is the default. It rejects invalid certificates rather
than inheriting the upstream client's permissive default. Supply a Dart
`SecurityContext` for private trusted certificate authorities.
`MysqlTls.require` deliberately skips certificate verification and is for
explicitly trusted environments such as local integration fixtures.
`MysqlTls.disable` is unencrypted; the current client requires TLS for
SHA-2 authentication, including MySQL's usual `caching_sha2_password` path.

Initialization sets the session time zone to UTC. It retains existing SQL
modes and adds `ANSI_QUOTES`, `NO_BACKSLASH_ESCAPES`, `STRICT_ALL_TABLES`,
`NO_ZERO_DATE`, `NO_ZERO_IN_DATE`, `ERROR_FOR_DIVISION_BY_ZERO`, and
`NO_ENGINE_SUBSTITUTION`. Double quotes therefore quote identifiers, and a
backslash in a string literal is an ordinary character. Bind values with
parameters instead of depending on string-literal escaping.

## Value boundaries

- Signed integer columns decode exactly into Dart's signed 64-bit `int`.
  Decimal columns stay decimal text and pass through `Codecs.decimal` without
  rounding through `double`. `BigInt` and `Decimal` inputs bind exact text.
- Boolean columns return integer `0` or `1`, which `Codecs.boolean` decodes.
- `BLOB` columns return bytes. The upstream binary decoder does not safely
  support all `BINARY`/`VARBINARY` columns or unsigned integer columns; those
  are outside this adapter's supported storage contract. For raw access,
  explicitly cast unsigned integers to character text and use `HEX(...)`
  for unsupported binary storage rather than relying on its decoder.
- Native `DateTime` parameters are converted to UTC; local date/time types
  retain their calendar meaning. Dates are limited to years 1000–9999.
  Binary temporal results preserve microseconds, including `.000001`.
  MySQL `TIME` can represent signed durations beyond 24 hours; such values
  are not `LocalTime` and should remain raw strings.
- Select JSON as `CAST(document AS CHAR CHARACTER SET utf8mb4)` for a
  lossless JSON text boundary. This distinguishes SQL `NULL` from JSON
  `null`, and works on both engines. The upstream decoder otherwise erases
  this distinction for a direct MySQL JSON column. Its parsed non-null JSON
  results are wrapped in `SqlJson` so JSON string scalars remain strings.

## Real database tests

`test/mysql_driver_test.dart` imports only the low-level driver libraries.
Set `ORM_TEST_MYSQL` and `ORM_TEST_MARIADB` to disposable database URLs.
The corresponding `ORM_TEST_MYSQL_TLS` and `ORM_TEST_MARIADB_TLS` variables
choose `verifyFull`, `require`, or `disable` (default `verifyFull`).

```sh
dart test test/mysql_driver_test.dart
```

The suite covers actual prepared statements, values, commit/rollback,
savepoints, abandoned transaction cleanup, error recovery, engine mismatch,
lease serialization, close draining, invalidation, and timeout handling.
Without a database URL that engine's integration group is explicitly skipped.
See `doc/progress.md` for which server versions have actually been validated.
`test/mysql_database_test.dart` exercises typed queries, JSON and decimal
boundaries, generated-row reads, relations, and transaction behavior.
`test/sql_mysql_review_test.dart` adds compiler and fault-injection regressions;
these synthetic checks do not replace the real database suites.
