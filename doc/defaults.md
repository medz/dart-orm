# Client values and database defaults

Use `clientDefault` when Dart should generate an omitted insert value. Use
`defaultValue` for typed database constants, or `defaultSql` for a SQL expression.

```dart
String initialLabel() => 'draft';

final entry = model('entries', (
  id: identity(),
  createdAt: dateTime(clientDefault: DateTime.now),
  label: text(clientDefault: initialLabel),
  state: text(defaultValue: 'server'),
));

final created = await db.entry.create(); // Dart timestamp/label; database id.
print(created.label); // draft
await db.entry.create(label: .set('manual'));
await db.entry.create(state: .defaultValue()); // SQL supplies "server".
```

Factories can be public top-level functions, static methods, constructors or
public const function references. They must accept a call without required
arguments and return a type compatible with the field, including domain types
and nullability. Optional arguments keep their Dart defaults. Instantiate generic
functions explicitly, for example `text().nullable(clientDefault: empty<String>)`. Factory results
are not awaited: an async `Future<String>` is not a value for a `String` field.
Generation reads the reference and type without calling it.

## Creation and updates

Generated creation parameters with client defaults use `Change<T>`, just like
fields with SQL defaults:

| Creation input | Behavior |
| --- | --- |
| Omitted or `.keep()` | Generate the client value if declared; otherwise omit the SQL column |
| `.set(value)` | Use the explicit value without calling that column's factory |
| `.set(null)` on a nullable field | Store SQL NULL without calling the factory |
| `.defaultValue()` | Use the database default or identity without calling the factory |

A column can combine `clientDefault` with a database default. Omission uses the
client factory; `.defaultValue()` uses the database default. Choose either
`defaultValue` or `defaultSql` for that database default, not both.
`.defaultValue()` requires a database default or identity; it does not rerun a
client factory. A nullable
factory returning null stores SQL NULL. Patches and conflict updates keep omitted
fields unchanged. SQLite does not support UPDATE SET DEFAULT.

`create`, `createRow`, `insert` and `insertMany` share this behavior. Factories run
once per omitted column per input row while constructing an insert. Batch values
are prepared in input order. Compilation, conflict-clause construction and repeated
execution of that prepared mutation retain those values. Construct a fresh insert
when fresh values are needed. An INSERT prepares defaults even if ON CONFLICT
later skips or updates the row; only explicit conflict assignments change stored
values. Raw `db.execute` SQL bypasses client factories.

Factory errors propagate before that INSERT is sent, but earlier factories may
already have run. Rollback does not reverse Dart side effects or return consumed
identifiers. Rebuilding an insert inside a transaction retry calls its factories
again. Keep factories short; external effects need their own idempotency handling.
They run in the caller's Dart isolate, including with background SQLite or a
browser worker.

## Physical schema

`Column<T>.clientDefault` is runtime metadata. It adds no database DEFAULT and is
absent from saved snapshots, catalog imports and migration checksums. Changing only
a client factory produces no DDL. A required column with only a client default
still needs an explicit value from raw-SQL writers.

Adding a non-null column with only a client factory still needs a database default
or an explicit backfill for existing rows. Migrations never run the client factory
to populate historical data.

A database identity may also have a client factory. Omission inserts the client
ID explicitly; `.defaultValue()` asks the database to generate one. PostgreSQL
does not advance its identity sequence for an explicit ID; SQLite rowid allocation
considers existing rowids. Coordinate uniqueness when mixing these sources.

`DateTime.now` is application time encoded by the UTC instant codec, not SQL
CURRENT_TIMESTAMP. Ordinary Dart constructor defaults do not declare database
defaults. Use [computed columns](https://github.com/medz/dart-orm/blob/main/doc/computed.md) for expressions the database
recomputes when their source values change.
