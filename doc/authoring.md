# Models and typed queries

Declare an immutable Dart class once. The generated client returns instances of
that class, including from inserts and relationships. It does not generate a
second row type or convert the class into a Record.

```dart
import 'package:orm/schema.dart';

final class User({
  @Id.generated() required final int id,
  @Unique() required final String email,
  required final String? nickname,
  @Default.sql('false') required final bool active,
});

final class Post(
  @Id.generated() final int id,
  final int authorId,
  final String title,
);

final users = entity<User>(table: 'users');
final posts = entity<Post>(table: 'posts');
final author = posts
    .key((p) => p.authorId)
    .references(users.key((u) => u.id), inverse: 'posts', onDelete: .cascade);
```

Primary constructors require Dart 3.13. They declare fields and constructor
parameters together; they are ordinary Dart classes with ordinary nominal type
identity. See the [Dart language documentation](https://dart.dev/language/primary-constructors).

`entity<User>()` gives the table its own identity and physical name. Two tables
can use the same row class, and a self-join still has separate table occurrences.
Row identity does not determine SQL scope.

Generate with `dart run orm generate lib/schema.dart`, then import the generated
client and the chosen driver. [Generation](https://github.com/medz/dart-orm/blob/main/doc/generation.md) describes standalone
and build_runner workflows. New projects can start with `dart run orm init
--database sqlite`; after initialization, `dart run orm generate` reads the typed
project configuration.

```dart
final User user = await db.users.create(email: 'seven@example.com');
await db.users.byId(user.id).patch(nickname: .set('Seven'));
await db.users.byId(user.id).patch(nickname: .set(null));

final List<User> active = await db.users
    .where((u) => u.active.eq(true))
    .get();

final List<Post> posts = await db.users
    .byId(user.id)
    .select((u) => u.posts.many())
    .single();
```

The same field declarations determine constructor values, typed query fields,
create parameters, patch parameters, codecs and the physical schema. Application
code does not repeat column types in a table class or a generated row interface.
The generated client imports `sql.dart` and binds to `QueryContext`. It can be used
with an offline `SqlBuilder` as well as a connected ORM `Database`; the model
declaration itself only depends on the schema/value layer.

## Full rows, writes and projections

The model constructor represents a complete database row. Every constructor
parameter is required, including nullable columns and generated IDs. `User.id`
stays `int`: creating a user does not require weakening the stored row to `int?`.

The generated `create` method has its own insert contract:

- Ordinary non-null columns are required.
- Nullable columns without defaults can be omitted and are inserted as NULL.
- Generated values, SQL defaults and client defaults use `Change<T>` with
  `.keep()` as the default. `.set(value)` explicitly supplies a value.
- Computed columns are absent from writes.

Patch parameters use `Change<T>` to distinguish omission from explicit NULL.
`patch()` keeps an omitted field; `patch(nickname: .set(null))` clears it.
Generated identities and computed columns are absent from patch parameters.

Use `@Default.sql` for database defaults and `@ClientDefault(factory)` for Dart
insert defaults. Constructor defaults are rejected: they would otherwise suggest
an insert behavior that the database does not implement. Neither constructors nor
client factories run during generation. Client factories run when building the
insert; the model constructor runs when decoding the resulting row.

Selected shapes remain independent of complete models. Project a scalar, a typed
Record, or a separate application DTO:

```dart
final cards = await db.users.select((u) => (
  u.id,
  u.email,
  u.posts.take(3).select((p) => p.title).many(),
).map((id, email, posts) => (id: id, email: email, posts: posts))).get();
// List<({int id, String email, List<String> posts})>
```

Selecting two columns does not produce a partly populated `User`. Relationships
are explicit query selections; they do not add hidden lazy-loading properties or
queries to the row class. A foreign key remains a separate typed declaration,
including for composite keys and multiple edges to the same table.

## Supported declarations and errors

Generated entity classes must be public, final, non-generic classes declared in
the selected schema file. Their unnamed primary constructor accepts public,
explicitly typed `final` declaring parameters. Required positional parameters,
required named parameters, and a mixture of both are supported. A constant
primary constructor is also valid. Classes cannot have inheritance, mixins,
implemented interfaces or members in their body. Add application behavior with
Dart extensions; arbitrary constructor logic is outside the database decoder's
contract.

Annotations use the same validation for classes and Records. Built-in values,
enums and explicit `@UseCodec` domain values retain their resolved Dart types.
The generator checks codec compatibility without executing codecs. It rejects
ambiguous field names, duplicate physical columns, invalid generated identities,
nullable primary keys, computed-column/default conflicts, invalid selectors and
foreign keys without a matching target key.

Dart analysis rejects wrong create/patch value types, unknown query fields and
assignment of an unrelated model with the same fields. Generation rejects
unsupported declaration forms and database-schema conflicts. Database-specific
capabilities are checked when selecting the migration engine.

These are ordinary classes: the ORM does not generate equality, `copyWith`, JSON
serialization or a global identity map. Two separately read rows are separate
instances. Serialization remains application code, while column codecs control
database encoding. In particular, SQL NULL, an omitted insert value and a missing
JSON property are different concepts.

## Records and schema history

Named Record typedefs remain an explicit structural data form:

```dart
typedef Coordinate = ({@Id() int id, double x, double y});
final coordinates = entity<Coordinate>();
```

They share the same schema validation and query runtime. A Record typedef does
not create nominal identity; another typedef with the same shape is assignable.
Classes are the default for models and catalog-import drafts. Records are useful
for projections and fixed SQL result shapes.

Changing a row declaration from a Record to a class does not change its physical
schema. Snapshots and saved migrations contain standalone physical metadata,
without imports of current model classes, constructors, codecs or client-default
functions. A class field rename can retain the database column with
`@ColumnName('old_name')`; absent that explicit name, normal schema diff rules
apply and never infer a destructive rename.

Class fields support Dart's normal symbol navigation and rename tools.
Regenerate after edits and repair affected generated-API references; a model
rename does not promise that an IDE will edit the regenerated client or all its
consumers automatically.
