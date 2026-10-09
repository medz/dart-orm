# Dart ORM

Plain Dart models, generated typed tables and explicit database sessions.

**6.0.0-beta.11** requires Dart 3.13. Native SQLite and PostgreSQL 18 are verified
on macOS and Linux. From beta.10, update the dependency and regenerate clients to
use `count()`. Existing generated methods remain usable; reviewed migration
definitions and fingerprints stay unchanged. PostgreSQL now requires native
`postgres` 3.5.20 or newer for cancellation and deadline fixes.

Count returns one integer without loading model rows and respects the query's
limit and offset. Count an unpaged filter scope for the total, then reuse it for
the selected page in one read-only transaction. The shop's `searchUsers` example
now returns `(users: ..., total: ...)`; code copied from it reads `.users` and
`.total`. PostgreSQL preserves the original SQL failure when rollback also fails.

From beta.8, regenerate clients to use `whereAny`; keep reviewed migration
definitions and fingerprints unchanged.

Beta.8 introduced a breaking rewrite. When upgrading from beta.7 or earlier,
migrate model declarations and application APIs, then regenerate clients. Earlier
clients and migration definitions have no compatibility layer; existing databases
require a separately reviewed baseline.

```sh
dart pub add orm:6.0.0-beta.11
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
