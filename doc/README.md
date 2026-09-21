# Dart ORM guides

Define a schema, generate typed models and queries, and evolve your database with
reviewed Dart migrations. Start with [schema declarations](https://github.com/medz/dart-orm/blob/main/doc/authoring.md)
and the [company example](https://github.com/medz/dart-orm/blob/main/example/company/README.md).

> **Version:** These guides describe `6.0.0-beta.3` and its Record schema API.
> When upgrading, replace annotated entities with `model(...)` and regenerate
> clients. Keep existing migration history unchanged.

## Define and query

| Task | Guide |
| --- | --- |
| Define models, columns, keys and relationships | [Schema declarations](https://github.com/medz/dart-orm/blob/main/doc/authoring.md) |
| Generate a client and use build_runner | [Generation](https://github.com/medz/dart-orm/blob/main/doc/generation.md) |
| Choose imports and open a database | [Entrypoints](https://github.com/medz/dart-orm/blob/main/doc/api.md) |
| Filter, select, join and paginate | [Queries](https://github.com/medz/dart-orm/blob/main/doc/queries.md) |
| Load related data | [Relationships](https://github.com/medz/dart-orm/blob/main/doc/relations.md) |
| Use domain values, enums and JSON | [Types and codecs](https://github.com/medz/dart-orm/blob/main/doc/types.md), [Decimals](https://github.com/medz/dart-orm/blob/main/doc/decimals.md) |
| Add defaults and database constraints | [Defaults](https://github.com/medz/dart-orm/blob/main/doc/defaults.md), [Computed columns](https://github.com/medz/dart-orm/blob/main/doc/computed.md), [Checks](https://github.com/medz/dart-orm/blob/main/doc/checks.md) |

## Run and maintain

| Task | Guide |
| --- | --- |
| Configure project commands | [CLI](https://github.com/medz/dart-orm/blob/main/doc/cli.md) |
| Evolve or adopt a database | [Migrations](https://github.com/medz/dart-orm/blob/main/doc/migrations.md), [Backfills](https://github.com/medz/dart-orm/blob/main/doc/backfills.md), [Importing](https://github.com/medz/dart-orm/blob/main/doc/importing.md) |
| Use transactions, streaming and timeouts | [Execution](https://github.com/medz/dart-orm/blob/main/doc/execution.md) |
| Subscribe to changes | [Query subscriptions](https://github.com/medz/dart-orm/blob/main/doc/watch.md) |
| Inspect SQL and query costs | [Observability](https://github.com/medz/dart-orm/blob/main/doc/observability.md), [Performance](https://github.com/medz/dart-orm/blob/main/doc/performance.md) |
| Use hand-written SQL | [Named SQL](https://github.com/medz/dart-orm/blob/main/doc/named-sql.md) |

## Choose a platform

| Task | Guide |
| --- | --- |
| Check engine and platform limits | [Capabilities](https://github.com/medz/dart-orm/blob/main/doc/capabilities.md) |
| Build Flutter or browser applications | [Flutter](https://github.com/medz/dart-orm/blob/main/doc/flutter.md), [SQLite Web](https://github.com/medz/dart-orm/blob/main/doc/sqlite-web.md) |
| Use MySQL or MariaDB | [Drivers](https://github.com/medz/dart-orm/blob/main/doc/mysql.md), [Migration recovery](https://github.com/medz/dart-orm/blob/main/doc/mysql-migrations.md) |

For repository setup, tests and documentation changes, see
[Contributing](https://github.com/medz/dart-orm/blob/main/CONTRIBUTING.md).
