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
    for (final violation in [
      (unique: true, code: '23505', sqliteCode: SqlExtendedError.SQLITE_CONSTRAINT_UNIQUE),
      (unique: false, code: '23503', sqliteCode: SqlExtendedError.SQLITE_CONSTRAINT_FOREIGNKEY),
    ]) {
      events.clear();
      var caught = false;
      try {
        await db.transaction((tx) async {
          await tx.users.update(seeded.user.id, age: 99);
          if (violation.unique) {
            await tx.users.create(username: 'consumer', age: 30);
          } else {
            await tx.posts.create(authorId: seeded.user.id + 1000, title: 'Missing author');
          }
        });
        throw StateError('Expected a native constraint failure');
      } on ServerException catch (error) {
        caught = true;
        final PgException native = error;
        final Severity severity = native.severity;
        check(driver.engine == Engine.postgresql && severity == Severity.error, 'Public PostgreSQL failure type');
        check(error.code == violation.code && error.schemaName == driver.schema, 'Native SQLSTATE and schema');
        check(violation.unique ? error is UniqueViolationException : error is ForeignKeyViolationException, 'Public PostgreSQL constraint subclass');
      } on SqliteException catch (error) {
        caught = true;
        check(driver.engine == Engine.sqlite && error.resultCode == SqlError.SQLITE_CONSTRAINT, 'Public SQLite failure type');
        check(error.extendedResultCode == violation.sqliteCode, 'Native SQLite constraint code');
      }
      check(caught && events.where((event) => event.kind == 'rollback').length == 1, 'Constraint failure rolls back');
      final unchanged = (await db.users.get(seeded.user.id))!;
      check(unchanged.username == 'consumer' && unchanged.age == 28, 'Earlier write rolls back');
      check(await db.users.count() == 1 && await db.posts.count() == 1, 'Original rows and next root query survive');
    }
    if (driver.engine == Engine.postgresql) {
      final parent = '${quoteIdentifier(driver.schema)}."users"';
      final child = '${quoteIdentifier(driver.schema)}."unmanaged_users_child"';
      final probe = '${quoteIdentifier(driver.schema)}."ownership_pending_probe"';
      final extra = await db.users.create(username: 'ownership parent', age: 20);
      await db.session.run('CREATE TABLE $child () INHERITS ($parent)');
      await db.session.run('INSERT INTO $child ("id", "username", "age") VALUES (\$1, \$2, \$3), (\$4, \$2, \$3)', parameters: [extra.id, 'unmanaged child', 91, extra.id + 1000]);
      check((await db.users.get(extra.id))!.username == 'ownership parent', 'Typed get owns the physical parent');
      check(await db.users.count() == 2 && await db.users.limit(10).count() == 2, 'Unpaged and paged counts own the physical parent');
      check((await db.users.update(extra.id, username: 'changed parent', age: 41))!.age == 41, 'Typed update owns the physical parent');
      check((await db.users.increment(extra.id, age: 1))!.age == 42, 'Atomic arithmetic owns the physical parent');
      final physical = await db.transaction((tx) => tx.users.stream(fetchSize: 1).toList(), readOnly: true);
      check(physical.length == 2 && physical.singleWhere((row) => row.id == extra.id).username == 'changed parent', 'Typed stream excludes inherited rows');
      check(await db.users.delete(extra.id) == 1 && await db.users.get(extra.id) == null, 'Typed delete owns the physical parent');
      final retained = (await db.session.run('SELECT "id", "username", "age" FROM $child ORDER BY "id"')).rows;
      check(retained.length == 2 && retained.first[0] == extra.id && retained.last[0] == extra.id + 1000 && retained.every((row) => row[1] == 'unmanaged child' && row[2] == 91), 'Inherited rows remain unchanged');
      final steps = ['CREATE TABLE $probe ("id" BIGINT PRIMARY KEY NOT NULL)'];
      final pending = Migration(
        version: 2, name: 'ownership probe', engine: driver.engine, steps: steps, snapshot: initial.snapshot,
        reviewedFingerprint: migrationFingerprint(version: 2, name: 'ownership probe', engine: driver.engine, steps: steps, snapshot: initial.snapshot),
      );
      events.clear();
      var rejected = false;
      try {
        await MigrationRunner(db.database, MigrationHistory(engine: driver.engine, migrations: [initial, pending])).apply();
      } on StateError { rejected = true; }
      check(rejected && !events.any((event) => event.sql == steps.single), 'Inheritance rejected before pending DDL');
      check((await db.session.run('SELECT to_regclass(\$1)', parameters: [probe])).rows.single.single == null, 'Pending table was not created');
      await db.session.run('DROP TABLE $child');
      check((await runner.apply()).isEmpty, 'Migration history resumes after inheritance repair');
      check(await db.users.count() == 1 && await db.posts.count() == 1, 'Original seed survives physical ownership checks');
    }
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
