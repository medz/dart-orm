@Tags(['database'])
library;

import 'package:orm/driver.dart';
import 'package:orm/orm.dart';

import 'dart:io';

import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import 'support/null_defaults.dart';

void main() {
  test('SQLite NULL defaults survive apply and verify', () async {
    final db = Database.fromSql(await sqlite(const SqliteOptions.memory()));
    try {
      await checkNullDefaults(db.sql);
    } finally {
      await db.close();
    }
  }, tags: 'sqlite');

  final url = Platform.environment['ORM_TEST_POSTGRES'];
  test(
    'PostgreSQL NULL defaults survive apply and verify',
    () async {
      final namespace =
          'orm_null_defaults_${pid}_${DateTime.now().microsecondsSinceEpoch}';
      final admin = Database.fromSql(
        postgres(PostgresOptions(url: Uri.parse(url!), tls: .disable)),
      );
      var created = false;
      try {
        await admin.execute(SqlCommand('CREATE SCHEMA "$namespace"'));
        created = true;
        final db = Database.fromSql(
          postgres(
            PostgresOptions(
              url: Uri.parse(url),
              tls: .disable,
              schema: namespace,
            ),
          ),
        );
        try {
          await checkNullDefaults(db.sql);
        } finally {
          await db.close();
        }
      } finally {
        if (created) {
          await admin.execute(SqlCommand('DROP SCHEMA "$namespace" CASCADE'));
        }
        await admin.close();
      }
    },
    tags: 'postgres',
    skip: url == null ? 'ORM_TEST_POSTGRES is not set' : false,
  );
}
