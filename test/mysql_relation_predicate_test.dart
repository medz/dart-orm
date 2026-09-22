@Tags(['mysql-suite'])
library;

import 'dart:io';

import 'package:orm/mysql.dart';
import 'package:orm/mariadb.dart';
import 'package:test/test.dart';

import 'support/relation_predicates.dart';

void main() {
  for (final engine in ['mysql', 'mariadb']) {
    final variable = 'ORM_TEST_${engine.toUpperCase()}';
    final address = Platform.environment[variable];
    final tls = MysqlTls.values.byName(
      Platform.environment['${variable}_TLS'] ?? 'verifyFull',
    );
    Future<Database<Backend>> open(
      Uri url, {
      void Function(QueryEvent)? observe,
    }) => engine == 'mysql'
        ? mysql(
            MysqlOptions(url: url, tls: tls),
            onQuery: observe,
          )
        : mariadb(
            MariadbOptions(url: url, tls: tls),
            onQuery: observe,
          );
    relationPredicateTests(
      engine,
      (observe) async {
        final url = Uri.parse(address!);
        final admin = await open(url);
        try {
          await admin.execute(
            SqlCommand('DROP DATABASE IF EXISTS orm_relation_predicate_tests'),
          );
          await admin.execute(
            SqlCommand('CREATE DATABASE orm_relation_predicate_tests'),
          );
        } finally {
          await admin.close();
        }
        return open(
          url.replace(path: '/orm_relation_predicate_tests'),
          observe: observe,
        );
      },
      skip: address == null
          ? 'Set $variable to run $engine relationship predicates.'
          : null,
    );
  }
}
