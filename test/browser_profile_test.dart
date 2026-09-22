@Tags(['core'])
library;

import 'dart:io';

import 'package:test/test.dart';

import '../tool/src/browser_profile.dart';

void main() {
  final notEmpty = Platform.isWindows
      ? 145
      : Platform.isMacOS
      ? 66
      : 39;
  FileSystemException failure(int code) => FileSystemException(
    'Deletion failed',
    '/temporary/profile',
    OSError('simulated filesystem race', code),
  );

  test(
    'removes a real nested profile and accepts an already removed root',
    () async {
      final profile = await Directory.systemTemp.createTemp(
        'orm-profile-test-',
      );
      addTearDown(() async {
        if (await profile.exists()) await profile.delete(recursive: true);
      });
      final settings = File('${profile.path}/Default/Preferences');
      await settings.parent.create();
      await settings.writeAsString('{}');
      await deleteBrowserProfile(profile);
      await deleteBrowserProfile(profile);
      expect(await profile.exists(), isFalse);
    },
  );

  test('retries a directory that receives late browser writes', () async {
    final profile = _Profile([failure(notEmpty), failure(notEmpty)]);
    await deleteBrowserProfile(profile);
    expect(profile.deletes, 3);
  });

  test(
    'retries a disappeared child while the profile root still exists',
    () async {
      final profile = _Profile([failure(2)]);
      await deleteBrowserProfile(profile);
      expect(profile.deletes, 2);
    },
  );

  test('exhausted cleanup preserves the final filesystem error', () async {
    final last = failure(notEmpty);
    final profile = _Profile(List.filled(20, last));
    await expectLater(deleteBrowserProfile(profile), throwsA(same(last)));
    expect(profile.deletes, 20);
  });

  test('unrelated filesystem failures are not retried or swallowed', () async {
    final denied = failure(13);
    final profile = _Profile([denied]);
    await expectLater(deleteBrowserProfile(profile), throwsA(same(denied)));
    expect(profile.deletes, 1);
  });
}

final class _Profile(this.failures) implements Directory {
  final List<FileSystemException> failures;
  int deletes = 0;

  @override
  Future<Directory> delete({bool recursive = false}) async {
    expect(recursive, isTrue);
    final index = deletes++;
    if (index < failures.length) throw failures[index];
    return this;
  }

  @override
  Future<bool> exists() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
