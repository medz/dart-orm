# Project CLI

Start inside a Dart project with the `orm` dependency and Dart 3.13 or newer:

```sh
dart run orm init --database sqlite
dart run orm migrate create 0001_initial
# Review migrations/m0001_initial.dart before applying it.
dart run orm migrate apply
dart run orm migrate verify
```

`init` also accepts `postgres`, `mysql` and `mariadb`. It creates five files:

| File | Purpose |
| --- | --- |
| `lib/schema.dart` | Editable Record schema |
| `lib/schema.orm.dart` | Generated models and typed queries |
| `lib/schema.snapshot.dart` | Standalone physical schema |
| `migrations/migrations.g.dart` | Static imports and one fixed engine |
| `orm.config.dart` | Typed project configuration and executable entrypoint |

Initialization refuses an existing destination before writing anything. It never
connects to a database, creates a database file or applies DDL. The first client
and snapshot are generated before writing the config, so its static imports are
valid immediately. build_runner is optional for this workflow.

SQLite defaults to `app.sqlite`; edit its typed options in the config to change
the path. Server connections read `DATABASE_URL` only when connecting. Missing
credentials do not prevent initialization, generation or history validation.
TLS defaults to certificate verification. Connections use the independent driver
and `SqlDatabase` layers rather than importing model/query APIs.

## Typed configuration

The generated `orm.config.dart` is normal application-owned Dart:

```dart
import 'package:orm/cli.dart';
import 'package:orm/drivers/sqlite.dart';
import 'lib/schema.snapshot.dart' as target;
import 'migrations/migrations.g.dart';

Future<void> main(List<String> args) => runOrmCli(args, config: OrmConfig(
  schema: 'lib/schema.dart',
  migrations: 'migrations',
  history: migrationHistory,
  snapshot: target.schema,
  connect: ({required bool readOnly}) async => SqlDatabase(
    await SqliteDriver.open(readOnly
        ? const SqliteOptions.readOnly('app.sqlite')
        : const SqliteOptions.file('app.sqlite')),
  ),
));
```

The package command runs this explicit entrypoint in a child Dart process.
History is statically imported and checked; it is not discovered by executing
every Dart file in a directory. Run from the project root so relative schema,
history and connection paths are consistent. Use `--config other.config.dart`
for another explicitly selected entrypoint, or run
`dart run orm.config.dart migrate check` directly.

Config is trusted project source and should not perform I/O at the top level.
Place connection setup inside `connect`. Migration commands establish their own
transaction and locking behavior; `readOnly` lets a SQLite factory avoid creating
a file during inspection.

## Commands and side effects

| Command | Behavior |
| --- | --- |
| `generate` | Generate client and physical snapshot using the config |
| `migrate create <id>` | Regenerate the current schema, then save its diff as fixed Dart history |
| `migrate check` | Check compiled history and fingerprints without a connection |
| `migrate plan` | Read applied history and report pending operations |
| `migrate apply` | Apply pending operations explicitly |
| `migrate status` | Read migration history and recovery checkpoints |
| `migrate verify` | Compare the catalog with the generated snapshot |
| `migrate baseline` | Verify an existing schema and register its history |
| `migrate record <id>` | Record a reviewed edit to the latest unpublished migration |
| `migrate inspect <table>` | Read physical metadata for one table |

`create` always uses the current source, including edits since the last
`generate`. Other commands use the statically imported snapshot/history; they do
not silently regenerate or change deployment artifacts. Run `generate` before
checking a deliberately edited target with `verify`. New migrations never
overwrite existing files. Database changes happen through explicit `apply` or
`baseline`; initialization, generation and diff creation are offline.

An initial SQLite `plan` needs an existing file and fails without creating one.
The first `apply` can create that file. `create <id> --allow-destructive` permits
writing reviewed drop operations, not executing them. `apply
--max-backfill-batches <count>` bounds a resumable backfill invocation.

See [migrations](https://github.com/medz/dart-orm/blob/main/doc/migrations.md) for immutable history, engine boundaries, reviewed
renames/conversions, baseline and recovery behavior.

## Explicit tools

These commands also work without project configuration:

```sh
dart run orm generate lib/schema.dart lib/generated/database.dart --database sqlite
dart run orm generate lib/schema --database postgres
dart run orm migration registry migrations --dialect sqlite
dart run orm db inspect --sqlite app.sqlite --table tasks
dart run orm db import --sqlite app.sqlite --output lib/imported.dart
dart run orm queries generate lib/queries.dart
dart run orm queries check --source lib/queries.dart --sqlite app.sqlite
dart run orm web-assets web/orm
```

Server database flags are `--postgres-env NAME`, `--mysql-env NAME` and
`--mariadb-env NAME`. Choose exactly one database option. `--tls
verifyFull|require|disable` configures server TLS; `--database-schema` is specific
to PostgreSQL. Catalog import writes a Dart draft and a separate review report.
It does not migrate an existing database.

Generation uses the project configuration even when a schema path is supplied.
`--database` selects the engine without loading a configuration, which is useful
when recreating a deleted snapshot:
`dart run orm generate lib/schema --database postgres`. When an explicitly loaded
configuration and engine disagree, generation rejects the mismatch. Without a
configuration or path, the source defaults to `lib/schema.dart`.

Directory layouts require an engine. `lib/schema`, `lib/schema/` and
`lib/schema.dart` identify the same root and combine the file and directory when
both exist. See [database schemas](https://github.com/medz/dart-orm/blob/main/doc/namespaces.md).

## Help and automation

`dart run orm --help`, `dart run orm help migrate` and `dart run orm migrate
apply --help` describe command groups. Add `--json` to emit machine-readable
reports on stdout and error objects on stderr. JSON is a reporting format only;
schema snapshots and migration history remain Dart source.

Exit codes are `0` for success, `1` for execution/generation failure, `2` for
catalog drift or blocking import issues, and `64` for invalid arguments or
configuration. The Dart launcher may print native build-hook diagnostics on
stderr before the CLI starts; automation should parse successful stdout reports
and use the process exit code for failures.
