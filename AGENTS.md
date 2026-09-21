# Dart ORM

The current implementation is documented in `doc/README.md` and public Dartdoc.
Old code and upstream architecture are retired.

- Keep one product package. Add abstractions only to support real use cases.
- Use independent Dart libraries; never use `part` or `part of`.
- Keep implementation in `lib/src/` and public entrypoints as explicit exports.
- Document public behavior, ownership and failure boundaries with Dartdoc.
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
- Keep `doc/` focused on public usage, examples and compatibility limits.
  Keep research notes and development/test-run records out of public documentation;
  put reusable contributor workflows in `CONTRIBUTING.md`.
- Schema snapshots and saved migrations are Dart source. Retire the old JSON file
  workflow directly; do not add compatibility readers or parallel output modes.
- Keep historical migration definitions independent of current application models.
  Persist reviewed fingerprints and use static imports for migration registration.

Commands: `dart run bin/orm.dart`, `dart analyze`, `dart test`.
