# Dart ORM

Plain Dart models, generated typed tables and explicit database sessions.

**6.0.0-beta.12** requires Dart 3.13. Native SQLite and PostgreSQL 18 are verified
on macOS and Linux. From beta.11, update the dependency; generated clients and
reviewed migration definitions and fingerprints stay unchanged.

PostgreSQL typed reads and mutations address their physical table, excluding
inherited rows. Migration verification rejects disabled or replica-only
foreign-key checks, unsafe replication settings, partitions and inheritance
links. Review unsupported topology and enforcement drift before resuming a
history; see [migration limits](https://github.com/medz/dart-orm/blob/main/doc/migrations.md).

Native exceptions and error-code constants are available through the public
PostgreSQL and SQLite modules. Catch failures outside the transaction; native
errors retain their types and metadata without remapping or automatic retries.

From beta.10, regenerate clients to expose `count()`. Code copied from the
`searchUsers` example reads its returned `.users` and `.total` fields.

From beta.8, regenerate clients to use `whereAny`; keep reviewed migration
definitions and fingerprints unchanged.

Beta.8 introduced a breaking rewrite. When upgrading from beta.7 or earlier,
migrate model declarations and application APIs, then regenerate clients. Earlier
clients and migration definitions have no compatibility layer; existing databases
require a separately reviewed baseline.

```sh
dart pub add orm:6.0.0-beta.12
```

```dart
import 'package:orm/query.dart';
import 'package:orm/sqlite.dart';
import 'package:orm/migration.dart';

import 'migrations/sqlite/history.dart' as migrations;
import 'models.dart';
import 'models.db.dart';

final db = AppDatabase(SqliteDriver.memory());
await MigrationRunner(db.database, migrations.history).apply();
final user = await db.users.create(username: 'seven', age: 28);
await db.users.update(user.id, nickname: 'Seven');
await db.users.update(user.id, nickname: null);

final cards = await db.users
    .where(active: eq(true), age: gte(18))
    .whereAny(username: startsWith('sev'), nickname: startsWith('sev'))
    .orderBy(id: asc)
    .limit(20)
    .select<UserCard>();
print(cards.first.username);

await db.transaction((tx) async {
  await tx.users.update(user.id, active: false);
});
await db.close();
```

`create` returns the inserted model. `update` returns the updated model or null
when the key and filters do not match. Omitted fields remain unchanged; explicit
null clears nullable fields. Selections are registered named records with direct
field access. Values are bound and identifiers are quoted.

From a repository checkout, run the complete example, including schema
installation, typed reads, relationship loading and an idempotent order
transaction:

```sh
dart pub get
dart run bin/orm.dart generate --schema example/models.dart --out example/models.db.dart --name AppDatabase --engine sqlite --check
dart run example/main.dart
```

- [Models and generated queries](https://github.com/medz/dart-orm/blob/main/doc/README.md)
- [Reviewed Dart migrations](https://github.com/medz/dart-orm/blob/main/doc/migrations.md)
- [Complete order workflow](https://github.com/medz/dart-orm/blob/main/example/shop.dart)
- [Contributor checks and module boundaries](https://github.com/medz/dart-orm/blob/main/CONTRIBUTING.md)

Each module has its own public import: `schema.dart`, `query.dart`,
`database.dart`, `sqlite.dart`, `postgres.dart`, `migration.dart` and `dev.dart`.
Implementation stays in `lib/src/<module>/`; modules depend on one another only
through those public entrypoints. All libraries are independent Dart files.
