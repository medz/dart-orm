# Generation and incremental builds

The standalone CLI and [build_runner](https://dart.dev/tools/build_runner) use
one annotation reader, validator and source emitter. Generation analyzes Dart
without opening a database or executing application factories.

Declare ordinary DTO classes with `@Model()` from `package:orm/schema.dart`.
Generated clients import and re-export the original classes, construct them when
decoding complete rows, and expose typed table getters plus an immutable
`appSchema`. They do not create a second row class. Scalar projections and
explicit relationship selections retain their own result types.

```dart
import 'package:orm/schema.dart';

@Model(table: 'users')
final class User({
  @Id(generated: true) required final int id,
  @Unique() required final String email,
  final String? nickname,
});
```

Public tooling is in `generate.dart`; builder factories are exported only by
`builder.dart`. Application code imports its generated client and chosen database
entrypoint. See [API boundaries](https://github.com/medz/dart-orm/blob/main/doc/api.md).

## Standalone command

```sh
dart run orm init --database sqlite
dart run orm generate
# Or select a source and engine explicitly:
dart run orm generate lib/models.dart --database sqlite
```

The path-free command reads `defineConfig(models: ...)` from `orm.config.dart`,
or defaults to `lib/models.dart` without a configuration. A configuration uses
parameterless `void main()` and requires no generated imports, so generation works
before any client, snapshot or migration registry exists. See
[project configuration](https://github.com/medz/dart-orm/blob/main/doc/cli.md).

A `lib/models.dart` root produces `lib/models.orm.dart` and
`lib/models.snapshot.dart`. The snapshot is standalone physical metadata with no
application imports. An explicit `database.dart` output gets an adjacent
`database.snapshot.dart`:

```sh
dart run orm generate lib/models.dart lib/generated/database.dart --database sqlite
```

Directory outputs must not become discovered model inputs. Use an `.orm.dart`
filename inside the source directory or choose an output outside it. Collisions
are rejected before either output is written. The CLI checks source errors and
resolves imports through the project's package configuration.

## build_runner

Use Dart 3.13 or newer and add build_runner as an application development dependency:

```sh
dart pub add dev:build_runner
```

Select individual model roots in `build.yaml`:

```yaml
targets:
  $default:
    builders:
      orm:orm:
        enabled: true
        generate_for:
          - lib/models.dart
```

Then build once or watch:

```sh
dart run build_runner build
dart run build_runner watch
```

A file root contains or exports annotated models. Relation targets are discovered
transitively; unrelated imports do not create additional model roots. Do not
select every Dart file or a `part of` file. Each additional root gets its own
client and snapshot. Use import prefixes where clients have overlapping query
member names.

`lib/models.dart` always produces adjacent `lib/models.orm.dart` and
`lib/models.snapshot.dart`. Set `options.database: postgres` for PostgreSQL
namespace rules. Use the CLI's output path for other locations. build_runner
owns its output cleanup and cache; do not edit either manually.

## Model directories

Select a directory root through builder options:

```yaml
targets:
  $default:
    builders:
      orm:orm:
        enabled: true
        options:
          models: lib/models
          database: postgres
```

Directory roots discover model sources recursively for every engine. A sibling
`lib/models.dart` is also included when present. Generated `.orm.dart` and
`.snapshot.dart` files are excluded. Outputs remain `lib/models.orm.dart` and
`lib/models.snapshot.dart`; a wrapper source file is not required.

Every other discovered Dart file must be an independent library. Both the CLI
and builder reject `part of` inputs, including unrelated generated `.g.dart`
parts inside the selected directory. Keep those parts outside the model layout
or select individual model libraries instead. Generation does not silently skip
discovered parts or treat their declarations as separate libraries.

The CLI accepts `lib/models`, `lib/models/` or `lib/models.dart` for this root.
Folder names do not determine physical namespaces. For PostgreSQL,
`@Model(namespace: ...)` overrides the configured `defaultNamespace`, with
`public` as the final default. Other engines reject explicit namespaces. See
[database schemas](https://github.com/medz/dart-orm/blob/main/doc/namespaces.md).

## Regeneration and errors

The builder resolves through `BuildStep.resolver` and writes through
`BuildStep.writeAsString`, sharing build_runner's analysis and dependency tracking.
Model imports, exports, imported enums, codec metadata and constants are tracked.
Directory file additions/deletions and metadata edits regenerate affected outputs;
unrelated source edits do not. Deleting a root removes its outputs, and recreating
it regenerates them. An unchanged build reports no new outputs.

Both entrypoints reject Dart errors and unsupported model mappings before emission.
Application codecs and client-default factories are referenced rather than run.
Relations are validated against the original target classes and fields before
query navigation is emitted. Ambiguous mappings, incompatible fields and generated
member collisions fail with source locations. Model-specific diagnostics currently
run during generation rather than through a dedicated editor plugin.

Source models must not import generated clients: that would make a first build
or regeneration depend on its own previous output. Formatting finishes before
either output is written. A failed build can be repaired and retried by the same
watcher. Generated files are reviewable and may be committed with an application.

Run `dart analyze` after generating to check affected queries and DTO consumers.
A renamed Dart field can preserve its column using `@Column(name: 'old_name')`;
a changed database identity requires a reviewed migration. Snapshot changes do
not authorize DDL. Follow the
[migration workflow](https://github.com/medz/dart-orm/blob/main/doc/migrations.md)
to review and explicitly apply database changes.
