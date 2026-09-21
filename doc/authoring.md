# Define your schema

Declare each model and table together with `model(...)`. Name columns in a
Record, then add keys, indexes and relationships in the same definition.
Generation produces immutable row classes and typed queries; no annotations or
separate hand-written row classes are needed.

```dart
import 'package:orm/schema.dart';

final Model user = model(
  'users',
  (
    id: identity(),
    email: text(unique: true),
    nickname: text().nullable(),
    active: boolean(defaultValue: true),
  ),
  relations: (u) => (posts: referencedBy(() => post),),
);

final post = model(
  'posts',
  (
    id: identity(),
    authorId: integer(),
    title: text(),
    createdAt: dateTime(clientDefault: DateTime.now),
  ),
  relations: (p) => (
    author: references(p.authorId, () => user, onDelete: .cascade),
  ),
  indexes: (p) => [
    index((p.authorId, p.createdAt, p.id), name: 'posts_author_timeline'),
  ],
);
```

Run `dart run orm generate lib/schema.dart`, or use
[build_runner watch](https://github.com/medz/dart-orm/blob/main/doc/generation.md). This produces `schema.orm.dart` with the
immutable `User`/`Post` row classes and typed query API, plus an independent
`schema.snapshot.dart` for migrations. The [company example](https://github.com/medz/dart-orm/blob/main/example/company/schema.dart)
includes self references and a many-to-many association with business fields;
`dart run example/company/main.dart` runs it against SQLite in memory.

Use `final name = model(...)` by default. `Model` is a non-generic declaration
type with no public constructor. For self references, write
`final Model name = model(...)`. For mutually related models, annotate enough
declarations to break every type inference cycle; the example annotates `user`.
These type annotations preserve field types in all selector callbacks.

The table name is explicit. The Dart declaration `user` supplies `User` and
`db.user`; the generator does not guess English singular/plural forms. Two models
with identical Record shapes still have separate table and nominal row identities.

The second argument is a named Record of `ColumnDefinition<T>` values. Dart
preserves each field's type and provides completion in local relation/index/key callbacks.
Generation also checks that every entry is a supported column declaration.

## Rows, inserts and updates

```dart
final User created = await db.user.create(email: 'seven@example.com');
await db.user.byId(created.id).patch(nickname: .set('Seven'));
await db.user.byId(created.id).patch(nickname: .set(null));

final List<String> titles = await db.user.byId(created.id)
    .select((u) => u.posts.select((p) => p.title).many()).single();
```

A generated row contains every stored field. Its constructor requires all values,
including nullable columns and identities. Inserts have their own contract:

- Non-null columns without defaults are required.
- Nullable columns without defaults can be omitted and are inserted as SQL NULL.
- Identity and defaulted columns use `Change<T>`: omission keeps the default;
  `.set(value)` explicitly supplies a value.
- Computed columns are absent from generated inserts and patches.

All patch parameters use `Change<T>`. Omission leaves a column unchanged;
`.set(null)` clears a nullable column. Projections remain independent of full rows.
Relations load only through explicit selections; rows have no implicit lazy queries,
equality generation, serialization, `copyWith` or global identity map.

## Column types and defaults

| Declaration | Dart value |
| --- | --- |
| `identity()`, `integer()` | `int` |
| `text()`, `boolean()`, `real()` | `String`, `bool`, `double` |
| `bigInteger()`, `decimal()` | `BigInt`, `Decimal` |
| `dateTime()` | `DateTime` UTC instant |
| `date()`, `time()`, `localDateTime()` | `LocalDate`, `LocalTime`, `LocalDateTime` |
| `bytes()`, `json()` | `Uint8List`, `SqlJson` |
| `enumeration(Status.values)` | `Status` |
| `custom(emailCodec)` | The public const codec's domain type |

Append `.nullable()` for SQL NULL. `json()` retains the distinction between a JSON
null document and SQL NULL. An integer-storage domain ID can use
`custom(PersonId.codec).identity()`; it must remain a single non-null primary key.

`name: 'existing_column'` fixes a physical column name; otherwise the generator
uses snake_case. `integer(bits: 32)`, `decimal(precision: 10, scale: 2)` and temporal
`precision: 3` declare storage limits; each migration engine checks its capabilities.

`defaultValue` on integer, text, boolean, real and enum columns declares a typed
SQL constant. Text is escaped as a literal. Enum constants are encoded using the
same labels as their column codec. For stable labels independent of Dart renames:

```dart
status: enumeration(
  Status.values,
  labels: {Status.pending: 'waiting', Status.done: 'complete'},
  defaultValue: Status.pending,
),
```

Every enum constant needs a distinct label. Use the full enum constant name in the
generic default argument; dot shorthand has no suitable context there.
Enum labels are application codecs over text storage. Changing those labels needs
an explicit data migration; schema diffing does not infer a label rename.

`defaultSql: 'CURRENT_TIMESTAMP'` is trusted database SQL. `clientDefault:
DateTime.now` is a public function or constructor tear-off, invoked only when an
insert omits the value. It may coexist with a database default: omission uses
the client factory, while `.defaultValue()` requests the database default.
Choose either `defaultValue` or `defaultSql` for the database default. Generation
never executes a factory or codec. Use `.computed('price * quantity')` for a read-only
computed column; it accepts explicit dialect overrides and `storage:`. Add trusted
checks inside the model with `checks: [check('price >= 0', name: 'positive_price')]`.

## Keys and relationships

`identity()` declares a database-generated primary key. Other primary keys use
`primaryKey: (m) => m.code` or an ordered composite tuple:

```dart
primaryKey: (m) => (m.projectId, m.employeeId),
uniqueKeys: (m) => [(m.departmentId, m.email)],
```

Relationships are named members of the Record returned by `relations`. A forward
reference declares a database foreign key and a query member on the current model.
A reverse member is declared on the model that exposes it:

```dart
final Model employee = model(
  'employees',
  (id: identity(), name: text(), managerId: integer().nullable()),
  relations: (e) => (
    manager: references(e.managerId, () => employee, onDelete: .setNull),
    reports: referencedBy(() => employee),
  ),
);
```

`manager` and `reports` are generated query members, not string options or stored
row fields. `references` defaults to the target's primary key and deletion action
`restrict`; `cascade` and `setNull` are explicit. Reverse navigation reuses a
forward reference and creates neither another foreign key nor an implicit index.
Renaming either relation changes the query API without changing the physical
schema. A unique foreign key expresses a one-to-one constraint. Many-to-many
associations use an explicit model, which can also hold business fields.

`referencedBy(() => model)` requires exactly one forward reference from that model
to the current one. If several exist, choose the foreign-key mapping explicitly:

```dart
// On user, when post has both authorId and reviewerId references to user:
relations: (u) => (
  authoredPosts: referencedBy(() => post, on: (authorId: u.id)),
  reviewedPosts: referencedBy(() => post, on: (reviewerId: u.id)),
),
```

No match or ambiguity is a generation error. The generator never guesses from a
relation name or chooses the first candidate. Reverse declarations work across
files, regardless of declaration order. Their mapping references fields, so a
forward relation's query name can change independently.

For composite primary keys, a positional Record retains target primary-key order:

```dart
relations: (m) => (
  team: references((m.tenantId, m.teamCode), () => team),
),
```

A named Record instead maps **target Dart field names to local columns**. This
selects an alternate unique key or spells out a composite mapping without strings:

```dart
relations: (m) => (
  team: references((tenantId: m.tenantId, code: m.teamCode), () => team),
  owner: references((email: m.ownerEmail), () => user),
),
```

Named mappings are normalized to the declared target key order; reordering their
entries does not change a foreign key. Target fields must form a primary or unique
key. `constraint: false` on `references` allows read-only navigation without a
database foreign key, including to non-unique fields; its reverse is read-only too.

**Typing boundary:** `m.teamCode` and `u.id` have native Dart types and completion.
Target mapping names (`code`, `authorId`) are checked against the referenced model
by generation, not Dart member completion. No `dynamic` selector or generated input
library is used. Invalid names, incompatible value types/codecs, repeated columns,
invalid target uniqueness and unmatched inverse mappings fail before emission.
The `relations` callback must return a literal named Record containing direct
`references`/`referencedBy` calls; it is read statically and never executed.

## Split schemas and static boundaries

Use ordinary independent Dart libraries. A schema root can export selected models:

```dart
export 'employees.dart' show employee;
export 'projects.dart' show project, projectMember;
```

Generation includes the root's local models and exported models, then follows
model references transitively. Local models retain declaration order; external
models are ordered by physical table name so renaming exported Dart variables
does not change the snapshot fingerprint. Unrelated imports and other unexported
models are not additional roots. Imported enum/domain types retain their defining library;
unambiguous public types are reexported by the generated client. For colliding
domain names, import the original libraries with prefixes.

Declarations are static source, not executable configuration scripts. Model and
column helper calls must be direct. Key callbacks are arrow expressions selecting
local fields; relation members are a named Record and other constraint collections
are literal lists, without control flow or
spreads. String/bool/numeric configuration accepts literals and const references.
Factories, mutation-based registration and dynamic schema assembly are not run.
Unsupported discovered declarations fail with a source diagnostic rather than
silently disappearing. Schema-specific checks run during generation. Keep
build_runner watch active to catch those errors while editing.

Keep physical names fixed during Dart refactoring. Regenerate and analyze consumers
after changing declarations. Generated model/field renames do not promise automatic
IDE edits across every generated API. Migration snapshots contain physical metadata,
without application imports, and destructive renames are never inferred.

## Updating an existing schema

Use `model(...)` for every table and move column settings into the column helpers.
Generate the new clients and update application imports to use their row classes.
Keep physical table and column names fixed, then compare the generated snapshots
before creating a migration. Saved migration definitions remain independent of
current schema declarations and must not be regenerated.
