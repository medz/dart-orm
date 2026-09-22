# Database schemas and definition files

Keep model declarations unchanged when splitting a schema. PostgreSQL uses the
first directory name as the database schema. MySQL, MariaDB and SQLite use a flat
directory of definition files for one configured database.

| Source | PostgreSQL | MySQL, MariaDB, SQLite |
| --- | --- | --- |
| `lib/schema.dart` | Default `public` schema | Configured database |
| `lib/schema/{schema}/*.dart` | Named database schema | Not a declaration layout |
| `lib/schema/*.dart` | Use a schema subdirectory | Split model declarations |

Neither directory pattern is recursive. Imported enums, codecs and default
factories can live elsewhere. In directory mode, referenced models must be
declared in the selected layout; an import or export cannot change their schema.
Generated `.orm.dart` and `.snapshot.dart` files are not declaration inputs.

## PostgreSQL

```text
lib/schema/
  public/
    profiles.dart
  auth/
    users.dart
    sessions.dart
```

`lib/schema/auth/users.dart`:

```dart
import 'package:orm/schema.dart';

final user = model('Users', (
  id: identity(),
  displayName: text(name: 'DisplayName'),
));
```

`lib/schema/public/profiles.dart`:

```dart
import 'package:orm/schema.dart';
import '../auth/users.dart' as auth;

final profile = model('profiles', (
  id: identity(),
  accountId: integer(),
), relations: (p) => (
  account: references(p.accountId, () => auth.user),
));
```

Generate offline using the project configuration, or select the engine explicitly:

```sh
dart run orm generate lib/schema --database postgres
```

The client and snapshot are `lib/schema.orm.dart` and `lib/schema.snapshot.dart`.
Only default `public` models produce flat access such as `db.user`. Declaring a
non-default schema groups all model access by schema:

```dart
final account = await db.auth.user.create(displayName: 'Alice');
await db.public.profile.create(accountId: account.id);
```

Grouped row types include their schema, such as `AuthUser` and `PublicProfile`.
Different schemas may declare the same model and table names. Names must remain
distinct within their schema. Schema directory names must also be usable as Dart
database members; invalid names and generated type collisions are reported.
Case-sensitive database names cannot always be represented on a case-insensitive
source filesystem; the generator does not silently rename or merge them.

Relationships use the target declaration's schema. Cross-schema foreign keys and
queries use the same PostgreSQL database and connection; they do not open another
database or introduce distributed transactions.

## Single files and generation roots

`lib/schema`, `lib/schema/` and `lib/schema.dart` select the same definition root.
If both the file and directory exist, generation combines their declarations.
The sibling file contributes to the default schema. Exporting a declaration that
was already discovered does not duplicate it; independent conflicting models
produce an error instead of overriding one another.

Select the engine through `OrmConfig.history.dialect` or `--database`. Directory
generation requires an engine and never connects to discover it. Single-file
programmatic generation without an engine retains engine-neutral metadata; select
PostgreSQL explicitly when generating its physical namespaces.

With an engine selected, table ordering is deterministic. Splitting declarations
or renaming a file within one schema does not change the physical snapshot.
Moving a model to another schema changes its database identity and requires a
reviewed migration. Existing migration definitions and fingerprints stay frozen.

When upgrading older PostgreSQL snapshots, unqualified tables match same-named
`public` tables during diffing. Adding explicit qualification alone does not
recreate tables, move data or rewrite historical files. This default-schema
transition does not infer a custom `search_path`: projects that previously used
another schema must record its explicit physical namespace in a new reviewed
migration snapshot before adopting directory generation.

## SQL names and migration ownership

The schema, table and column names are separate identifiers. The example above
queries `"auth"."Users"` and `"DisplayName"`. PostgreSQL generation also explicitly
qualifies default models with `"public"`. Querying these tables does not depend
on a later `SET search_path` or an identically named temporary table.

Do not write `model('auth.Users', ...)`: dotted table names are rejected. Column
names use snake_case unless their helper specifies `name:`. Explicit physical
names retain their spelling and quotes are escaped for the selected dialect;
quoting does not change the database's own rules for case equality.

Generated PostgreSQL creation plans include the required `CREATE SCHEMA IF NOT
EXISTS` statements. Review these through the normal migration workflow and use a
role with the required privileges. Removing models never automatically drops a
schema or runs `DROP SCHEMA ... CASCADE`. Explicit table moves can use
`SchemaRenames.tables` with the before/after identities, for example
`{'auth.Users': 'archive.Users'}`; these keys match snapshot identities and are
not interpreted as arbitrary SQL.

Migration locks cover one PostgreSQL database, including work spanning several
schemas. Catalog verification, foreign keys, query inspection, cursors and change
subscriptions distinguish schema-qualified tables. Namespace getters do not grant
database permissions. Raw SQL remains trusted application SQL and follows its
own explicit names and session state.

MySQL/MariaDB cross-database models and SQLite attached-database models are outside
this layout feature. Their definition files continue to describe one database.
