import 'dart:io';

import 'package:orm/database.dart';
import 'package:orm/migration.dart';
import 'package:orm/postgres.dart';
import 'package:orm/query.dart';
import 'package:orm/sqlite.dart';

import '../../example/migrations/postgres/history.dart' as postgres;
import '../../example/migrations/sqlite/history.dart' as sqlite;
import '../../example/models.db.dart';

bool get hasPostgres =>
    Platform.environment.containsKey('ORM_TEST_POSTGRES_SOCKET') ||
    Platform.environment.containsKey('ORM_TEST_POSTGRES_HOST');

final class TestDatabase {
  TestDatabase(this.db, this.events);
  final AppDatabase db;
  final List<DatabaseEvent> events;
  List<DatabaseEvent> get statements =>
      events.where((event) => event.kind == 'statement').toList();
}

Future<TestDatabase> openTestDatabase(Engine engine) async {
  final events = <DatabaseEvent>[];
  final Driver driver;
  if (engine == Engine.sqlite) {
    driver = SqliteDriver.memory();
  } else {
    final environment = Platform.environment;
    final socket = environment['ORM_TEST_POSTGRES_SOCKET'];
    final native = PostgresDriver(
      Endpoint(
        host: socket ?? environment['ORM_TEST_POSTGRES_HOST']!,
        port: int.parse(environment['ORM_TEST_POSTGRES_PORT'] ?? '5432'),
        database: environment['ORM_TEST_POSTGRES_DATABASE'] ?? 'postgres',
        username: environment['ORM_TEST_POSTGRES_USER'] ?? 'orm_test',
        password: environment['ORM_TEST_POSTGRES_PASSWORD'],
        isUnixSocket: socket != null,
      ),
      settings: const PoolSettings(
        sslMode: SslMode.disable,
        maxConnectionCount: 4,
      ),
    );
    final schema =
        'orm_business_${pid}_${DateTime.now().microsecondsSinceEpoch}';
    await native.withConnection(
      (connection) =>
          connection.run('CREATE SCHEMA ${quoteIdentifier(schema)}', []),
    );
    driver = _SchemaDriver(native, schema);
  }
  final db = AppDatabase(driver, onEvent: events.add);
  try {
    await MigrationRunner(
      db.database,
      engine == Engine.sqlite ? sqlite.history : postgres.history,
    ).apply();
  } catch (_) {
    await db.close();
    rethrow;
  }
  events.clear();
  return TestDatabase(db, events);
}

/// Isolates every pooled connection in a disposable test schema.
final class _SchemaDriver implements Driver {
  _SchemaDriver(this.driver, this.schema);
  final Driver driver;
  @override
  final String schema;
  @override
  Engine get engine => driver.engine;
  @override
  Capabilities get capabilities => driver.capabilities;
  @override
  Future<T> withConnection<T>(Future<T> Function(Connection) action) =>
      driver.withConnection((connection) async {
        await connection.run(
          'SET search_path TO ${quoteIdentifier(schema)}',
          [],
        );
        return action(connection);
      });
  @override
  Future<void> close() async {
    try {
      await driver.withConnection(
        (connection) => connection.run(
          'DROP SCHEMA ${quoteIdentifier(schema)} CASCADE',
          [],
        ),
      );
    } finally {
      await driver.close();
    }
  }
}
