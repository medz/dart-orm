# Flutter acceptance

For Web, use the same package and SQLite entry point:

```sh
cd example/flutter
flutter pub get
flutter run -d chrome
flutter build web --wasm
```

No worker compilation, WASM download or application asset declaration is needed.
The Web example applies the fixed Dart migration history, persists a note and its
comment in one transaction, loads typed relationships and checks that animation
advances during worker SQL. Refreshing the page retains its OPFS database.
The platform-specific acceptance files select different checks and host reporting;
they do not implement database drivers.

The automated release runner is `dart run tool/test_flutter_web.dart /path/to/flutter`
from the repository root. For native directory choices and current platform limits,
see [SQLite setup](../../docs/sqlite-web.md).

## Android acceptance

This Android application exercises the public ORM APIs in an installed Flutter
app. The native bridge only provides the application's files directory and launch
phase; SQLite executes through `package:orm/sqlite.dart` in its worker isolate.

The legacy schema stores two notes. The current schema preserves the physical
`body` column while exposing `text`, adds a defaulted `done` field and a related
comments table. Both migrations are fixed Dart libraries with recorded fingerprints, imported
through a static registry and compiled into the APK. No migration assets are loaded. The application
checks generated CRUD, transaction rollback, relation projections, watch delivery,
cancellation, read-only reopening and process persistence.

Use a dedicated arm64 Android emulator. The runner rejects physical-device serials
and an already-installed `dev.orm.orm_flutter`; it never clears application data.
To repeat, explicitly uninstall that test app on your dedicated emulator or use a
fresh emulator. No production database or physical device is involved.

From the repository root, after choosing an installed Flutter SDK:

```sh
cd example/flutter
flutter pub get
flutter build apk --debug --target-platform android-arm64 \
  --dart-define=ORM_SCHEMA_VERSION=1
mkdir -p ../../.dart_tool/flutter
cp build/app/outputs/flutter-apk/app-debug.apk ../../.dart_tool/flutter/legacy.apk
flutter build apk --release --target-platform android-arm64 --build-number=2 \
  --dart-define=ORM_SCHEMA_VERSION=2
cp build/app/outputs/flutter-apk/app-release.apk ../../.dart_tool/flutter/current.apk
cd ../..
dart run tool/test_flutter.dart /path/to/android/sdk/platform-tools/adb \
  emulator-5580 .dart_tool/flutter/legacy.apk .dart_tool/flutter/current.apk
```

The example uses Flutter's debug signing key for both APKs so `adb install -r`
can preserve the database. These APKs are test artifacts, not store releases.
The runner force-stops between phases, verifies distinct process IDs and matching
database paths, compares rows and migration checksums after restart, and saves a
machine-readable report at `research/validation/flutter.json`. Logs, individual
reports and APK copies stay in `.dart_tool/flutter/`; the final screenshot is
saved as `research/validation/flutter-android.png`.

The application prints chunked base64 JSON so the host can capture release reports
without `run-as`. SQL work runs while a Flutter animation and Dart timer advance;
their progress verifies worker separation, not a frame-rate performance target.
The acceptance scope is the tested Android emulator. iOS, macOS Flutter, physical
devices and power-loss recovery require their own runs.

To edit the schema, run the generator from the repository root after `pub get`:

```sh
dart run bin/orm.dart generate example/flutter/lib/legacy/schema.dart
dart run bin/orm.dart generate example/flutter/lib/schema.dart
```

Do not regenerate applied migration history. Add a reviewed migration for future
schema changes.
