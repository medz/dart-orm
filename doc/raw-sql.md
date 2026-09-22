# Raw SQL with optional types

`Sql` stores trusted SQL and separately bound values. It has no connection and
needs no query generator. Import `package:orm/orm.dart` or a database entrypoint.

```dart
final result = await db.raw(Sql(
  'SELECT id, email FROM users WHERE email = :email',
  parameters: {'email': email},
));
// SqlResult: columns, positional rows, affectedRows and lastInsertId.
```

Values are always parameterized. The optional part is the Dart parameter and
result contract. Raw results retain duplicate labels instead of losing values
in a map. SQL semantics and supported statements remain engine-specific.

## Typed functions and reusable results

Reuse generated fields or physical `Column<T>` codecs. A result column describes
an SQL label, without carrying identity, defaults or other write constraints.

```dart
final u = userTable.alias().fields;
final userRow = (
  u.id.result(),
  u.email.result(),
).map((id, email) => (id: id, email: email));

SqlQuery<({int id, String email})> userById(int id) => Sql(
  'SELECT email, id FROM users WHERE id = :id',
  parameters: {'id': u.id.bind(id)},
).returns(userRow);

final query = userById(7);
final rows = await db.query(query);
await db.transaction((tx) => tx.query(query));
```

Ordinary Dart functions enforce parameter types and support shared business
logic. Return a record, scalar or class through `map`; no DTO is generated.
Use `ResultColumn('total', Codecs.integer)` for computed results. Use
`field.result(as: 'owner_id')` for aliases and `.nullable()` for outer joins.
This declares the expected result; it does not prove an SQL expression's type.

Compositions support two through six independently typed shapes, including nested
shapes. Reusing one label with conflicting codecs fails at construction. Required
labels must occur exactly once in actual result metadata, including zero-row
results. Extra SQL columns are ignored. Mappers run only for actual decoded rows.
Outer-joined object groups require an explicit presence key; nullable fields alone
do not establish whether an object exists.

`SqlValue(value, codec)` gives parameters an explicit storage/domain codec without
a table. Encoding happens once at construction. Parameter maps and byte buffers
are copied; JSON codecs serialize then. Raw parameters accept null, scalar values,
DateTime, Uint8List, SqlReal and SqlJson. Maps, lists and domain objects require a
codec. Raw scalars use driver inference; typed bindings add storage casts where
needed, such as standalone PostgreSQL parameters. MySQL can infer a bare binary
parameter as text: bind bytes into a BLOB column and select that column to preserve
binary result metadata. A result codec cannot repair driver-level decoding of a
misclassified native result. For MySQL JSON results, select
`CAST(json_expression AS CHAR)` when distinguishing JSON null from SQL NULL is
required; the current driver loses that distinction in native JSON projections.
`Codecs.jsonDocument` decodes the resulting JSON text. Use explicit dialect
variants for these native result differences. MySQL may infer arithmetic on bare
parameters as floating point; use an explicit `CAST(... AS SIGNED)` when promising
an integer result. Result codecs validate/decode returned storage; they never
rewrite the SQL projection.

## Fragments and database variants

```dart
final first = Sql('SELECT id, email FROM users WHERE id = :id',
    parameters: {'id': 1});
final second = Sql('SELECT id, email FROM users WHERE id = :id',
    parameters: {'id': 2});
final candidates = Sql.join([first, second], separator: ' UNION ALL ');
final query = Sql.parts([
  'WITH candidates AS (', candidates,
  ') SELECT id, email FROM candidates ORDER BY id',
]).returns(userRow);
```

Every fragment owns its parameter names. PostgreSQL/SQLite reuse repeated local
slots; MySQL/MariaDB duplicate values in positional occurrence order. Fragments
are separated by newlines and must have complete quotes/comments. One trailing
semicolon is accepted for the entire statement; multiple statements are rejected.
Use `:name` placeholders rather than driver-native `$1`, `?` or `@name` syntax.
PostgreSQL syntax can also contain a literal colon followed by a name, such as
an array-slice bound. Escape that colon as `\:` outside quotes/comments:
`Sql(r'SELECT items[1\:array_length(items, 1)] FROM data')`.
Compilation removes the escape and preserves the native expression. To bind
both bounds, separate the slice colon with spaces: `items[:start : :end]`.
Mode-dependent MySQL backslash strings and executable comments are rejected;
bind string values instead.

