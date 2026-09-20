# Contributing

Use Dart 3.13 or newer. From a repository checkout:

```sh
dart pub get
dart analyze
dart test
dart run example/main.dart
dart run example/queries.dart
```

The Flutter example is a separate package; run its analysis with the Flutter SDK.
For browser checks, set `CHROME_EXECUTABLE` and run
`dart run tool/test_browser.dart`, then add `--wasm` for the WASM build.

## Real database checks

Set `ORM_TEST_POSTGRES`, `ORM_TEST_MYSQL` and `ORM_TEST_MARIADB` to disposable
database URLs to include those integration suites. Tests create and drop their
own tables; MySQL/MariaDB migration tests also create isolated databases.
Use dedicated test servers and accounts with those privileges.

Server TLS defaults to `verifyFull`. Self-signed local fixtures can explicitly
set `ORM_TEST_MYSQL_TLS=require` and `ORM_TEST_MARIADB_TLS=require`.
Run `dart test --concurrency=1` when testing the complete native matrix.

## Documentation and public APIs

Keep public entrypoints explicit and add `///` comments at the declarations they
export. Explain result shape, ownership, transaction boundaries and errors where
those affect callers. Internal modules use ordinary imports and exports; do not
introduce `part` directives to share private state.

Handwritten guides live in `doc/`. Dartdoc categories connect those guides to API
navigation. After changing comments, exports or category configuration, run:

```sh
dart doc --validate-links
```

After moving or renaming APIs, remove the previous generated `doc/api/` directory
before regenerating so stale pages cannot survive. Broken links, ambiguous
canonical exports and unresolved symbol references fail documentation generation.

Inspect the generated `doc/api/` pages through a local HTTP server, including
library/category navigation, symbol links and public signatures. Do not commit
or publish that generated directory. Run package analysis and the relevant
examples as well; a formatted code block alone does not verify an example.

## Release checks

Check formatting and run `dart pub publish --dry-run`. The published package
includes its Dart sources, documentation, examples and SQLite Web assets;
development caches and repository test tools stay out of the archive.

`dart run tool/build_sqlite_web.dart --check` verifies committed worker/WASM
resources. Regenerate them only when their source fingerprint changes.
Keep validation records tied to the actual revision and platform tested.
