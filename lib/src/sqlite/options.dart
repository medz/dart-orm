import 'web_build.dart';

/// Native SQLite journal mode; browser persistence manages its own storage.
enum SqliteJournal {
  /// Uses a write-ahead log beside the database file.
  wal,

  /// Deletes the rollback journal after each completed transaction.
  delete,

  /// Keeps the rollback journal in memory.
  memory,
}

/// Chooses an in-memory, native-file, or browser-persistent SQLite database.
///
/// Use [SqliteOptions.memory] on any platform and [SqliteOptions.persistent] for
/// shared application configuration across native and browser deployments.
final class SqliteOptions {
  /// Native file path. Persistent browser databases use [name] instead.
  final String path;

  /// Browser persistence name; must contain only letters, digits, `_`, `-`, `.`.
  final String? name;

  /// Requested native journal mode; `null` preserves the existing mode.
  final SqliteJournal? journal;

  /// Whether a native file is opened without write access.
  final bool readOnly;

  /// Native wait time for a locked database before returning SQLite BUSY.
  final Duration busyTimeout;

  /// Browser worker and asset configuration.
  final SqliteWebOptions web;

  /// A native file. Web callers should use [SqliteOptions.persistent].
  const SqliteOptions.file(
    this.path, {
    this.journal = SqliteJournal.wal,
    this.busyTimeout = const Duration(seconds: 5),
  }) : name = null,
       readOnly = false,
       web = const SqliteWebOptions();

  /// Opens an existing native file without changing its journal mode.
  const SqliteOptions.readOnly(
    this.path, {
    this.busyTimeout = const Duration(seconds: 5),
  }) : name = null,
       journal = null,
       readOnly = true,
       web = const SqliteWebOptions();

  /// Creates an isolated database discarded when its driver closes.
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

  /// Worker script override, resolved against the HTML base URI.
  final Uri? worker;

  /// Subresource integrity for the SQLite module. Override for a custom build.
  final String wasmIntegrity;

  /// Deadline for the worker handshake and database initialization.
  final Duration openTimeout;

  /// Uses the matching packaged worker and SQLite module unless overridden.
  const SqliteWebOptions({
    this.assetBase,
    this.wasm,
    this.worker,
    this.wasmIntegrity = sqliteWasmIntegrity,
    this.openTimeout = const Duration(seconds: 15),
  });
}
