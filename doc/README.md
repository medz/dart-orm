# Using Dart ORM

## Models and generation

Declare immutable classes with final scalar fields. Dart 3.13 primary
constructors keep the declaration small. Table and column names are
physical identities, independent of Dart class or record names.

PostgreSQL identifiers are limited to 63 UTF-8 bytes. SQLite identifiers compare
ASCII letters without case sensitivity, and table names beginning with `sqlite_`
are reserved. `_orm_migrations` belongs to the migration runner. Generation and
typed queries reject invalid physical identities before writing files or SQL.

```dart
import 'package:orm/schema.dart';

@Table('users')
final class const User({
  @PrimaryKey(autoIncrement: true)
  required final int id,
  @Unique()
  required final String username,
  required final int age,
  final String? nickname,
});

@SelectFrom(User)
typedef UserCard = ({int id, String username});
```

Use `@Column(name: 'joined_at')` to map a field name and
`@Column(defaultValue: true)` to declare a literal database default.
`@References('users', onDelete: 'cascade')` declares a foreign key targeting the
physical primary-key column `id`. Targets must exist in the same declared schema
and have compatible types. Every table needs exactly one non-null primary key.
An identity key is an integer primary key and is omitted from generated creation
arguments. Ordinary constructors are supported when every parameter directly
assigns its matching field. Transforming initializers, assertions, bodies and
uninitialized late fields are rejected: decoding must faithfully return the row
the database stored. Constructor defaults do not become database defaults.

```sh
dart run orm generate --schema lib/models.dart --out lib/models.db.dart --name AppDatabase --engine sqlite
# Use --engine postgresql for a PostgreSQL snapshot.
dart run orm generate --schema lib/models.dart --out lib/models.db.dart --name AppDatabase --engine sqlite --check
```

Generation writes an independent client and `models.snapshot.dart`. `--check`
compares both outputs without changing files. There is no build runner, runtime
reflection or `part` library. Import the client and your models normally.
The current generator reads one model library; split unrelated schemas into
separate clients when needed.

## Connections and ownership

```dart
import 'package:orm/sqlite.dart';
final db = AppDatabase(SqliteDriver.open('app.sqlite'));
```

```dart
import 'package:orm/postgres.dart';
final db = AppDatabase(PostgresDriver(
  Endpoint(host: 'localhost', database: 'app', username: 'app', password: secret),
  settings: PoolSettings(maxConnectionCount: 4, sslMode: SslMode.verifyFull),
));
```

The generated database owns its driver. Close it in `finally`; closing drains
admitted work and rejects new work. `db.database` exposes that same owned runtime
for `MigrationRunner`; do not wrap the driver again or close it separately.
`db.session` provides raw execution and typed tables in the root scope.

SQLite uses one native connection with FIFO acquisition. PostgreSQL uses its
native connection pool; configure pool limits, TLS and timeouts explicitly.
SQLite runs synchronously on its isolate, so move heavy workloads to a worker
isolate when a UI needs a responsive event loop.

## Writes and reads

```dart
final user = await db.users.create(username: 'seven', age: 28);
await db.users.update(user.id, age: 29);        // Keeps nickname.
await db.users.update(user.id, nickname: null); // Clears nickname.
final existing = await db.users.get(user.id);   // User?
final removed = await db.users.delete(user.id); // affected row count
```

Creation omits database defaults and nullable values unless provided. Updates
must contain at least one field. Primary keys cannot be updated. Generated
arguments retain their declared Dart types, including optional non-null fields;
passing null to a non-null field is a static error.

```dart
import 'package:orm/query.dart';

final adults = db.users.where(age: gte(18) & lt(65));
final cards = await adults
    .where(username: startsWith('sev'))
    .orderBy(age: desc)
    .orderBy(id: asc)
    .limit(20)
    .offset(0)
    .select<UserCard>();
print(cards.first.username);
final models = await adults.all(); // List<User>
```

Queries are immutable. Fields in one `where` and chained `where` calls combine
with AND. `&` and `|` combine conditions on the same field. `eq`, `ne`, `gt`,
`gte`, `lt`, `lte`, `oneOf`, `startsWith` and `containsText` bind values.
Text helpers escape SQL wildcard characters and use the engine's LIKE/collation
rules (SQLite defaults to ASCII case-insensitive LIKE; PostgreSQL defaults to
case-sensitive LIKE). `eq(null)` uses IS NULL; `ne(null)` uses IS NOT NULL. Empty `oneOf` matches
no rows; nullable `oneOf` includes SQL NULL when explicitly listed. Other
comparisons retain SQL's three-valued null behavior.

Each `orderBy` specifies one field; chain calls for sort precedence. Set an
explicit order for stable paging. Negative limits and offsets fail before SQL.
Registered selections must have exactly matching field names, types and
nullability. Unknown selection types fail before SQL. `.all()` returns full
models; `.select<T>()` fetches only the columns registered for T.

