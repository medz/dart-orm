# Contributing

Use Dart 3.13 stable. The product is one package with seven independent modules.

| Entrypoint | Implementation responsibility |
| --- | --- |
| `lib/database.dart` | Sessions, driver contracts, ownership and transactions |
| `lib/schema.dart` | Model annotations and physical metadata |
| `lib/query.dart` | Parameterized filters, scope checks and decoding |
| `lib/sqlite.dart` | Native SQLite connection and configuration |
| `lib/postgres.dart` | Native PostgreSQL pool and configuration |
| `lib/migration.dart` | Frozen Dart history, planning and application |
| `lib/dev.dart` | Static analyzer and generated source emission |

Keep implementation in `lib/src/<module>/`. Same-module imports are relative;
cross-module imports must use `package:orm/<module>.dart`. Public entrypoints use
explicit exports from their own implementation. Never use `part` or `part of`.
Runtime modules cannot depend on `dev`; no aggregate entrypoint hides ownership.
`test/module_boundaries_test.dart` enforces these rules and rejects module cycles.

## Local checks

```sh
dart pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed bin lib test example/*.dart example/migrations
dart analyze
dart run bin/orm.dart generate --schema example/models.dart --out example/models.db.dart --name AppDatabase --engine sqlite --check
dart test --concurrency=1
dart run example/main.dart
```

SQLite tests run against native SQLite. PostgreSQL tests skip unless configured.
Use a disposable PostgreSQL instance and an account allowed to create/drop
schemas. Fixtures own their isolated schemas and remove them after each test.

```sh
ORM_TEST_POSTGRES_HOST=127.0.0.1 \
ORM_TEST_POSTGRES_PORT=5432 \
ORM_TEST_POSTGRES_USER=orm \
ORM_TEST_POSTGRES_PASSWORD=orm \
ORM_TEST_POSTGRES_DATABASE=orm_test \
dart test --concurrency=1
```

For a local Unix socket, replace HOST with `ORM_TEST_POSTGRES_SOCKET`; the driver
tests accept its directory or full `.s.PGSQL.<port>` path. Query/business fixtures
and migration fixtures use the full socket path. Test TLS is explicitly disabled
for the local service; application PostgreSQL configuration is independent.
CI supplies PostgreSQL and exercises the entire suite without database skips.

Test meaningful behavior against real engines: mutation return rows, parameter
binding, rollback, callback lifetimes, guarded updates, concurrent requests and
catalog drift. Static type tests need a valid positive consumer before deliberate
invalid calls. Do not count syntax errors or an obsolete generated API as type
safety evidence. Keep tests small and reuse passing evidence unless new changes
or unresolved failures justify more work.

## Documentation and publication

Document public behavior, ownership and failure boundaries with Dartdoc.
Keep `doc/` for public usage and compatibility limits. Research and test-run logs
belong outside public documentation. Contributor workflows belong here.

Review saved migration SQL and freeze a standalone Dart snapshot before saving
its literal fingerprint. Use static registration. Never revise deployed history
or add compatibility with the retired JSON snapshot workflow during beta.

Before a release, also run `dart doc --validate-links` and
`dart pub publish --dry-run`; generated API pages stay under ignored `doc/api/`.
Check the package archive for local caches, credentials and unrelated artifacts.
Use small Conventional Commits. Pushing needs explicit authorization.
