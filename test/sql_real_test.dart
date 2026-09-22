@Tags(['database'])
library;

import 'dart:io';

import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

void main() {
  for (final dialect in [SqlDialect.sqlite, SqlDialect.postgres]) {
    test(
      '${dialect.name} explicitly typed REAL parameters preserve floating storage',
      () async {
        final Database<Backend> db = dialect == SqlDialect.sqlite
            ? await sqlite(const SqliteOptions.memory())
            : postgres(
                PostgresOptions(
                  url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
                  tls: PostgresTls.disable,
                ),
              );
        try {
          final result = await db.execute(
            SqlCommand(
              dialect == SqlDialect.sqlite
                  ? 'SELECT typeof(?1), ?1'
                  : r'SELECT pg_typeof($1::float8)::text, $1::float8',
              [const SqlReal(1e20)],
            ),
          );
          expect(result.rows.single, [
            dialect == SqlDialect.sqlite ? 'real' : 'double precision',
            1e20,
          ]);
        } finally {
          await db.close();
        }
      },
      skip:
          dialect == SqlDialect.postgres &&
              Platform.environment['ORM_TEST_POSTGRES'] == null
          ? 'Set ORM_TEST_POSTGRES.'
          : false,
      tags: dialect.name,
    );
  }
}
