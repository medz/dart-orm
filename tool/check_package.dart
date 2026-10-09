import 'dart:io';

import 'package:path/path.dart' as p;

/// Verifies a downloaded pub.dev archive in a fresh consumer, using both engines.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1 || !File(arguments.single).existsSync()) {
    stderr.writeln(
      'Usage: dart run tool/check_package.dart /path/orm-version.tar.gz',
    );
    exitCode = 64;
    return;
  }
  if (!Platform.environment.containsKey('ORM_TEST_POSTGRES_HOST') &&
      !Platform.environment.containsKey('ORM_TEST_POSTGRES_SOCKET')) {
    stderr.writeln(
      'Configure a disposable PostgreSQL instance with ORM_TEST_POSTGRES_HOST or ORM_TEST_POSTGRES_SOCKET.',
    );
    exitCode = 64;
    return;
  }
  final directory = await Directory.systemTemp.createTemp('orm-package-check-');
  try {
    final archive = p.absolute(arguments.single);
    final listing = await _run('tar', ['-tzf', archive]);
    for (final name in listing.split('\n').where((name) => name.isNotEmpty)) {
      final components = p.posix.split(name);
      if (p.posix.isAbsolute(name) ||
          components.contains('..') ||
          components.any(
            (component) => {
              '.git',
              '.dart_tool',
              '.gradle',
              '.idea',
              'build',
              'test',
              'tool',
            }.contains(component),
          ) ||
          components.any(
            (component) => component == '.env' || component.startsWith('.env.'),
          ) ||
          name.startsWith('example/flutter/')) {
        throw StateError('Unexpected archive entry: $name');
      }
    }
    final package = await Directory(p.join(directory.path, 'package')).create();
    await _run('tar', ['-xzf', archive, '-C', package.path]);
    for (final module in [
      'database',
      'schema',
      'query',
      'sqlite',
      'postgres',
      'migration',
      'dev',
    ]) {
      if (!File(p.join(package.path, 'lib', '$module.dart')).existsSync()) {
        throw StateError('Archive lacks the $module public entrypoint.');
      }
    }
    final metadata = await File(p.join(package.path, 'pubspec.yaml'))
        .readAsString();
    final version = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(metadata)?.group(1);
    if (version == null ||
        !RegExp(r'^name:\s*orm\s*$', multiLine: true).hasMatch(metadata)) {
      throw StateError('Archive is not an identifiable ORM package.');
    }
    final consumer = await Directory(p.join(directory.path, 'consumer'))
        .create();
    await Directory(p.join(consumer.path, 'lib')).create();
    await Directory(p.join(consumer.path, 'bin')).create();
    await File(p.join(consumer.path, 'pubspec.yaml')).writeAsString('''
name: orm_package_consumer
environment:
  sdk: '>=3.13.0 <4.0.0'
dependencies:
  orm:
    path: ../package
''');
    for (final name in ['models.dart', 'shop.dart']) {
      await File(p.join(package.path, 'example', name))
          .copy(p.join(consumer.path, 'lib', name));
    }
    final dart = Platform.resolvedExecutable;
    await _run(dart, ['pub', 'get'], workingDirectory: consumer.path);
    for (final engine in ['sqlite', 'postgresql']) {
      await _run(dart, [
        'run',
        'orm',
        'generate',
        '--schema',
        'lib/models.dart',
        '--out',
        'lib/models.db.dart',
        '--name',
        'AppDatabase',
        '--engine',
        engine,
      ], workingDirectory: consumer.path);
      await _run(dart, [
        'run',
        'orm',
        'migration',
        'draft',
        '--to',
        'lib/models.snapshot.dart',
        '--out',
        'lib/migrations/$engine.dart',
        '--version',
        '1',
        '--name',
        'initial',
      ], workingDirectory: consumer.path);
    }
    await File(p.join(consumer.path, 'bin', 'verify.dart'))
        .writeAsString(_consumer);
    await _run(dart, ['analyze'], workingDirectory: consumer.path);
    final build = p.join(consumer.path, 'build');
    await _run(dart, [
      'build',
      'cli',
      '--target',
      'bin/verify.dart',
      '--output',
      build,
    ], workingDirectory: consumer.path);
    final executable = Directory(p.join(build, 'bundle', 'bin'))
        .listSync()
        .whereType<File>()
        .single
        .path;
    stdout.write(
      await _run(executable, const [], workingDirectory: consumer.path),
    );
    stdout.writeln(
      'Verified ORM $version from the supplied archive in an independent consumer.',
    );
  } finally {
    await directory.delete(recursive: true);
  }
}

