# Annotated Dart models

Annotated models let queries return your ordinary Dart objects, including their
business methods. Use Dart 3.13 or newer. Import `package:orm/schema.dart` for the annotation API. Old Record model
declarations are no longer supported; migrate their fields and physical names
to annotated classes, then regenerate clients.

## Start without generated files

```dart
// orm.config.dart
import 'package:orm/config.dart';

void main() {
  defineConfig(
    database: .sqlite,
    models: 'lib/models.dart',
    output: 'lib/models.orm.dart',
    migrations: 'migrations',
  );
}
```

```dart
// lib/models.dart
import 'package:orm/schema.dart';

@Model()
final class User({
  @Id(generated: true) required final int id,
  @Unique() required final String email,
  final String? nickname = 'guest',
  @DatabaseDefault(true) final bool active = false,
}) {
  String displayLabel() => nickname ?? email;
}
```

Run `dart run orm generate`. Neither the configuration nor the model source
imports generated files, so the first generation has no bootstrap dependency.
The command writes a typed client and an independent `.snapshot.dart` physical
schema. It does not connect to a database or apply migrations.

`defineConfig` returns `void` and registers configuration when loaded by the
package CLI. Use `dart run orm generate --config path/to/orm.config.dart` for
another configuration. `--config` is relative to the calling directory; the
`models`, `output` and `migrations` strings are relative to the configuration's
directory. A models directory is searched recursively, excluding `.orm.dart` and
`.snapshot.dart` outputs. A sibling Dart file can export shared model classes.

The same configuration supports migration commands through `connect`, with
static history loaded from the configured migrations directory only when needed.
A missing registry alongside migration files is an error, never an empty history.
Production AOT executables use the independent `runMigrationCli` API and frozen
history. See [Migrations](migrations.md).

## Typed results and presence

Import your generated client using your application's package name:

```dart
import 'package:my_app/models.orm.dart';

final User user = await db.user.create(email: 'a@example.com');
print(user.displayLabel());

await db.user.byId(user.id).patch(nickname: .set(null));
final User updated = await db.user.byId(user.id).single();
await db.user.byId(user.id).delete().execute();
```

The generated client imports and reexports the original DTO. It never emits a
replacement `User` class. Every normal read selects and decodes every mapped
scalar field, including actual database nulls, then passes all those values to
the constructor. Business methods and derived getters remain available.

Required creation fields take their declared type directly. Generated fields and
fields with defaults use `Change<T>` to distinguish omission from an explicit
value. Use `.set(value)` to provide one, including `.set(null)` for a nullable
field; `.keep()` is the default omission marker. For example:

```dart
final user = await db.user.create(
  email: 'b@example.com',
  nickname: .set(null),
  active: .set(false),
);
```

Patches use the same presence representation. Omitted fields remain unchanged;
patches never apply insert defaults. Generated identities are excluded from the
patch signature. An entirely empty patch retains the existing `MUTATION.EMPTY`
diagnostic. Nonnullable fields reject null statically.

For omitted creation values the order is:

1. An explicit `@ClientDefault` factory
2. An explicit `@DatabaseDefault` or generated identity
3. A constant constructor default
4. SQL null for a nullable field
5. Otherwise the creation argument is required

A constructor default only supplies a client fallback. It never adds SQL
`DEFAULT`. In the example, direct `User(...)` construction defaults `active` to
false; an omitted create value lets the database supply true. Explicit false is
preserved. Reads always use actual database values rather than constructor
fallbacks.

