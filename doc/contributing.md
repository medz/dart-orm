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

## Release checks

Check formatting and run `dart pub publish --dry-run`. The published package
includes its Dart sources, documentation, examples and SQLite Web assets;
development caches and repository test tools stay out of the archive.

`dart run tool/build_sqlite_web.dart --check` verifies committed worker/WASM
resources. Regenerate them only when their source fingerprint changes.
Keep validation records tied to the actual revision and platform tested.
