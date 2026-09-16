# Dart ORM

A new Dart 3.13 ORM designed around record schemas, typed relationships,
composable selections, and explicit database sessions.

The implementation has separate real SQLite, PostgreSQL, Chrome, Flutter Web and Android
verification records. See [current progress](docs/progress.md),
[capability limits](docs/capabilities.md) and [design acceptance](docs/acceptance.md)
for which revision and scenarios each record covers.

One package, independent SQLite and PostgreSQL entry points, no runtime reflection.
This branch is unrelated to earlier ORM implementations.

The [SQLite entry point](docs/sqlite-web.md) works on native platforms and the web,
with background execution and the same generated query API. Flutter Web bundles
its worker/WASM resources automatically; plain Dart uses `dart run orm web-assets`.
The [native Flutter example](docs/flutter.md) verifies Android APK upgrades,
background SQLite, persistence and commit-driven query subscriptions.

```sh
dart pub get
dart run orm generate example/schema.dart
dart run example/main.dart
dart run example/queries.dart
dart test
```

For incremental generation, enable `orm:orm` for explicit schema roots in
`build.yaml` and run `dart run build_runner watch`. See
[generation and builds](docs/generation.md) for setup, dependency tracking and
reproducible generation measurements.

Declare data once in [schema.dart](example/schema.dart):

```dart
typedef User = ({
  @Id.generated() int id,
  @Unique() String email,
  String? nickname,
});
final users = entity<User>();
```

Import the generated client and a driver. The client exports `User` and the driver
exports the portable query API:

```dart
import 'package:orm/migrate.dart';
import 'package:orm/sqlite.dart';
import 'schema.orm.dart';

Future<void> main() async {
  final db = await sqlite(const SqliteOptions.memory());
  try {
    await Migrator(db).apply([
      Migration.create('0001_initial', appSchema, dialect: .sqlite),
    ]);
    final User user = await db.users.create(email: 'seven@example.com');
    await db.users.byId(user.id).patch(nickname: .set('Seven'));
    final List<String> emails = await db.users.select((u) => u.email).get();
    print(emails);
  } finally {
    await db.close();
  }
}
```

For PostgreSQL, import `postgres.dart` and use
`postgres(PostgresOptions(url: url))`; TLS certificate verification is the default.
Each backend has its own transaction options and migration history. Choose the
engine when initializing that history, and keep its reviewed Dart migrations and
static registry in version control. A connection change does not translate history.

The example above creates a temporary in-memory schema. The persistent
[migration entrypoint](example/migrate.dart) fixes SQLite: run
`dart run example/migrate.dart check`, then set `ORM_SQLITE_PATH` before `apply` or
`verify`. A PostgreSQL project creates its own PostgreSQL history and connection
entrypoint. See [migrations](docs/migrations.md) and [resumable backfills](docs/backfills.md).

Read [API and mental model](docs/api.md) for imports, current declarations versus
historical schemas, prepared versus executed operations, selection nullability,
and transaction ownership. Inside a transaction, build every query from `tx`;
subqueries, CTEs and UNION operands must share that same view.

For an existing database, [import a Record declaration](docs/importing.md), review
its report, generate the client, and baseline the current schema without copying
existing rows.

Declare [row CHECK constraints](docs/checks.md) with explicit SQL and optional
backend overrides; generated snapshots support catalog verification, import and
reviewed constraint migrations.

Use [client defaults](docs/defaults.md) for typed Dart value factories and SQL
defaults for database-generated values, with explicit omission/value/default inputs.
Declare [computed columns](docs/computed.md) for database expressions with typed
read-only results, explicit stored/virtual modes and reviewed migrations.

Model [many-to-many memberships](docs/relations.md#many-to-many-with-business-fields)
with an explicit association table, typed business fields and per-parent pagination.
Run `dart run example/teams/main.dart` to see its selected records and SQL counts.

Use `query.inspect()` for SQL templates, selected columns, joins and conditional
relation batches without connecting. Optional `onAcquire`, `onQuery` and `onDecode`
callbacks measure execution phases. See [plans and observations](docs/observability.md).

For complex SQL files, [generate named queries](docs/named-sql.md) with typed
Record parameters/results, native database structure checks and the same query
composition, transaction and streaming APIs.

Use `query.stream(batchSize: 128)` with `await for` to read through a database
cursor. Reads and mutations accept `ExecutionOptions` for connection acquisition
limits, statement deadlines and cancellation. See [streaming and execution](docs/execution.md) for connection
lifetime, batch sizing, transaction-wide deadlines and failure outcomes.

The [runtime cost report](docs/performance.md) compares the same driver, SQL and
result shapes across SQLite, local PostgreSQL and a controlled TCP delay. It
separates normal timing from acquisition probes, live heap and allocation traces.

Single relationships use JOINs when declared keys prove uniqueness; collections
load in parameter-aware batches. Both support typed nested selections. See
[relationship strategies](docs/relations.md) for composite keys, per-parent
pagination and explicit `.join`/`.batch` choices.

Domain IDs, custom classes, record values and enums retain their types in generated
APIs. Declare public const codecs with `@UseCodec`; use `@EnumValue` for stable
stored labels. See [types and JSON](docs/types.md) for codec validation, nullable
values and the distinction between SQL NULL and JSON null.

Use `query.watch()` for typed snapshots after relevant committed writes.
Transactions merge notifications; rollbacks do not notify. See
[query subscriptions](docs/watch.md) for relation dependencies, pause/cancellation,
and explicit notifications for raw SQL or external writers.

The [query cookbook](example/queries.dart) runs filters, joined ordering, relation
counts, grouped CTEs, windows, subqueries and cursor pagination. See
[query usage](docs/queries.md) for the API and PostgreSQL example configuration.

Combine scalar or `.row` projections with `union`/`unionAll`, then map the
result to a Record or DTO. Sets support typed exported columns, CTEs, streaming
and subscriptions. See [queries](docs/queries.md) for scope,
nullability and codec requirements.

Set `ORM_TEST_POSTGRES` to a **disposable** local PostgreSQL database to include
PostgreSQL integration tests. The tests create and drop their own test tables.