`Sql.identifier(name)` quotes one identifier, including literal dots.
`Sql.table(tableSchema)` quotes namespace and table separately; namespaces require
PostgreSQL. Identifier selection remains the application's responsibility.
`Sql.join(values.map(Sql.value))` builds bound lists. For an empty `IN` list,
choose an explicit predicate such as `FALSE` rather than emitting `IN ()`.

Use `Sql.dialects({SqlDialect.sqlite: ..., SqlDialect.postgres: ...})` for native
variants sharing one result shape. Missing branches fail before I/O; no SQL
translation or fallback is attempted. A descriptor can be reused concurrently
across databases; this does not cache rows or server prepared statements.

## Execution, streams and watches

`db.query` executes the supplied statement once without adding a CTE or LIMIT.
Read cardinality from the returned list with `.single` or `.firstOrNull`.
For native DML `RETURNING`, attach a shape and use the same method. Unsupported
native syntax remains a database error.

```dart
await for (final row in db.streamSql(query, batchSize: 128)) {
  print(row);
}
final snapshots = db.watchSql(query, reads: [userSchema]);
await db.raw(
  Sql('UPDATE users SET email = :email WHERE id = :id',
      parameters: {'email': email, 'id': id}),
  changedTables: [userSchema],
);
```

Streams use one cursor, bind column metadata on the first batch (even empty), and
fetch on demand without an extra metadata query. Finish or cancel within the
owning session/transaction. Streaming inherits each driver's cursor restrictions;
use `raw`/`query` for writes. The current MySQL/MariaDB adapters reject `streamSql`
with `CAPABILITY.STREAM`. Watches require a root database and nonempty explicit
physical `reads`: result columns cannot reveal hidden dependencies. Writes notify
after commit; rollbacks do not notify. Watches repeat the statement, so callers
must choose SQL suitable for repeated execution.

ExecutionOptions, query/decode observations and connection ownership follow the
normal execution chain. Decode/mapper failure makes an explicit transaction
uncommittable, even when caught; use a savepoint for a recoverable substep.
Outside a transaction, a write may already be committed when decoding fails.
The ORM does not automatically retry that statement.

## Inspect and check without generating queries

```dart
final command = query.sql.compile(db.capabilities); // Offline: SQL and bindings.
final check = await checkSqlQuery(db.sql, query);    // Native preparation.
print(check.storageTypesChecked);
```

`checkSqlQuery` checks SELECT/WITH/VALUES sources by preparing a projected subquery.
It does not execute application expressions or support DML/RETURNING checks.
SQLite, MySQL and MariaDB report structure only. PostgreSQL additionally compares
native storage families. No engine check proves nullability, numeric range or
custom domain conversion; some engines rename duplicate labels inside subqueries,
so actual runtime labels are checked again. Prepared resources are released in the
same session, or the connection is discarded if cleanup fails.

Import application query functions in an ordinary development script and use the
same connection factory as the application or `orm.config.dart`. Call `db.query`
explicitly when a real preview is wanted; preparation and execution are distinct
operations. SQL files may be loaded by such a script or embedded at build time.
There is no automatic function discovery, query registry or query-specific build
step. See [the runnable example](https://github.com/medz/dart-orm/blob/main/example/raw_sql.dart).

## Replacing the former Named SQL API

Delete query declarations, generated `.queries.dart` files and `orm:queries`
builder entries. Replace generated methods with plain functions returning
`SqlQuery<R>`, then call `db.query`. Remove `queries generate/check` commands;
use `compile` and `checkSqlQuery` from a development script. Schema generation
continues unchanged. Keep immutable migration history as it is.

Move former `.where`, `.orderBy`, CTE and UNION operations into SQL or explicit
fragments. A raw result shape is not a mutable table and does not add query-builder
methods. Use `streamSql` and `watchSql` for cursor and subscription behavior.