To claim a unique key without changing an existing row:

```dart
final user = await db.users.createIfAbsent(
  .username,
  username: 'seven',
  age: 28,
);
// user is null if that username already exists.
```

The generated target type contains the table's insertable single-column unique
keys. Supply a non-null target value. Other constraint failures propagate.
`createIfAbsent` executes one INSERT ON CONFLICT DO NOTHING RETURNING; replay
handling remains explicit in application code.

Filters are preserved on `get`, `update`, `delete`, `increment` and `decrement`.
Paging and sorting on those operations are rejected. `create` requires an
unfiltered table. Numeric changes accept positive amounts on non-null numeric
value fields and execute one guarded UPDATE RETURNING. Integer bounds are checked
in that statement; overflow returns null without changing the row. SQLite also
guards finite REAL arithmetic; PostgreSQL reports real overflow as a SQL error.

```dart
final product = await tx.products
    .where(stock: gte(quantity))
    .decrement(productId, stock: quantity);
if (product == null) throw StateError('Sold out');
```

Relationship loading is explicit: read the root page, then fetch related rows
with `oneOf` on the foreign key. [The complete example](../example/shop.dart)
loads users and posts with two SELECTs in one read-only transaction. It also
shows sorted product locks, atomic stock changes, integer-cent totals and
idempotent request replay without repeating stock changes.

## Transactions, streaming and raw SQL

```dart
await db.transaction((tx) async {
  final user = await tx.users.create(username: 'seven', age: 28);
  await tx.posts.create(authorId: user.id, title: 'Hello');
});
```

The callback pins one physical connection. Success commits; exceptions roll
back. Use only the supplied `tx` in the callback. Root queries, nested
transactions and manually issued boundaries are rejected. Transaction sessions
expire after the callback. A database SQL failure poisons the transaction even
if the application catches it. Await issued work and propagate business
failures. There are no automatic retries; choose retry policy in the application.

Default isolation is serializable. PostgreSQL also supports readCommitted and
repeatableRead; SQLite rejects those levels. `readOnly: true` uses PostgreSQL's
READ ONLY mode or SQLite's scoped query_only setting. Raw SQL is trusted
application code, not a SQL sandbox.

```dart
await db.transaction((tx) async {
  await for (final user in tx.users.stream(fetchSize: 200)) {
    consume(user.username);
  }
}, readOnly: true);
```

Streaming uses bounded primary-key batches within an explicit transaction.
Integer and text keys are supported. Custom order and offset are rejected;
limit is honored. Cancellation stops further batches. It is a keyset reader,
not a server cursor or a database change subscription.

Raw statements use `Session.run`. Bind every value with `?` for SQLite or `$1`,
`$2`, ... for PostgreSQL. Decode positional results with `decodeValue<T>`.
Raw SQL is the direct extension point for joins, aggregates and engine-specific
features; inspect its result shape in application code.

Set `onEvent` on `AppDatabase` to observe SQL text, elapsed time, result counts,
transaction IDs, and begin/commit/rollback events. Bound values are excluded.
Observer failures do not change database outcomes. SQLite read-only setup also
emits PRAGMA statements; account for these when measuring total work.

## Types and current limits

| Dart | SQLite | PostgreSQL |
| --- | --- | --- |
| int | INTEGER | BIGINT |
| String | TEXT | TEXT |
| bool | INTEGER, 0/1 | BOOLEAN |
| double | REAL | DOUBLE PRECISION |
| DateTime | INTEGER, Unix epoch microseconds | TIMESTAMPTZ |
| Uint8List | BLOB | BYTEA |

Nullable declarations allow SQL NULL. Dates return UTC instants with microsecond
precision; they do not preserve the original timezone. SQLite integer storage
preserves ordering before and after the Unix epoch, including expanded years.
PostgreSQL applies its native timestamp range. Floating-point values are unsuitable
for exact money; use integer minor units as the shop example does. Column definitions are
not inferred from arbitrary Dart objects, enums or custom serializers.

Native SQLite and PostgreSQL are verified on macOS and Linux. SQLite RETURNING
needs SQLite 3.35 or newer and is capability-checked. Windows, Web and Flutter
packaging remain unverified. MySQL and MariaDB are outside this rewrite.
PostgreSQL verification uses PostgreSQL 18; older server versions remain
unverified.
Composite keys, typed joins, cross-field OR, relation DSLs, schema namespaces,
client defaults, conflict updates and watchers are
not currently implemented. Raw SQL and ordinary Dart composition cover the
complete demonstrated business workflow without adding alternate query APIs.

This rewrite changes generated clients and migration definitions. There are no
compatibility readers for old JSON snapshots or old client APIs. Existing
production databases require a separately reviewed baseline; do not apply the
example history to them.
