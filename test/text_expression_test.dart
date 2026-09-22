@Tags(['database'])
library;

import 'dart:io';

import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import 'support/text_expressions.dart';

void main() {
  textExpressionTests('sqlite', () => sqlite(const SqliteOptions.memory()));
  final address = Platform.environment['ORM_TEST_POSTGRES'];
  textExpressionTests(
    'postgres',
    () async => postgres(
      PostgresOptions(url: Uri.parse(address!), tls: PostgresTls.disable),
    ),
    skip: address == null
        ? 'Set ORM_TEST_POSTGRES for live database validation.'
        : false,
  );
}
