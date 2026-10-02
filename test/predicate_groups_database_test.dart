@Tags(['database'])
library;

import 'package:orm/orm.dart';

import 'dart:io';

import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import 'support/predicate_groups.dart';

void main() {
  group('sqlite predicate groups', () {
    predicateGroupTests(
      () =>
          sqlite(const SqliteOptions.memory())
              .then((sql) => Database.fromSql(sql)),
    );
  }, tags: 'sqlite');
  final address = Platform.environment['ORM_TEST_POSTGRES'];
  group(
    'postgres predicate groups',
    () {
      predicateGroupTests(
        () async => Database.fromSql(
          postgres(
            PostgresOptions(url: Uri.parse(address!), tls: PostgresTls.disable),
          ),
        ),
      );
    },
    tags: 'postgres',
    skip: address == null ? 'Set ORM_TEST_POSTGRES.' : false,
  );
}
