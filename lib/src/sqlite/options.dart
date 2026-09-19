import 'web_build.dart';

enum SqliteJournal { wal, delete, memory }

final class SqliteOptions {
  /// Native file path. Persistent browser databases use [name] instead.
  final String path;
  final String? name;
  final SqliteJournal? journal;
  final bool readOnly;
  final Duration busyTimeout;
  final SqliteWebOptions web;

  /// A native file. Web callers should use [SqliteOptions.persistent].
  const SqliteOptions.file(
    this.path, {
    this.journal = SqliteJournal.wal,
    this.busyTimeout = const Duration(seconds: 5),
  }) : name = null,
       readOnly = false,
       web = const SqliteWebOptions();

  const SqliteOptions.readOnly(
    this.path, {
    this.busyTimeout = const Duration(seconds: 5),
  }) : name = null,
       journal = null,
       readOnly = true,
       web = const SqliteWebOptions();

  const SqliteOptions.memory({
    this.busyTimeout = const Duration(seconds: 5),
    this.web = const SqliteWebOptions(),
  }) : path = ':memory:',
       name = null,
       journal = SqliteJournal.memory,
       readOnly = false;

  /// OPFS on Web; [nativePath] on native platforms.
  ///
  /// Native callers must supply a non-empty file path in a directory they own.
  /// The ORM does not guess a Flutter application's documents directory.
  const SqliteOptions.persistent(
    String this.name, {
    String? nativePath,
    this.journal = SqliteJournal.wal,
    this.busyTimeout = const Duration(seconds: 5),
    this.web = const SqliteWebOptions(),
  }) : path = nativePath ?? '',
       readOnly = false;
}

/// Advanced browser asset overrides. Flutter Web needs no asset configuration.
final class SqliteWebOptions {
  /// Directory containing the packaged, versioned assets. Relative to HTML base.
  /// Defaults to Flutter package assets, or `orm/` in a plain Dart web app.
  final Uri? assetBase;

  /// Overrides are relative to the document's HTML base, not [assetBase].
  final Uri? wasm;
  final Uri? worker;

  /// Subresource integrity for the SQLite module. Override for a custom build.
  final String wasmIntegrity;
  final Duration openTimeout;
  const SqliteWebOptions({
    this.assetBase,
    this.wasm,
    this.worker,
    this.wasmIntegrity = sqliteWasmIntegrity,
    this.openTimeout = const Duration(seconds: 15),
  });
}
