import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import 'web_build.dart';

/// Copies only verified current assets. Existing older deployment assets remain.
Future<void> copySqliteWebAssets(Directory destination) async {
  final library = await Isolate.resolvePackageUri(
    Uri.parse('package:orm/sqlite.dart'),
  );
  if (library == null) {
    throw StateError('Cannot locate the installed ORM package.');
  }
  final files = [
    for (final (name, digest) in [
      (sqliteWorkerFile, sqliteWorkerSha256),
      (sqliteWasmFile, sqliteWasmSha256),
    ])
      (File.fromUri(library.resolve('../assets/sqlite/$name')), name, digest),
  ];
  // Validate everything before writing any output.
  for (final (file, _, digest) in files) {
    if (!await file.exists() ||
        (await sha256.bind(file.openRead()).first).toString() != digest) {
      throw StateError(
        'Packaged SQLite asset is missing or corrupt: ${file.path}',
      );
    }
  }
  await destination.create(recursive: true);
  for (final (file, name, _) in files) {
    await file.copy('${destination.path}/$name');
  }
}
