# Define your models

Use ordinary Dart classes with annotations from `package:orm/schema.dart`.
Generation adds typed queries and an independent physical snapshot. Full reads
return the original class, so application methods and interfaces stay yours.

```dart
import 'package:orm/schema.dart';

@Model(table: 'users')
final class User({
  @Id(generated: true) required final int id,
  @Unique() required final String email,
  required final String? nickname,
  @DatabaseDefault(true) required final bool active,
});

@Model(table: 'posts')
@Index(['authorId', 'createdAt', 'id'], name: 'posts_author_timeline')
final class Post({
  @Id(generated: true) required final int id,
  @Relation(target: User, name: 'author', inverse: 'posts', onDelete: .cascade)
  required final int authorId,
  required final String title,
  @ClientDefault(DateTime.now) required final DateTime createdAt,
});
```

Dart 3.13 primary constructors, shown above, and ordinary field declarations with
an unnamed named-parameter constructor are supported. Annotate the field or its
constructor parameter. Every persistent parameter must directly initialize its
matching field. Models must be public, concrete and non-generic.

Run `dart run orm generate lib/models.dart`, or use
[build_runner watch](https://github.com/medz/dart-orm/blob/main/doc/generation.md).
This produces `models.orm.dart` with the query API and exports of the original
`User`/`Post` classes, plus an independent `models.snapshot.dart` for migrations.
The [company example](https://github.com/medz/dart-orm/blob/main/example/company/schema.dart)
includes self references and a many-to-many association with business fields.

`@Model()` uses the class name exactly as the table name: `User` maps to `User`.
There is no case conversion or pluralization for tables. `table: 'users'` is an
explicit override. The query member uses the lower-camel class name, such as
`db.user`. Physical namespaces never change that member or the DTO class.
Column names default to snake_case; `@Column(name: 'existing_column')` overrides it.

## Full reads, inserts and updates

```dart
final User created = await db.user.create(email: 'seven@example.com');
await db.user.byId(created.id).patch(nickname: .set('Seven'));
await db.user.byId(created.id).patch(nickname: .set(null));
final List<String> titles = await db.user.byId(created.id)
    .select((u) => u.posts.select((p) => p.title).many()).single();
```

Full reads supply every stored field to your constructor, including nullable,
generated and computed fields. A constructor default is not a partial-row marker.
Use explicit selections for partial results: scalars, typed Records or mapped DTOs.

Generated inserts have a separate contract:

- Non-null columns without defaults are required
- Nullable columns without defaults can be omitted and become SQL NULL
- Identities and defaulted fields use `Change<T>`: omission keeps the default;
  `.set(value)` explicitly supplies a value
- Computed columns are absent from generated inserts and patches

All patch parameters use `Change<T>`. Omission leaves a column unchanged;
`.set(null)` clears a nullable column. Relations load only through explicit
selections. No relation placeholders, lazy queries, equality, serialization or
`copyWith` methods are injected into your model.

Mark nonpersistent instance fields with `@Ignore()`. An ignored constructor
parameter must be optional; a database read cannot invent a required value for it.
Mixins, interfaces and ordinary methods remain normal Dart behavior. They do not
implicitly register additional persistent fields or relations.

## Scalar types and storage

| Dart field type | Inferred storage |
| --- | --- |
| `int`, `String`, `bool`, `double` | Integer, text, boolean, real |
| `BigInt`, `Decimal` | Exact integer, exact decimal |
| `DateTime` | UTC instant |
| `LocalDate`, `LocalTime`, `LocalDateTime` | Calendar values without a timezone |
| `Uint8List`, `SqlJson` | Bytes, JSON document |
| An enum | Text labels |
| A domain value with `@Column(codec: ...)` | The public const codec's storage |

Use nullable Dart types for SQL NULL. Import `dart:typed_data` for `Uint8List`.
`SqlJson?` distinguishes SQL NULL from a JSON null document. A custom codec can
supply storage for a domain type without changing the DTO's field type.

`@Column(bits: 32)`, `@Column(precision: 10, scale: 2)` and temporal
`@Column(precision: 3)` declare storage limits. Each engine validates capabilities.
See [types](https://github.com/medz/dart-orm/blob/main/doc/types.md).

For stable enum labels independent of Dart constant renames:

```dart
enum Status { pending, done }

@Model()
final class Job({
  @Id(generated: true) required final int id,
  @Column(labels: {Status.pending: 'waiting', Status.done: 'complete'})
  @DatabaseDefault(Status.pending)
  required final Status status,
});
```

Every enum constant needs a distinct label. Labels are codecs over text storage;
changing them needs an explicit data migration, not an inferred label rename.

## Defaults, computed columns and checks

`@DatabaseDefault(value)` declares a typed SQL constant, including nullable null.
`@DatabaseDefault.sql('CURRENT_TIMESTAMP')` declares trusted SQL. `@ClientDefault`
references a public synchronous factory, called only for omitted insert values.
It can coexist with a database default: omission uses the client factory;
`.defaultValue()` explicitly requests the database default.

A constant constructor default is a client-side fallback when no identity,
database default or explicit client factory takes precedence. It creates no SQL
DEFAULT and does not backfill historical rows. Generation never invokes your
constructor, factory or codec. See [defaults](https://github.com/medz/dart-orm/blob/main/doc/defaults.md).

`@Computed('price * quantity')` marks a read-only computed scalar.
`@Check('price >= 0', name: 'positive_price')` adds a class-level database check.
Both accept `sqlite`, `postgres`, `mysql` and `mariadb` SQL overrides; computed
columns also accept `storage: .stored` or `.virtual`, subject to engine support.

## Keys, indexes and relationships

`@Id()` marks a primary-key field. Multiple IDs form an ordered composite key in
constructor parameter order. `@Id(generated: true)` requires one non-null
integer-storage primary key. `@Unique()` marks a scalar; class-level
`@Unique(['departmentId', 'email'])` declares a composite key.
`@Index(['departmentId', 'id'], name: 'employees_department_id')` names an index.

A scalar `@Relation(target: User, name: 'author')` uses the annotated local field
and defaults to the target's primary key. Specify `key: 'email'` for an alternate
unique field. `inverse: 'posts'` adds reverse navigation to the target without
creating another foreign key or an implicit index.

Composite relations belong on the class. Ordered `fields` and `keys` lists pair
local and target Dart field names:

```dart
@Model()
@Relation(
  target: Team,
  name: 'team',
  fields: ['tenantId', 'teamCode'],
  keys: ['tenantId', 'code'],
  inverse: 'members',
)
final class Member({
  @Id() required final int id,
  required final int tenantId,
  required final String teamCode,
});
```

The target key must be primary or unique when `constraint` is true. Deletion
behavior defaults to `restrict`; choose `cascade`, `setNull`, `setDefault` or
`noAction` explicitly. `constraint: false` provides read-only navigation without
a foreign key, including navigation to non-unique fields. A unique foreign key
expresses a one-to-one constraint. Many-to-many associations use an explicit
model that can hold business fields.

Target classes are Dart symbols. Field lists and query names are string metadata:
the generator checks their existence, ordering, compatible types/codecs and
uniqueness before emission. They do not receive Dart member completion or automatic
analyzer symbol renames. Maintain these strings explicitly after a field rename,
then regenerate and analyze consumers. Preserve physical names with `@Column`
and `@Model` when refactoring only the Dart API.

## Source discovery and static boundaries

A model source can be a file or a recursively discovered directory. Folder names
never select a physical namespace. A sibling root file can also export models:

```dart
export 'employees.dart' show Employee;
export 'projects.dart' show Project, ProjectMember;
```

Generation includes root models and exports, then follows relation targets.
Unrelated imports are not additional roots. Generated `.orm.dart` and
`.snapshot.dart` files are excluded. Model sources must not import generated
clients; use independent libraries rather than `part` files. See
[namespaces](https://github.com/medz/dart-orm/blob/main/doc/namespaces.md).

Metadata is resolved statically. Unsupported declarations fail with a source
diagnostic; application constructors and factories are not executed to discover
models. Generated snapshots contain physical metadata without application
imports. Applied migration definitions stay frozen and destructive renames are
never inferred.
