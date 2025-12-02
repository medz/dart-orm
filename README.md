# Dart ORM

> [!IMPORTANT]
>  December 2, 2025: I've decided to restart this project! Please check out 👉 "[Dartorm New Beginning!](https://github.com/medz/dart-orm/issues/479)"

> ⚠️ **IMPORTANT NOTICE**: Development of Prisma Dart Client has been suspended until after June 2025 due to Prisma's architectural changes from Rust to TypeScript. Current versions will continue to work with existing Prisma versions but will not be updated to support Prisma v7 and beyond until after the suspension period. For more details, please see the [official announcement](https://github.com/medz/prisma-dart/issues/471).

[![Pub Version](https://img.shields.io/pub/v/orm?include_prereleases)](https://pub.dev/packages/orm)
[![GitHub License](https://img.shields.io/github/license/medz/prisma-dart)](https://github.com/medz/prisma-dart/blob/main/LICENSE)
[![Docs website](https://img.shields.io/badge/docs-prisma.pub-brightgreen)](https://prisma.pub/)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/medz?label=github%20sponsors)](https://github.com/sponsors/medz)
[![Open Collective sponsors](https://img.shields.io/opencollective/sponsors/openodroe?label=open%20collective)](https://opencollective.com/openodroe)
[![Discord](https://img.shields.io/discord/1035043284457881620?label=discord)](https://discord.gg/ms2X9TQMR8)
[![X (formerly Twitter) Follow](https://img.shields.io/twitter/follow/shiweidu)
](https://twitter.com/shiweidu)

Prisma Client Dart is an auto-generated type-safe ORM. It uses Prisma Engine as the data access layer and is as consistent as possible with the Prisma Client JS/TS APIs.

👉 [Learn how to use Prisma ORM for Dart in your project](https://prisma.pub/).

```dart
import 'package:orm/orm.dart';

final client = PrismaClient();

main() {
  final users = await client.user.findMany();
}
```

## Installation

This will add a like this to you packages `pubspec.yaml` (and run an implicit `dart pub get`):

```yaml
dependencies:
  orm: latest
```

Or you can run the following command:

```sh
dart pub add orm
```

## Sponsors

Prisma Client Dart is an [BSD-3 Clause licensed](https://github.com/medz/prisma-dart/blob/main/LICENSE) open source project with its ongoing development made possible entirely by the support of these awesome backers. If you'd like to join them, please consider [sponsoring Seven(@medz)](https://github.com/sponsors/medz) on GitHub.

<p align="center">
  <a target="_blank" href="https://github.com/sponsors/medz#:~:text=Featured-,sponsors,-Current%20sponsors">
    <img alt="sponsors" src="https://github.com/medz/public/raw/main/sponsors.tiers.svg">
  </a>
</p>

## Documentation

You can find the Prisma Client Dart [on the website](https://prisma.pub).

The documentation is divided into the following sections:

- [Getting Started](https://prisma.pub/getting-started/)
  - [Setup & Configuration](https://prisma.pub/getting-started/setup.html)
  - [Prisma Schema](https://prisma.pub/getting-started/schema.html)
- Queries
  - [CRUD](https://prisma.pub/queries/crud.html)
  - [Select Fields](https://prisma.pub/queries/select-fields.html)
  - [Relation queries](https://prisma.pub/queries/relation-queries.html)
  - [Filtering and Sorting](https://prisma.pub/queries/filtering-and-sorting.html)
  - [Pagination](https://prisma.pub/queries/pagination.html)
  - [Aggregation, grouping, and summarizing](https://prisma.pub/queries/aggregation-grouping-summarizing.html)
  - [Transactions](https://prisma.pub/queries/transactions.html)
  - [Raw database access](https://prisma.pub/queries/raw-database-access.html)

> You can improve it by sending pull requests to [`docs` folder in the `main` branch](https://github.com/odroe/prisma-dart/tree/main/docs).

## Examples

You can also find them in the [`example` folder in the `main` branch](https://github.com/odroe/prisma-dart/tree/main/examples).

## Query engine support matrix

| Engine     | Dart Native | Dart Web | Flutter Native | Flutter Web |
| ---------- | :---------: | :------: | :------------: | :---------: |
| Binary     |     ✅      |    ❌    |       ❌       |     ❌      |
| Library    |     ✅      |    ❌    |       ✅       |     ❌      |
| Data Proxy |     ✅      |    ✅    |       ✅       |     ✅      |

## Contributing

We welcome contributions! Please read our [contributing guide](CONTRIBUTING.md) to learn about our development process, how to propose bugfixes and improvements, and how to build and test your changes to Prisma.

Thank you to all the people who already contributed to Prisma Dart!

[![Contributors](https://contrib.rocks/image?repo=medz/prisma-dart)](https://github.com/odroe/prisma-dart/graphs/contributors)

## Code of Conduct

This project has adopted the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). For more information see the [Code of Conduct FAQ](https://www.contributor-covenant.org/faq) or contact [hello@odroe.com](mailto:hello@odroe.com) with any additional questions or comments.
