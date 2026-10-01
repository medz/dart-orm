# Database namespaces and model sources

A source path selects Dart files. A physical namespace selects PostgreSQL tables.
They are independent: moving a model into a different directory never changes its
namespace, DTO class or generated database member.

A model root can be `lib/models.dart` or the recursively discovered
`lib/models/` directory. If both exist, generation combines them. Generated
`.orm.dart` and `.snapshot.dart` files are excluded. Ordinary Dart exports and
relation targets can contribute models from other libraries.

## PostgreSQL namespace resolution

Resolve each model's namespace in this order:

1. `@Model(namespace: 'auth')`
2. `defaultNamespace` from project configuration or programmatic generation
3. `public` when PostgreSQL is selected

`orm.config.dart` can configure an offline generation target:

```dart
import 'package:orm/config.dart';

void main() {
  defineConfig(
    database: .postgres,
    models: 'lib/models',
    defaultNamespace: 'app',
  );
}
```

Add the explicit connection factory described in the [CLI guide](https://github.com/medz/dart-orm/blob/main/doc/cli.md)
for database commands. Configuration paths are plain strings, relative to the
configuration file. No generated client or migration registry is imported here.

An explicit model namespace overrides that default:

```dart
import 'package:orm/schema.dart';

@Model(table: 'Users', namespace: 'auth')
final class User({
  @Id(generated: true) required final int id,
  @Column(name: 'DisplayName') required final String displayName,
});

@Model(table: 'profiles')
final class Profile({
  @Id(generated: true) required final int id,
  @Relation(target: User, name: 'account', inverse: 'profiles')
  required final int accountId,
});
```

With this configuration, `User` maps to `auth.Users` and `Profile` to
`app.profiles`. Queries retain flat members and return the original DTOs:

```dart
final User account = await db.user.create(displayName: 'Alice');
await db.profile.create(accountId: account.id);
```

Different namespaces may contain identically named physical tables. Use distinct
Dart class names for their generated APIs and explicit `table:` overrides where
needed. Namespace spelling need not be a Dart identifier and is unrelated to the
case sensitivity of the source filesystem.

Relationships use the target model's resolved namespace. Cross-schema foreign
keys and queries run in the same PostgreSQL database and connection; they do not
create distributed transactions.

## Generation and refactoring

Generate through the configuration, or choose an engine explicitly:

```sh
dart run orm generate lib/models --database postgres
```

The default output paths are `lib/models.orm.dart` and
`lib/models.snapshot.dart`. Directory generation requires an engine and never
connects to discover it. Single-file programmatic generation without an engine
retains engine-neutral metadata; explicitly select PostgreSQL to resolve its
default namespace.

Table ordering is deterministic. Splitting files, exporting the same discovered
class or changing directory names does not duplicate models or change physical
identity. Conflicting independent declarations fail generation.

Changing `defaultNamespace` changes physical identity for models that inherit it;
explicit overrides keep their namespace. This is a real schema change requiring
a reviewed migration. Use explicit rename/move mappings when rows must survive.
Applied migrations and their fingerprints remain frozen; generation never
reinterprets historical unqualified metadata as `public`.

## SQL names and ownership

The schema, table and column are separate quoted identifiers. The example uses
`"auth"."Users"` and `"DisplayName"`. PostgreSQL generation also qualifies models
resolved to `public`. Generated queries do not select another table because of a
later `SET search_path` or an identically named temporary table.

Use `@Model(table: 'Users', namespace: 'auth')`, not a dotted table name.
Manual `TableSchema` metadata follows the same identifier rules: namespaces,
tables and foreign-key targets reject dots, empty strings and NUL characters.
Columns default to snake_case unless `@Column(name: ...)` overrides the name.
Explicit names retain their spelling; quoting does not change each database's
case-equality rules.

Creation plans include required `CREATE SCHEMA IF NOT EXISTS` statements.
Review them and use a role with the necessary privileges. Removing models never
automatically drops a namespace or runs `DROP SCHEMA ... CASCADE`. Explicit moves
can use `SchemaRenames.tables`, for example
`{'auth.Users': 'archive.Users'}`. These keys identify snapshot tables; they are
not arbitrary SQL expressions.

`PostgresOptions.schema` controls the connection search path for raw SQL and
unqualified historical metadata. It does not set model namespaces. The migration
ledger remains associated with the connection's current schema; changing a model
default does not relocate that ledger. Migration locks cover the whole PostgreSQL
database, including changes spanning multiple namespaces.

Catalog verification, foreign keys, query inspection, cursors and subscriptions
distinguish qualified physical identities. A namespace does not itself grant
permissions or provide tenant isolation. Raw SQL follows its explicit names and
session state.

SQLite, MySQL and MariaDB reject explicit model/default namespaces. Their model
sources describe one configured database; cross-database models and SQLite
attached-database models are outside this feature.
