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
- Each migration history fixes one database engine. Save only that engine's SQL,
  steps and frozen schema; reject mixed histories and mismatched connections.
- Prefer small Conventional Commits. Do not push without explicit authorization.
- Keep `docs/progress.md` accurate, including unfinished work and validation limits.
- Schema snapshots and saved migrations are Dart source. Retire the old JSON file
  workflow directly; do not add compatibility readers or parallel output modes.
- Keep historical migration definitions independent of current application models.
  Persist reviewed fingerprints and use static imports for migration registration.

Commands: `dart run bin/orm.dart`, `dart analyze`, `dart test`.
