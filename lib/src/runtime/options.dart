part of '../../runtime.dart';

sealed class TransactionOptions<B extends Backend> {
  const TransactionOptions();
  SqlDialect get dialect;
  List<String> get beginCommands;
}

enum Isolation { readCommitted, repeatableRead, serializable }

String _isolationSql(Isolation isolation) => switch (isolation) {
  Isolation.readCommitted => 'READ COMMITTED',
  Isolation.repeatableRead => 'REPEATABLE READ',
  Isolation.serializable => 'SERIALIZABLE',
};

final class PostgresTransaction extends TransactionOptions<Postgres> {
  final Isolation isolation;
  final bool readOnly;
  const PostgresTransaction({
    this.isolation = Isolation.readCommitted,
    this.readOnly = false,
  });
  @override
  SqlDialect get dialect => SqlDialect.postgres;
  @override
  List<String> get beginCommands => [
    'BEGIN ISOLATION LEVEL ${_isolationSql(isolation)} ${readOnly ? 'READ ONLY' : 'READ WRITE'}',
  ];
}

enum SqliteTransactionMode { deferred, immediate, exclusive }

final class SqliteTransaction extends TransactionOptions<Sqlite> {
  final SqliteTransactionMode mode;
  const SqliteTransaction({this.mode = SqliteTransactionMode.deferred});
  @override
  SqlDialect get dialect => SqlDialect.sqlite;
  @override
  List<String> get beginCommands => ['BEGIN ${mode.name.toUpperCase()}'];
}

final class MysqlTransaction extends TransactionOptions<Mysql> {
  final Isolation isolation;
  final bool readOnly;
  const MysqlTransaction({
    this.isolation = Isolation.repeatableRead,
    this.readOnly = false,
  });
  @override
  SqlDialect get dialect => SqlDialect.mysql;
  @override
  List<String> get beginCommands => _mysqlBegin(isolation, readOnly);
}

final class MariadbTransaction extends TransactionOptions<Mariadb> {
  final Isolation isolation;
  final bool readOnly;
  const MariadbTransaction({
    this.isolation = Isolation.repeatableRead,
    this.readOnly = false,
  });
  @override
  SqlDialect get dialect => SqlDialect.mariadb;
  @override
  List<String> get beginCommands => _mysqlBegin(isolation, readOnly);
}

List<String> _mysqlBegin(Isolation isolation, bool readOnly) => [
  'SET TRANSACTION ISOLATION LEVEL ${_isolationSql(isolation)}',
  'START TRANSACTION ${readOnly ? 'READ ONLY' : 'READ WRITE'}',
];
