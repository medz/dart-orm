@Tags(['mysql-suite'])
library;

import 'dart:io';

import 'package:orm/mariadb.dart';
import 'package:orm/mysql.dart';
import 'package:test/test.dart';

import 'support/text_expressions.dart';

void main() {
  for (final engine in ['mysql', 'mariadb']) {
    final variable = 'ORM_TEST_${engine.toUpperCase()}';
    final address = Platform.environment[variable];
    final tls = MysqlTls.values.byName(
      Platform.environment['${variable}_TLS'] ?? 'verifyFull',
    );
    textExpressionTests(
      engine,
      () async => engine == 'mysql'
          ? await mysql(MysqlOptions(url: Uri.parse(address!), tls: tls))
          : await mariadb(MariadbOptions(url: Uri.parse(address!), tls: tls)),
      skip: address == null
          ? 'Set $variable for live database validation.'
          : false,
    );
  }
}
