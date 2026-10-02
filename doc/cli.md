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
| `lib/models.dart` | Editable annotated DTO classes |
| `lib/models.orm.dart` | Typed queries using the original DTO types |
| `lib/models.snapshot.dart` | Standalone physical schema |
| `migrations/migrations.g.dart` | Static history imports and one fixed engine |
| `orm.config.dart` | Runnable project configuration |

Initialization refuses existing destinations before writing anything. It never
connects, creates a database file or applies DDL. build_runner is optional.
SQLite's generated connection factory uses `app.sqlite` relative to the command's
working directory. Server factories read `DATABASE_URL` only when connecting;
missing credentials do not prevent generation or history validation. Server TLS
defaults to certificate verification.

## Runnable configuration

The configuration contains ordinary Dart and does not import generated files:

```dart
import 'package:orm/config.dart';
import 'package:orm/sqlite.dart';
import 'package:orm/sql.dart';

void main() {
  defineConfig(
    database: .sqlite,
    models: 'lib/models.dart',
    output: 'lib/models.orm.dart',
    migrations: 'migrations',
    connect: ({required bool readOnly}) async => SqlDatabase(
      await SqliteDriver.open(readOnly
          ? const SqliteOptions.readOnly('app.sqlite')
          : const SqliteOptions.file('app.sqlite')),
    ),
  );
}
```

`models`, `output` and `migrations` are direct string paths relative to the
configuration file's directory. `models` accepts one Dart file or a recursively
discovered source directory. Omit `output` to use the model root's `.orm.dart`
basename. PostgreSQL accepts `defaultNamespace: 'application'`; an explicit
`@Model(namespace: ...)` overrides it. Source folder names never select namespaces.

Run `dart run orm generate` for the first build. Neither a snapshot nor a history
registry needs to exist. `--config configuration/development.dart` selects another
entrypoint; the option's path is relative to the command's working directory.
Paths used inside a connection callback are application-owned and are not rewritten.

The CLI executes `main()` to register the configuration. For migration commands,
it compiles a second static entrypoint when a registry exists. Keep registration
free of side effects: `main()` may run twice for one command. Put connection setup
inside `connect`, which is called only by database commands. Do not invoke
`orm.config.dart` directly as a command-line executable. A dedicated
[migration executable](https://github.com/medz/dart-orm/blob/main/doc/migrations.md#deployment-bundle)
is available for frozen-history deployment.

## Commands and side effects

| Command | Behavior |
| --- | --- |
| `generate` | Write the typed client and physical snapshot |
| `migrate create <id>` | Regenerate current models, then save a reviewed diff |
| `migrate check` | Validate registered files, fixed engine and fingerprints offline |
| `migrate plan` | Read applied history and report pending operations |
| `migrate apply` | Apply pending operations explicitly |
| `migrate status` | Read applied history and recovery checkpoints |
| `migrate verify` | Compare the catalog with current models without writing generated files |
| `migrate baseline` | Verify an existing schema against the last frozen snapshot and register history |
| `migrate record <id>` | Record a reviewed edit to the latest unpublished migration |
| `migrate inspect <table>` | Read physical metadata for one table |

`create` and `verify` analyze the current models, including edits since the last
`generate`. Other migration commands use the frozen history without loading
current models or generated clients. They remain usable if those application
sources are temporarily missing or invalid. Database commands own and close the
runtime returned by `connect`; read-only commands request `readOnly: true`.

A missing registry represents an empty history only if no migration source files
exist. Existing migrations without a registry, stale registry membership and an
engine different from `database` fail before opening a connection. Rebuild static
imports explicitly with `migration registry`; this does not accept edited
fingerprints. `record` is the separate, explicit review step for an unpublished edit.

An initial SQLite `plan` needs an existing database file and fails without creating
one. The first `apply` can create it. `create <id> --allow-destructive` permits
writing reviewed drop operations, not executing them. `apply
--max-backfill-batches <count>` bounds a resumable backfill invocation. No command
except explicit `apply` or `baseline` changes database state.

## Explicit tools

These commands also work without project configuration:

```sh
dart run orm generate lib/models.dart lib/generated/database.dart --database sqlite
dart run orm generate lib/models --database postgres
dart run orm migration registry migrations --dialect sqlite
dart run orm db inspect --sqlite app.sqlite --table tasks
dart run orm db import --sqlite app.sqlite --output lib/imported.dart
dart run orm web-assets web/orm
```

Generation normally loads the project configuration, even with a positional source
path. `--database` bypasses the default configuration; an explicit `--config`
still loads it and rejects a mismatched engine. Without a configuration or source
path, generation uses `lib/models.dart`. Positional source/output overrides are
relative to the command's working directory.

Server database flags are `--postgres-env NAME`, `--mysql-env NAME` and
`--mariadb-env NAME`. Choose one database option. `--tls
verifyFull|require|disable` configures server TLS; `--database-schema` is specific
to PostgreSQL. Catalog import writes a Dart draft and a separate review report;
it does not migrate an existing database.

## Help and automation

`dart run orm --help`, `dart run orm help migrate` and `dart run orm migrate
apply --help` describe command groups. Add `--json` for machine-readable reports
on stdout and error objects on stderr. Schema snapshots and migration history
remain Dart source.

Exit codes are `0` for success, `1` for execution/generation failure, `2` for
catalog drift or blocking import issues, and `64` for invalid arguments or
configuration. Compilation failures in a loaded config or migration registry are
reported as execution failures (`1`), with compiler diagnostics in the JSON error
message. The outer Dart launcher can still emit its own native build-hook
diagnostics before the package CLI starts.
