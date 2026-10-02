# Client values and database defaults

Use `@ClientDefault` when Dart should generate an omitted insert value.
`@DatabaseDefault(value)` declares a typed database constant;
`@DatabaseDefault.sql(expression)` declares trusted SQL.

```dart
import 'package:orm/schema.dart';

String initialLabel() => 'draft';

@Model(table: 'entries')
final class Entry({
  @Id(generated: true) required final int id,
  @ClientDefault(DateTime.now) required final DateTime createdAt,
  @ClientDefault(initialLabel) required final String label,
  @DatabaseDefault('server') required final String state,
});

// After generation:
final created = await db.entry.create(); // Dart timestamp/label; database id.
print(created.label); // draft
await db.entry.create(label: 'manual');
await db.entry.plan.insert(entryInsert.values(state: .databaseDefault())).row(); // SQL supplies "server".
```

Factories can be public top-level functions, static methods or constructor
tear-offs. They must accept a call without required arguments and return a type
compatible with the field, including its domain type and nullability. Optional
arguments keep their Dart defaults. Factory results are not awaited: an async
`Future<String>` is not a value for a `String` field. Generation reads the
reference and type without calling it.

## Constructor defaults

An ordinary constant constructor default is a client-side fallback. It is used
for omitted inserts when no explicit client factory, database default or
identity takes precedence:

```dart
@Model()
final class Draft({
  @Id(generated: true) required final int id,
  final String label = 'draft',
});
```

This declares no SQL DEFAULT. Raw-SQL writers must still supply `label`.
Full reads always supply the actual database value to the original constructor,
so a constructor fallback never hides a missing selected field.

## Creation and updates

Generated `create(...)`, `userInsert(...)` and `userPatch(...)` accept literal
values. Omission remains distinct from explicitly supplying null. Use the
factory's `.values(...)` when you need an explicit write intent:

| Input | Behavior |
| --- | --- |
| Omitted or `.keep()` in an insert | Use its client default, otherwise omit the SQL column |
| Literal value or `.set(value)` | Store the value without calling that field's factory |
| Explicit null or `.set(null)` | Store SQL NULL in a nullable column |
| `.databaseDefault()` | Use the database default or identity without calling the factory |
| Omitted or `.keep()` in a patch | Leave the stored value unchanged |

A field can combine `@ClientDefault` with `@DatabaseDefault`. Omission uses the
client factory; `.databaseDefault()` uses the database default. Specify a database
constant or a SQL expression, not two database-default annotations.
A generated `@Id(generated: true)` cannot also declare `@DatabaseDefault`:
the identity already supplies its database value. It may declare `@ClientDefault`;
omission then uses that factory and `.databaseDefault()` selects the database identity.
`.databaseDefault()` requires a database default or identity; it does not rerun a
client factory. A nullable factory returning null stores SQL NULL.
Patches and conflict updates keep omitted fields unchanged. SQLite does not
support UPDATE SET DEFAULT.

Model writes defer factory evaluation until a terminal or explicit `prepare()`.
A prepared mutation retains those values across compilation, conflict-clause
construction and replay. Calling another terminal on the original model write
prepares fresh values. Handwritten Table `insert`/`insertMany` prepare immediately;
`create` and `createRow` prepare and execute together. They share structural/scope
validation before factories and evaluate defaults in input-row/schema-column order.
An INSERT prepares defaults even when ON CONFLICT later skips or updates the row;
only explicit conflict assignments change stored values. Raw SQL bypasses factories.

Factory errors propagate before that INSERT is sent, but earlier factories may
already have run. Rollback does not reverse Dart side effects or return consumed
identifiers. Rebuilding an insert inside a transaction retry calls its factories
again. Keep factories short; external effects need their own idempotency handling.
They run in the caller's Dart isolate, including with background SQLite or a
browser worker.

## Physical schema

Client defaults are runtime metadata. They add no database DEFAULT and are
absent from saved snapshots, catalog imports and migration checksums. Changing
only a client factory or constructor fallback produces no DDL.

Adding a non-null field with only a client default still needs a database default
or an explicit backfill for existing rows. Migrations never run today's client
factory or constructor to populate historical data.

A database identity may also have an explicit client factory. Omission inserts
the client ID; `.databaseDefault()` asks the database to generate one. PostgreSQL
does not advance its identity sequence for an explicit ID; SQLite rowid
allocation considers existing rowids. Coordinate uniqueness when mixing sources.

`DateTime.now` is application time encoded by the UTC instant codec, not SQL
CURRENT_TIMESTAMP. Use [computed columns](https://github.com/medz/dart-orm/blob/main/doc/computed.md)
for expressions the database recomputes when their source values change.
