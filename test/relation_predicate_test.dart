@Tags(['database'])
library;

import 'dart:io';

import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import 'support/relation_predicates.dart';

void main() {
  relationPredicateTests(
    'sqlite',
    (observe) => sqlite(const SqliteOptions.memory(), onQuery: observe),
  );
  final address = Platform.environment['ORM_TEST_POSTGRES'];
  relationPredicateTests(
    'postgres',
    (observe) async {
      final db = postgres(
        PostgresOptions(
          url: Uri.parse(address!),
          tls: .disable,
          schema: 'orm_relation_predicate_tests',
        ),
        onQuery: observe,
      );
      await db.execute(
        SqlCommand(
          'DROP SCHEMA IF EXISTS orm_relation_predicate_tests CASCADE',
        ),
      );
      await db.execute(
        SqlCommand('CREATE SCHEMA orm_relation_predicate_tests'),
      );
      return db;
    },
    skip: address == null
        ? 'Set ORM_TEST_POSTGRES to run PostgreSQL relationship predicates.'
        : null,
  );
}
