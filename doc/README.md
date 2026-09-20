# Dart ORM guides

Start with the [quickstart](https://github.com/medz/dart-orm/blob/main/README.md#get-started), then choose the guide for
the part of your application you are building.

The [API reference](https://pub.dev/documentation/orm/6.0.0-beta.2/) documents the
beta.2 package. See the [release notes](https://github.com/medz/dart-orm/blob/main/CHANGELOG.md#600-beta2)
when upgrading from beta.1.
Run `dart doc --validate-links` in a checkout to generate the reference from the
current public library and member comments into `doc/api/`.

| Task | Guide |
| --- | --- |
| Declare models, keys and relations | [Authoring](https://github.com/medz/dart-orm/blob/main/doc/authoring.md) |
| Understand imports and execution | [API and mental model](https://github.com/medz/dart-orm/blob/main/doc/api.md) |
| Filter, select, join and paginate | [Queries](https://github.com/medz/dart-orm/blob/main/doc/queries.md) |
| Load related data | [Relationships](https://github.com/medz/dart-orm/blob/main/doc/relations.md) |
| Work with domain values | [Types and codecs](https://github.com/medz/dart-orm/blob/main/doc/types.md), [Decimals](https://github.com/medz/dart-orm/blob/main/doc/decimals.md) |
| Define database behavior | [Defaults](https://github.com/medz/dart-orm/blob/main/doc/defaults.md), [Computed columns](https://github.com/medz/dart-orm/blob/main/doc/computed.md), [Checks](https://github.com/medz/dart-orm/blob/main/doc/checks.md) |
| Evolve or adopt a database | [Migrations](https://github.com/medz/dart-orm/blob/main/doc/migrations.md), [Backfills](https://github.com/medz/dart-orm/blob/main/doc/backfills.md), [Importing](https://github.com/medz/dart-orm/blob/main/doc/importing.md) |
| Use transactions, streaming and timeouts | [Execution](https://github.com/medz/dart-orm/blob/main/doc/execution.md) |
| Subscribe to changes | [Query subscriptions](https://github.com/medz/dart-orm/blob/main/doc/watch.md) |
| Inspect SQL and execution costs | [Observability](https://github.com/medz/dart-orm/blob/main/doc/observability.md), [Performance](https://github.com/medz/dart-orm/blob/main/doc/performance.md) |
| Use hand-written SQL | [Named SQL](https://github.com/medz/dart-orm/blob/main/doc/named-sql.md) |
| Configure generation and project commands | [CLI](https://github.com/medz/dart-orm/blob/main/doc/cli.md), [Generation](https://github.com/medz/dart-orm/blob/main/doc/generation.md) |
| Build Flutter or browser applications | [Flutter](https://github.com/medz/dart-orm/blob/main/doc/flutter.md), [SQLite Web](https://github.com/medz/dart-orm/blob/main/doc/sqlite-web.md) |
| Use MySQL or MariaDB | [Drivers](https://github.com/medz/dart-orm/blob/main/doc/mysql.md), [Migration recovery](https://github.com/medz/dart-orm/blob/main/doc/mysql-migrations.md) |
| Check supported behavior | [Capabilities](https://github.com/medz/dart-orm/blob/main/doc/capabilities.md), [Acceptance](https://github.com/medz/dart-orm/blob/main/doc/acceptance.md) |
| Contribute or reproduce validation | [Contributing](https://github.com/medz/dart-orm/blob/main/doc/contributing.md), [Progress](https://github.com/medz/dart-orm/blob/main/doc/progress.md) |

The beta uses Dart declarations and engine-specific Dart migration histories.
The retired Prisma-based 5.x documentation does not describe this API.