`@ClientDefault(DateTime.now)` references a public synchronous function, static
method or constructor tear-off with no required arguments. Generation does not
execute it. Each generated create call prepares a new insert and obtains its
own omitted client defaults; re-executing an already prepared low-level mutation
retains that mutation's values. Generated factory references preserve the public
import/export entrypoint used by the annotation, including conditional imports
and indirect exports. A public factory declared alongside a conditional mixin
is selected through the model's mixin import; expose the factory through that
entrypoint when using `show`/`hide`. Each platform must provide the same public
symbol and a compatible zero-required-argument signature. Target compilation
checks that signature; generation never substitutes a host implementation to
bypass a missing or incompatible platform symbol. A fixed-library wrapper whose
body delegates to conditional code remains a compatible alternative. Local
private typedef qualifiers are expanded along their alias chain to the first
public type while retaining its import route and constructor type arguments.
Public aliases keep their own entrypoint. For external factories used by a
conditional mixin, expose the symbol through the mixin entrypoint or use the
same factory expression and public import route in every branch. Generation
checks those routes before retaining a shared fixed-library wrapper. A private
alias inside a conditional mixin needs its first public target exposed through
that mixin entrypoint and a consistent alias mapping across branches. Missing
or ambiguous routes and unresolved alias arguments produce a located
`SCHEMA.DEFAULT` diagnostic instead of fixing the factory to the host branch.
Explicit generic arguments, including nested named/record types and local
private typedef chains to named types, retain their own public import/export
routes as well as the factory route. Different import prefixes and field
declaration grouping between mixin branches do not change this contract.
Inactive package branches are resolved through the consumer package config.
An inferred argument without a provable conditional public route must be
spelled explicitly; generation reports `SCHEMA.DEFAULT` instead of importing
the host implementation. Branches must keep the same factory expression and
private alias mapping after import-prefix normalization; generation does not
prove arbitrary semantically equivalent rewrites.

`@DatabaseDefault.sql('CURRENT_TIMESTAMP')` uses
trusted SQL. Scalar database constants are encoded and quoted by generation. For a custom
codec, use `@DatabaseDefault.sql` with an already encoded database expression;
generation never executes an application encoder to infer a default.

Constructor defaults support scalar and enum constants, including imported
constants, and recursively expressible constant collections with a suitable
codec. Constant collections remain immutable, shareable Dart constants. Values
that cannot be emitted in an independent library produce a diagnostic; use a
public client-default factory rather than relying on arbitrary source copying.

## Mapping boundaries

Use a public, concrete, nongeneric class with an unnamed generative constructor
and named field parameters (`final T name` or `this.name`). Persistent values
must directly initialize their same-name fields. Fields cannot be late. Mutable
or final model fields are supported; generated reads still construct a complete
object. Classes directly extend Object; superclass storage and constructor effects
are not supported. Transforming initializers and executable constructor bodies
are rejected, except for the direct optional mixin assignments described below.

Static fields, methods and derived getters are not columns. `@Ignore()` excludes
nonpersistent fields; ignored constructor parameters must be optional. A stored
instance field that the constructor cannot supply is rejected instead of silently
omitted. A model source must not depend on its generated client.

## Optional shared fields and methods

Ordinary models do not need a mixin. When several DTOs share storage and business
methods, a plain, nongeneric mixin can declare the fields and their annotations
once. Each DTO keeps its own named constructor and original class identity:

```dart
mixin SharedFields {
  @Id(generated: true)
  int id = 0;
  @DatabaseDefault(true)
  bool active = false;
  String describe() => '$id: $active';
}

@Model()
final class Memo with SharedFields {
  final String title;
  Memo({required int id, required this.title, bool active = false}) {
    this.id = id;
    this.active = active;
  }
}
```

Generated create/read/relation results are the original `Memo`, including
`SharedFields.describe()`. Field annotations on the mixin apply independently
to each model; class-level keys, indexes and relations remain on the model.
Imported mixin libraries and relation targets are resolved statically, without
executing application factories or constructors. Like model libraries, a library
owning an applied mixin cannot contain `part` or `part of` directives.

Persistent mixin fields must be mutable, non-late storage with constant
initializers or implicit null. Every field needs a same-name, exactly same-type
named constructor parameter, including nullability, and exactly one
`this.field = field` statement. No casts, calculations, extra statements or
parameter renaming are accepted. The stored values supplied to reads therefore
remain unchanged. Ordinary model fields still use `this.field` or primary
constructor field parameters. `@Ignore()` can exclude mixin-only business state.

