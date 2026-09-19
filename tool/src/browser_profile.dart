import 'dart:io';

/// Chrome children can still finish profile writes after the parent exits.
Future<void> deleteBrowserProfile(Directory profile) async {
  const attempts = 20;
  final notEmpty = Platform.isWindows
      ? 145
      : Platform.isMacOS
      ? 66
      : 39;
  for (var attempt = 1; attempt <= attempts; attempt++) {
    try {
      await profile.delete(recursive: true);
      return;
    } on FileSystemException catch (error) {
      final code = error.osError?.errorCode;
      final missing = code == 2 || Platform.isWindows && code == 3;
      if (missing && !await profile.exists()) return;
      if ((!missing && code != notEmpty) || attempt == attempts) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}
