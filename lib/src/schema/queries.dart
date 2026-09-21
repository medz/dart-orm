/// A fixed SQL file with named result and parameter column declarations.
///
/// Use the same column helpers as a model, such as `text()` and `custom(codec)`.
/// Generation creates the result class and a typed query method. Source paths
/// are relative to this library. Creating a declaration never reads or runs SQL.
/// Run query generation, then validate the SQL against each target database.
SqlDeclaration sqlQuery({
  required Record result,
  Record parameters = (),
  String? sqlite,
  String? postgres,
  String? mysql,
  String? mariadb,
}) => SqlDeclaration._(result, parameters, sqlite, postgres, mysql, mariadb);

/// Source metadata for a typed SQL query, created through [sqlQuery].
final class SqlDeclaration {
  /// Named result columns, interpreted by static generation.
  final Record result;

  /// Named parameter columns, or an empty Record for no parameters.
  final Record parameters;

  /// SQLite SQL file, relative to the declaring Dart library.
  final String? sqlite;

  /// PostgreSQL SQL file, relative to the declaring Dart library.
  final String? postgres;

  /// MySQL SQL file, relative to the declaring Dart library.
  final String? mysql;

  /// MariaDB SQL file, relative to the declaring Dart library.
  final String? mariadb;

  const SqlDeclaration._(
    this.result,
    this.parameters,
    this.sqlite,
    this.postgres,
    this.mysql,
    this.mariadb,
  );
}
