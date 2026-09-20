import 'package:meta/meta.dart' show internal;

import '../../driver.dart';

/// Engine-specific settings applied before a transaction callback starts.
///
/// The backend type prevents passing one engine's settings to another engine's
/// typed database. Runtime validation also checks the selected dialect.
///
/// {@category Execution}
sealed class TransactionOptions<B extends Backend> {
  /// Creates typed transaction settings without starting a transaction.
  const TransactionOptions();

  /// Engine these transaction settings are valid for.
  SqlDialect get dialect;

  /// @nodoc
  @internal
  List<String> get beginCommands;
}

/// Requested transaction isolation; exact visibility rules belong to the engine.
enum Isolation {
  /// Reads committed data according to the engine's per-statement semantics.
  readCommitted,

  /// Uses the engine's repeatable-read semantics across the transaction.
  repeatableRead,

  /// Requests serializable execution; conflicting work may require a retry.
  serializable,
}

String _isolationSql(Isolation isolation) => switch (isolation) {
  Isolation.readCommitted => 'READ COMMITTED',
  Isolation.repeatableRead => 'REPEATABLE READ',
  Isolation.serializable => 'SERIALIZABLE',
};

/// PostgreSQL isolation and read-only settings for one transaction.
final class PostgresTransaction extends TransactionOptions<Postgres> {
  /// Requested PostgreSQL isolation; defaults to read committed.
  final Isolation isolation;

  /// Whether PostgreSQL should reject writes in this transaction.
  final bool readOnly;

  /// Creates PostgreSQL settings applied by the transaction BEGIN statement.
  const PostgresTransaction({
    this.isolation = Isolation.readCommitted,
    this.readOnly = false,
  });
  @override
  SqlDialect get dialect => SqlDialect.postgres;

  /// @nodoc
  @internal
  @override
  List<String> get beginCommands => [
    'BEGIN ISOLATION LEVEL ${_isolationSql(isolation)} ${readOnly ? 'READ ONLY' : 'READ WRITE'}',
  ];
}

/// When SQLite acquires its transaction locks.
enum SqliteTransactionMode {
  /// Defers lock acquisition until the first read or write.
  deferred,

  /// Attempts to reserve write access as the transaction begins.
  immediate,

  /// Requests exclusive access; blocking behavior depends on the journal mode.
  exclusive,
}

/// SQLite BEGIN mode for an explicit transaction.
final class SqliteTransaction extends TransactionOptions<Sqlite> {
  /// Lock acquisition mode; defaults to SQLite deferred transactions.
  final SqliteTransactionMode mode;

  /// Chooses when SQLite attempts to acquire transaction locks.
  const SqliteTransaction({this.mode = SqliteTransactionMode.deferred});
  @override
  SqlDialect get dialect => SqlDialect.sqlite;

  /// @nodoc
  @internal
  @override
  List<String> get beginCommands => ['BEGIN ${mode.name.toUpperCase()}'];
}

/// MySQL isolation and read-only settings applied to the next transaction.
final class MysqlTransaction extends TransactionOptions<Mysql> {
  /// Requested MySQL isolation; defaults to repeatable read.
  final Isolation isolation;

  /// Whether MySQL should reject writes in this transaction.
  final bool readOnly;

  /// Defaults to repeatable read, independently of prior connection settings.
  const MysqlTransaction({
    this.isolation = Isolation.repeatableRead,
    this.readOnly = false,
  });
  @override
  SqlDialect get dialect => SqlDialect.mysql;

  /// @nodoc
  @internal
  @override
  List<String> get beginCommands => _mysqlBegin(isolation, readOnly);
}

/// MariaDB isolation and read-only settings applied to the next transaction.
final class MariadbTransaction extends TransactionOptions<Mariadb> {
  /// Requested MariaDB isolation; defaults to repeatable read.
  final Isolation isolation;

  /// Whether MariaDB should reject writes in this transaction.
  final bool readOnly;

  /// Defaults to repeatable read, independently of prior connection settings.
  const MariadbTransaction({
    this.isolation = Isolation.repeatableRead,
    this.readOnly = false,
  });
  @override
  SqlDialect get dialect => SqlDialect.mariadb;

  /// @nodoc
  @internal
  @override
  List<String> get beginCommands => _mysqlBegin(isolation, readOnly);
}

List<String> _mysqlBegin(Isolation isolation, bool readOnly) => [
  'SET TRANSACTION ISOLATION LEVEL ${_isolationSql(isolation)}',
  'START TRANSACTION ${readOnly ? 'READ ONLY' : 'READ WRITE'}',
];