Mixin initializers (`id = 0`, `active = false`) are construction placeholders;
they never provide generated insert defaults. Constructor parameter constants
provide client fallbacks under the same precedence rules as ordinary models.
In the example, the generated identity and database `true` default beat the
constructor values; an explicit `active: .set(false)` still wins.

Generation rejects fields/accessors shared under the same name by multiple
mixins or redeclared by the model. Repeating a mapping annotation on both the
mixin field and constructor parameter is an error, not an override. Final or
late persistent mixin storage, generic mixins, mixin classes, superclass storage,
and mixins with superclass constraints other than Object are outside this
supported mapping. Derived getters and methods remain ordinary Dart members.
See the complete [shared-field example](https://github.com/medz/dart-orm/blob/main/example/annotated/mixins.dart).

## Scalar storage

Scalar Dart types select the existing codecs: `int`, `String`, `bool`, `double`,
`BigInt`, `DateTime`, `Uint8List`, `Decimal`, `LocalDate`, `LocalTime`,
`LocalDateTime`, `SqlJson`, and enum values. Nullable types are the sole nullability
marker. `@Column(codec: publicConstCodec)` supports domain values;
`@Column(name: 'physical_name')` overrides the default snake_case column name.
The physical table defaults to the exact class name. Use `@Model(table: 'users')`
for an explicit override; table names are never automatically pluralized.

## Keys and explicit relations

```dart
@Model(table: 'posts')
@Index(['authorId', 'title'], name: 'posts_author_title')
final class Post({
  @Id(generated: true) required final int id,
  @Relation(
    target: User,
    name: 'author',
    key: 'id',
    inverse: 'posts',
    onDelete: .cascade,
  )
  required final int authorId,
  required final String title,
});
```

The relation creates typed query navigation and one foreign key. The optional
inverse creates reverse navigation, without another foreign key. `User` does not
receive a posts field or an unloaded placeholder. Load relations explicitly:

```dart
final List<Post> posts = await db.user.byId(user.id)
    .select((u) => u.posts.many()).single();
final User author = await db.post.byId(post.id)
    .select((p) => p.author.required()).single();
```

Use multiple nongenerated `@Id()` fields for a composite primary key, in
constructor order. Class-level `@Unique(['tenant', 'email'])` declares a composite
unique key. Class-level `@Relation(fields: ['tenant', 'authorId'],
keys: ['tenant', 'id'], target: User, name: 'author')` pairs fields in order.
`key` and `keys` are mutually exclusive; omitting them uses the target primary
key. Names refer to Dart scalar fields and are checked during generation, rather
than being analyzer-bound field references. The generator checks existence,
arity, order, value type, storage, codec, target uniqueness, duplicate navigation,
and deletion nullability. `constraint: false` retains read-only navigation without
a physical foreign key. Existing engine capability checks still apply.

## PostgreSQL identity

For annotated models, source folders never define a namespace. Use
`defaultNamespace: 'application'` in configuration and
`@Model(namespace: 'auth')` for an override. The fallback is `public` on PostgreSQL.
The resolved namespace is frozen into the client, snapshot and foreign-key
identities. Namespace spelling does not rename the DTO or group its Dart getters.
Other engines reject explicit namespaces.

Moving a source file preserves physical identity. Changing an inherited default
namespace changes physical identity and requires reviewed migrations. The
connection's `PostgresOptions.schema` still controls its search path; it is not a
model-default setting and is not changed by generation. Existing frozen migration
snapshots remain unchanged. Record source declarations must be migrated with explicit
namespace annotations; their old folder location no longer selects a namespace.

The runnable [annotated example](../example/annotated/main.dart) includes
configuration, ordinary models, generated artifacts and a SQLite demonstration.
