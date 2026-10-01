@Tags(['core'])
library;

import 'package:orm/src/migrate/catalog.dart' show isNullDefault;
import 'package:test/test.dart';

void main() {
  test('recognizes only NULL literals and built-in casts of NULL', () {
    for (final sql in [
      'NULL',
      ' ((null)) ',
      'NULL::smallint',
      '(NULL)::integer',
      'NULL::bigint',
      'NULL::boolean',
      'NULL::text',
      'NULL::bytea',
      'NULL::jsonb',
      'NULL::numeric(12, 2)',
      'NULL::time(3) without time zone',
      'NULL::timestamp(3) with time zone',
      'CAST((NULL) AS SIGNED INTEGER)',
      'CAST(NULL AS CHAR(10))',
      'CAST(NULL AS DECIMAL(12, 2))',
      'CAST(CAST(NULL AS TEXT) AS INTEGER)',
      '(NULL::pg_catalog.int8)::numeric',
    ]) {
      expect(isNullDefault(sql), true, reason: sql);
    }
  });

  test('keeps strings, values, functions and domain casts distinct', () {
    for (final sql in [
      "'NULL'",
      "'NULL'::text",
      '7',
      'CAST(7 AS INTEGER)',
      'COALESCE(NULL, 7)',
      'NULLIF(7, 7)',
      'NULL::app.not_null_domain',
      'CAST(NULL AS app.not_null_domain)',
      'NULL::integer + 7',
      "CAST('NULL' AS CHAR)",
    ]) {
      expect(isNullDefault(sql), false, reason: sql);
    }
    expect(isNullDefault(null), false);
  });
}