Future<String> _run(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  if (result.exitCode != 0) {
    throw StateError(
      '$executable ${arguments.join(' ')} failed (${result.exitCode}):\n${result.stdout}\n${result.stderr}',
    );
  }
  return result.stdout as String;
}

const _consumer = r'''
import 'dart:io';
import 'dart:typed_data';
import 'package:orm/database.dart';
import 'package:orm/migration.dart';
import 'package:orm/postgres.dart';
import 'package:orm/query.dart';
import 'package:orm/sqlite.dart';
import '../lib/models.dart';
import '../lib/models.db.dart';
import '../lib/shop.dart';
import '../lib/migrations/sqlite.dart' as sqlite;
import '../lib/migrations/postgresql.dart' as postgres;

Future<void> main() async {
  await verify(SqliteDriver.memory(), sqlite.migration);
  final environment = Platform.environment;
  final socket = environment['ORM_TEST_POSTGRES_SOCKET'];
  final schema = 'orm_package_${pid}_${DateTime.now().microsecondsSinceEpoch}_"Case';
  final driver = PostgresDriver(
    Endpoint(
      host: socket ?? environment['ORM_TEST_POSTGRES_HOST']!,
      port: int.parse(environment['ORM_TEST_POSTGRES_PORT'] ?? '5432'),
      database: environment['ORM_TEST_POSTGRES_DATABASE'] ?? 'postgres',
      username: environment['ORM_TEST_POSTGRES_USER'] ?? 'orm_test',
      password: environment['ORM_TEST_POSTGRES_PASSWORD'],
      isUnixSocket: socket != null,
    ),
    schema: schema,
    settings: const PoolSettings(sslMode: SslMode.disable, maxConnectionCount: 1, queryMode: .simple),
  );
  try {
    check(driver.schema == schema, 'Configured PostgreSQL schema');
    await driver.withConnection((connection) => connection.run('CREATE SCHEMA ${quoteIdentifier(schema)}', []));
  } catch (_) {
    await driver.close();
    rethrow;
  }
  await verify(SchemaDriver(driver, schema), postgres.migration);
}

Future<void> verify(Driver driver, Migration initial) async {
  final events = <DatabaseEvent>[];
  final db = AppDatabase(driver, onEvent: events.add);
  try {
    check(db.database.session.schema == driver.schema, 'Fixed session schema');
    final history = MigrationHistory(engine: driver.engine, migrations: [initial]);
    final runner = MigrationRunner(db.database, history);
    check((await runner.apply()).single == 1, 'Initial migration');
    check((await runner.apply()).isEmpty, 'History resumes');
    final seeded = await db.transaction((tx) async {
      final user = await tx.users.create(username: 'consumer', age: 28);
      final post = await tx.posts.create(authorId: user.id, title: 'Packaged ORM');
      final product = await tx.products.create(sku: 'book', name: 'Dart book', priceCents: 4900, stock: 10);
      return (user: user, post: post, product: product);
    });
    events.clear();
    await db.users.update(seeded.user.id, nickname: 'Seven');
    check(events.length == 1 && events.single.kind == 'statement' && events.single.sql.contains('${quoteIdentifier(driver.schema)}."users"'), 'One typed statement in the fixed schema');
    await db.users.update(seeded.user.id, nickname: null);
    check((await db.users.get(seeded.user.id))!.nickname == null, 'Nullable patch');
    final bytes = Uint8List.fromList([0, 255]);
    final pendingBytes = db.users.update(seeded.user.id, avatar: bytes);
    bytes[0] = 42;
    check((await pendingBytes)!.avatar![0] == 0, 'Root write captures binary parameters');
    bytes[0] = 0;
    final binaryEquality = db.users.where(avatar: eq(bytes));
    final binaryMembership = db.users.where(avatar: oneOf([bytes]));
    bytes[0] = 42;
    check((await binaryEquality.get(seeded.user.id)) != null && (await binaryMembership.get(seeded.user.id)) != null, 'Filters capture immutable binary values');
    await db.transaction((tx) async {
      final patch = Uint8List.fromList([1, 255]);
      final pending = tx.users.update(seeded.user.id, avatar: patch);
      patch[0] = 42;
      check((await pending)!.avatar![0] == 1, 'Transaction write captures binary parameters');
    });
    final ({List<UserCard> users, int total}) page = await searchUsers(db, 'con');
    check(page.users.single.username == 'consumer' && page.total == 1, 'Typed page and count');
    await db.users.update(seeded.user.id, nickname: 'Alias%_!');
    events.clear();
    final aliases = await searchUsers(db, 'Alias%_!');
    check(aliases.users.single.id == seeded.user.id && aliases.total == 1, 'Typed cross-field literal-prefix page');
    final searchStatements = events.where((event) => event.kind == 'statement' && event.sql.startsWith('SELECT')).toList();
    check(searchStatements.length == 2 && searchStatements.every((event) => event.sql.startsWith('SELECT')), 'Two snapshot-consistent search statements');
    check(searchStatements.first.rows == 1 && searchStatements.first.sql.contains('COUNT(*)') && !searchStatements.first.sql.contains('"avatar"'), 'One-cell count without model fields');
    final beyond = await searchUsers(db, 'Alias%_!', offset: 10, limit: 1);
    check(beyond.users.isEmpty && beyond.total == 1, 'Empty page retains filtered total');
    await db.users.update(seeded.user.id, nickname: null);
    events.clear();
    final related = await usersWithPosts(db);
    check(related.single.posts.single.title == 'Packaged ORM', 'Related projection');
    check(events.where((event) => event.kind == 'statement' && event.sql.startsWith('SELECT')).length == 2, 'Two relationship queries');
    final items = [(productId: seeded.product.id, quantity: 2)];
    final receipt = await checkout(db, userId: seeded.user.id, requestKey: 'package', items: items);
    final replay = await checkout(db, userId: seeded.user.id, requestKey: 'package', items: items);
    check(receipt.order.totalCents == 9800 && replay.order.id == receipt.order.id && replay.replayed, 'Idempotent checkout');
    check((await db.products.get(seeded.product.id))!.stock == 8, 'One stock debit');
    final backend = driver.engine == Engine.postgresql
        ? (await db.session.run('SELECT pg_backend_pid()')).rows.single.single
        : null;
    var failed = false;
    try {
      await checkout(db, userId: seeded.user.id, requestKey: 'sold-out', items: [(productId: seeded.product.id, quantity: 99)]);
    } on StateError { failed = true; }
    check(failed && (await db.orders.all()).length == 1 && (await db.products.get(seeded.product.id))!.stock == 8, 'Failed checkout rolls back');
    if (backend != null) {
      check((await db.session.run('SELECT pg_backend_pid()')).rows.single.single == backend, 'Successful business rollback reuses the PostgreSQL connection');
    }
    final users = await db.transaction((tx) => tx.users.stream(fetchSize: 1).toList(), readOnly: true);
    check(users.single.username == 'consumer', 'Bounded typed stream');
    check(await db.posts.delete(seeded.post.id) == 1, 'Typed delete count');
    check(await db.posts.get(seeded.post.id) == null, 'Typed delete persists');
    print('${driver.engine.name}: migration, typed CRUD, relationships, checkout and rollback passed.');
  } finally { await db.close(); }
}

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

final class SchemaDriver implements Driver {
  SchemaDriver(this.driver, this.schema);
  final Driver driver;
  @override
  final String schema;
  @override Engine get engine => driver.engine;
  @override Capabilities get capabilities => driver.capabilities;
  @override Future<T> withConnection<T>(Future<T> Function(Connection) action) => driver.withConnection(action);
  @override Future<void> close() async {
    try {
      await driver.withConnection((connection) => connection.run('DROP SCHEMA ${quoteIdentifier(schema)} CASCADE', []));
    } finally { await driver.close(); }
  }
}
''';
