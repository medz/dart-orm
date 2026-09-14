# Dart ORM

This branch is a new implementation. The design reference is
`research/new-dart-orm-design.md`; old code and upstream architecture are retired.

- Keep one product package. Add abstractions only to support real use cases.
- Use Dart 3.13 stable syntax, static generation, explicit sessions and typed selections.
- Table identity is independent of Dart record identity.
- Parameterize values, quote identifiers, and validate SQL scope before execution.
- Make relationship query counts and transaction boundaries observable.
- SQLite and PostgreSQL have separate driver configuration and capability checks.
- Verify behavior against real databases. Mark unverified platforms explicitly.
- Preserve immutable migration history and never infer destructive renames.
- Prefer small Conventional Commits. Do not push without explicit authorization.
- Keep `docs/progress.md` accurate, including unfinished work and validation limits.

Commands: `dart run bin/orm.dart`, `dart analyze`, `dart test`.
