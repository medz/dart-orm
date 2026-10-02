@Tags(['database'])
library;

import 'package:orm/orm.dart';

import 'dart:io';

import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import 'support/text_expressions.dart';

void main() {
  textExpressionTests(
    'sqlite',
    () =>
        sqlite(const SqliteOptions.memory())
            .then((sql) => Database.fromSql(sql)),
  );
  final address = Platform.environment['ORM_TEST_POSTGRES'];
  textExpressionTests(
    'postgres',
    () async => Database.fromSql(
      postgres(
        PostgresOptions(url: Uri.parse(address!), tls: PostgresTls.disable),
      ),
    ),
    skip: address == null
        ? 'Set ORM_TEST_POSTGRES for live database validation.'
        : false,
  );
}
