part of '../generate.dart';

/// Regenerates only static imports. Fingerprints stay in the migration files.
Future<String> writeMigrationRegistry(
  String directory, {
  SqlDialect? dialect,
}) async {
  dialect = await _registryDialect(directory, dialect);
  final root = Directory(directory);
  await root.create(recursive: true);
  final ids = await _migrationIds(root);
  final path = p.join(directory, 'migrations.g.dart');
  await _replaceSource(
    path,
    _formatMigration(migrationHistorySource(ids, dialect: dialect)),
  );
  return path;
}

/// Saves a new fixed migration and updates the registry. Never replaces a file.
Future<String> writeMigration(
  Migration migration, {
  required String directory,
  required MigrationHistory history,
}) async {
  final previous = history.checked;
  final all = [...previous, migration];
  validateMigrations(all, dialect: history.dialect);
  await _registryDialect(directory, history.dialect);
  final root = Directory(directory);
  await root.create(recursive: true);
  await _checkMigrationFiles(root, previous);
  final source = _formatMigration(migrationSource(migration));
  final registry = _formatMigration(
    migrationHistorySource(all.map((m) => m.id), dialect: history.dialect),
  );
  final file = File(p.join(directory, 'm${migration.id}.dart'));
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw GenerationException('Migration already exists: ${file.path}');
  }
  await file.create(exclusive: true);
  try {
    await file.writeAsString(source, flush: true);
    await _replaceSource(p.join(directory, 'migrations.g.dart'), registry);
  } catch (_) {
    await file.delete();
    rethrow;
  }
  return file.path;
}

/// Records a reviewed edit to the latest unpublished migration. Its source is
/// retained verbatim apart from the fingerprint literal. Applied files must not
/// be edited or recorded again; this offline tool cannot know deployment state.
Future<String> recordMigration(
  String id, {
  required String directory,
  required MigrationHistory history,
}) async {
  if (history.entries.isEmpty || history.entries.last.$1.id != id) {
    throw const GenerationException(
      'Only the latest unpublished migration can be recorded.',
    );
  }
  MigrationHistory(
    history.entries.take(history.entries.length - 1),
    dialect: history.dialect,
  ).checked;
  final migrations = history.entries.map((e) => e.$1).toList();
  validateMigrations(migrations, dialect: history.dialect);
  await _registryDialect(directory, history.dialect);
  await _checkMigrationFiles(Directory(directory), migrations);
  final path = p.join(directory, 'm$id.dart');
  final file = File(path);
  final content = await file.readAsString();
  final unit = parseString(content: content, path: path).unit;
  final fingerprints = [
    for (final declaration
        in unit.declarations.whereType<TopLevelVariableDeclaration>())
      if (declaration.variables.isConst)
        for (final variable in declaration.variables.variables)
          if (variable.name.lexeme == 'migrationChecksum') variable,
  ];
  if (fingerprints.length != 1 ||
      fingerprints.single.initializer is! SimpleStringLiteral) {
    throw const GenerationException(
      'Use one const migrationChecksum string literal.',
    );
  }
  final literal = fingerprints.single.initializer!;
  await _replaceSource(
    path,
    content.replaceRange(
      literal.offset,
      literal.end,
      _literal(migrations.last.checksum),
    ),
  );
  return migrations.last.checksum;
}

Future<List<String>> _migrationIds(Directory directory) async {
  final ids = <String>[];
  await for (final entity in directory.list(followLinks: false)) {
    final name = p.basename(entity.path);
    if (name == 'migrations.g.dart' || !name.endsWith('.dart')) continue;
    final match = RegExp(r'^m([0-9]+_[a-z][a-z0-9_]*)\.dart$').firstMatch(name);
    if (match == null || entity is! File) {
      throw GenerationException(
        'Expected a regular m<id>.dart migration: ${entity.path}',
      );
    }
    ids.add(match.group(1)!);
  }
  return ids..sort();
}

Future<void> _checkMigrationFiles(
  Directory directory,
  List<Migration> migrations,
) async {
  final actual = await _migrationIds(directory);
  final expected = migrations.map((m) => m.id).toList();
  if (!_same(actual, expected)) {
    throw const GenerationException(
      'Migration registry is stale. Regenerate static imports, then run the command again.',
    );
  }
}

String _formatMigration(String source) =>
    DartFormatter(languageVersion: DartFormatter.latestLanguageVersion)
        .format(source);

Future<void> _replaceSource(String path, String source) async {
  final kind = await FileSystemEntity.type(path, followLinks: false);
  if (kind != FileSystemEntityType.notFound &&
      kind != FileSystemEntityType.file) {
    throw GenerationException('Expected a regular source file: $path');
  }
  final temporary = File(
    '$path.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  await temporary.create(exclusive: true);
  try {
    await temporary.writeAsString(source, flush: true);
    await temporary.rename(path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}

/// A saved target is never changed by registry regeneration, including when empty.
Future<SqlDialect> _registryDialect(
  String directory,
  SqlDialect? requested,
) async {
  final file = File(p.join(directory, 'migrations.g.dart'));
  final kind = await FileSystemEntity.type(file.path, followLinks: false);
  if (kind == FileSystemEntityType.notFound) {
    return requested ??
        (throw const GenerationException(
          'Choose --dialect sqlite, postgres, mysql or mariadb when initializing a migration registry.',
        ));
  }
  if (kind != FileSystemEntityType.file) {
    throw GenerationException('Expected a regular source file: ${file.path}');
  }
  final unit = parseString(content: await file.readAsString()).unit;
  final values = [
    for (final d in unit.declarations.whereType<TopLevelVariableDeclaration>())
      if (d.variables.isConst)
        for (final v in d.variables.variables)
          if (v.name.lexeme == 'migrationDialect') v.initializer?.toSource(),
  ];
  final saved = values.length == 1
      ? switch (values.single) {
          'SqlDialect.sqlite' => SqlDialect.sqlite,
          'SqlDialect.postgres' => SqlDialect.postgres,
          'SqlDialect.mysql' => SqlDialect.mysql,
          'SqlDialect.mariadb' => SqlDialect.mariadb,
          _ => null,
        }
      : null;
  if (saved == null || requested != null && requested != saved) {
    throw const GenerationException(
      'Migration registry has a different or invalid database target. Use a separate history for another engine.',
    );
  }
  return saved;
}
