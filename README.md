# Dart ORM

A new Dart 3.13 ORM designed around record schemas, typed relationships,
composable selections, and explicit database sessions.

Development is in progress. See [the design](research/new-dart-orm-design.md)
and [implementation status](docs/progress.md).

One package, independent SQLite and PostgreSQL entry points, no runtime reflection.
This branch is unrelated to earlier ORM implementations.

```sh
dart pub get
dart run orm generate example/schema.dart
dart run example/main.dart
dart test
```

Declare data once in [schema.dart](example/schema.dart):

```dart
typedef User = ({
  @Id.generated() int id,
  @Unique() String email,
  String? nickname,
});
final users = entity<User>();
```

Import the generated client and a driver:

```dart
final db = await sqlite(const SqliteOptions.memory());
await Migrator(db).apply([Migration.create('0001_initial', appSchema)]);
final user = await db.users.create(email: 'seven@example.com');
await db.users.byId(user.id).patch(nickname: .set('Seven'));
final emails = await db.users.select((u) => u.email).get(); // List<String>
await db.close();
```

For PostgreSQL, use `postgres(PostgresOptions(url: url))`; TLS certificate
verification is the default. Each backend has its own transaction options.
Migrations should be saved, reviewed and committed before use in persistent
environments. See [migration workflows](docs/migrations.md) for diffs, renames,
rebuilds and existing-database baselines. The in-memory example builds an initial migration directly for clarity.

Use `query.stream(batchSize: 128)` with `await for` to read through a database
cursor. Reads and mutations accept `ExecutionOptions` for statement deadlines and
cancellation. See [streaming and execution](docs/execution.md) for connection
lifetime, batch sizing and backend behavior.

Single relationships use JOINs when declared keys prove uniqueness; collections
load in parameter-aware batches. Both support typed nested selections. See
[relationship strategies](docs/relations.md) for composite keys, per-parent
pagination and explicit `.join`/`.batch` choices.

Set `ORM_TEST_POSTGRES` to a **disposable** local PostgreSQL database to include
PostgreSQL integration tests. The tests create and drop their own test tables.
