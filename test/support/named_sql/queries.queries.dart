// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';

Expr<T> _bindSqlParameter<T>(T input, Codec<T> codec) => value(input, codec);
final class AuthorStats({
  required final String author,
  required final int postCount,
  required final int points,
});
final _sqlColumnAuthorStats_0 = Column<String>(
  "author",
  Codecs.text,
  nullable: false,
);
final _sqlColumnAuthorStats_1 = Column<int>(
  "post_count",
  Codecs.integer,
  nullable: false,
);
final _sqlColumnAuthorStats_2 = Column<int>(
  "points",
  Codecs.integer,
  nullable: false,
);

final class AuthorStatsFields extends Fields {
  AuthorStatsFields(super.table);
  late final author = column(_sqlColumnAuthorStats_0);
  late final postCount = column(_sqlColumnAuthorStats_1);
  late final points = column(_sqlColumnAuthorStats_2);
}

final _sqlDefinitionAuthorStats =
    SqlQueryDefinition<AuthorStats, AuthorStatsFields>(
      Table(
        TableSchema(
          "_orm_sql_author_stats",
          columns: [
            _sqlColumnAuthorStats_0,
            _sqlColumnAuthorStats_1,
            _sqlColumnAuthorStats_2,
          ],
        ),
        AuthorStatsFields.new,
        (row) => (row.author, row.postCount, row.points).map(
          (v0, v1, v2) => AuthorStats(author: v0, postCount: v1, points: v2),
        ),
      ),
      {
        SqlDialect.sqlite: SqlTemplate(
          "-- :not_a_parameter; fixed query with explicit result aliases\nSELECT author, COUNT(*) AS post_count, SUM(points) AS points\nFROM posts\nWHERE points >= :minimum AND (:author IS NULL OR author = :author)\nGROUP BY author;\n",
          dialect: SqlDialect.sqlite,
        ),
        SqlDialect.postgres: SqlTemplate(
          "-- :not_a_parameter; fixed query with explicit result aliases\nSELECT author, COUNT(*) AS post_count, SUM(points)::bigint AS points\nFROM posts\nWHERE points >= :minimum AND (:author IS NULL OR author = :author)\nGROUP BY author;\n",
          dialect: SqlDialect.postgres,
        ),
      },
    );

extension AuthorStatsSql on QueryContext {
  Query<AuthorStats, AuthorStatsFields> authorStats({
    required int minimum,
    String? author,
  }) => _sqlDefinitionAuthorStats.bind(this, {
    "minimum": _bindSqlParameter(minimum, Codecs.integer),
    "author": _bindSqlParameter(author, Codecs.text.nullable()),
  });
}

final class Echo({
  required final String value,
  required final DateTime at,
  required final Decimal amount,
  required final LocalDate day,
});
final _sqlColumnEcho_0 = Column<String>("value", Codecs.text, nullable: false);
final _sqlColumnEcho_1 = Column<DateTime>(
  "at",
  Codecs.dateTime,
  nullable: false,
);
final _sqlColumnEcho_2 = Column<Decimal>(
  "amount",
  Codecs.decimal,
  nullable: false,
);
final _sqlColumnEcho_3 = Column<LocalDate>("day", Codecs.date, nullable: false);

final class EchoFields extends Fields {
  EchoFields(super.table);
  late final value = column(_sqlColumnEcho_0);
  late final at = column(_sqlColumnEcho_1);
  late final amount = column(_sqlColumnEcho_2);
  late final day = column(_sqlColumnEcho_3);
}

final _sqlDefinitionEcho = SqlQueryDefinition<Echo, EchoFields>(
  Table(
    TableSchema(
      "_orm_sql_echo",
      columns: [
        _sqlColumnEcho_0,
        _sqlColumnEcho_1,
        _sqlColumnEcho_2,
        _sqlColumnEcho_3,
      ],
    ),
    EchoFields.new,
    (row) => (
      row.value,
      row.at,
      row.amount,
      row.day,
    ).map((v0, v1, v2, v3) => Echo(value: v0, at: v1, amount: v2, day: v3)),
  ),
  {
    SqlDialect.sqlite: SqlTemplate(
      "SELECT :value AS value, :at AS at, :amount AS amount, :day AS day\n",
      dialect: SqlDialect.sqlite,
    ),
    SqlDialect.postgres: SqlTemplate(
      "SELECT :value AS value, :at AS at, :amount AS amount, :day AS day\n",
      dialect: SqlDialect.postgres,
    ),
  },
);

extension EchoSql on QueryContext {
  Query<Echo, EchoFields> echo({
    required String value,
    required DateTime at,
    required Decimal amount,
    required LocalDate day,
  }) => _sqlDefinitionEcho.bind(this, {
    "value": _bindSqlParameter(value, Codecs.text),
    "at": _bindSqlParameter(at, Codecs.dateTime),
    "amount": _bindSqlParameter(amount, Codecs.decimal),
    "day": _bindSqlParameter(day, Codecs.date),
  });
}

final class Constant({required final int n});
final _sqlColumnConstant_0 = Column<int>("n", Codecs.integer, nullable: false);

final class ConstantFields extends Fields {
  ConstantFields(super.table);
  late final n = column(_sqlColumnConstant_0);
}

final _sqlDefinitionConstant = SqlQueryDefinition<Constant, ConstantFields>(
  Table(
    TableSchema("_orm_sql_constant", columns: [_sqlColumnConstant_0]),
    ConstantFields.new,
    (row) => row.n.map((value) => Constant(n: value)),
  ),
  {
    SqlDialect.sqlite: SqlTemplate(
      "SELECT 42 AS n\n",
      dialect: SqlDialect.sqlite,
    ),
    SqlDialect.postgres: SqlTemplate(
      "SELECT 42 AS n\n",
      dialect: SqlDialect.postgres,
    ),
  },
);

extension ConstantSql on QueryContext {
  Query<Constant, ConstantFields> constant() =>
      _sqlDefinitionConstant.bind(this, {});
}

final class PostgresOnly({required final int n});
final _sqlColumnPostgresOnly_0 = Column<int>(
  "n",
  Codecs.integer,
  nullable: false,
);

final class PostgresOnlyFields extends Fields {
  PostgresOnlyFields(super.table);
  late final n = column(_sqlColumnPostgresOnly_0);
}

final _sqlDefinitionPostgresOnly =
    SqlQueryDefinition<PostgresOnly, PostgresOnlyFields>(
      Table(
        TableSchema(
          "_orm_sql_postgres_only",
          columns: [_sqlColumnPostgresOnly_0],
        ),
        PostgresOnlyFields.new,
        (row) => row.n.map((value) => PostgresOnly(n: value)),
      ),
      {
        SqlDialect.postgres: SqlTemplate(
          "SELECT 42 AS n\n",
          dialect: SqlDialect.postgres,
        ),
      },
    );

extension PostgresOnlySql on QueryContext {
  Query<PostgresOnly, PostgresOnlyFields> postgresOnly() =>
      _sqlDefinitionPostgresOnly.bind(this, {});
}
