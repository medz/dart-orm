import 'dart:convert';
import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';

import '../test/support/decimals/schema.orm.dart';

Future<void> main() async {
  final results = <Map<String, Object?>>[];
  final schema = 'orm_decimal_cost_${DateTime.now().microsecondsSinceEpoch}';
  for (final backend in [
    'sqlite',
    if (Platform.environment.containsKey('ORM_TEST_POSTGRES')) 'postgres',
  ]) {
    final Database<Backend> db = backend == 'sqlite'
        ? await sqlite(const SqliteOptions.memory())
        : postgres(
            PostgresOptions(
              url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
              tls: .disable,
              schema: schema,
            ),
          );
    var created = false;
    try {
      if (backend == 'postgres') {
        await db.execute(SqlCommand('CREATE SCHEMA $schema'));
        created = true;
      }
      await Migrator(db.sql).apply([
        Migration.create('0001_decimal', appSchema, dialect: db.dialect),
      ]);
      final version = (await db.execute(
        SqlCommand(
          backend == 'sqlite'
              ? 'SELECT sqlite_version()'
              : "SELECT current_setting('server_version')",
        ),
      )).rows.single.single;
      await db.execute(
        SqlCommand(
          "INSERT INTO entries(amount, bucket) WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<10000) SELECT x, 'a' FROM n",
        ),
      );
      final cases = {
        'read': db.entry.select((e) => e.amount),
        'average_half_even_scale_2': db.entry.select(
          (e) => e.amount.average(scale: 2, rounding: .halfEven),
        ),
        'window_average_half_even_scale_2': db.entry.select(
          (e) => e.amount
              .average(scale: 2, rounding: .halfEven)
              .over(orderBy: [e.id.asc()], frame: .rowsToCurrent),
        ),
        'divide_half_even_scale_2': db.entry.select(
          (e) => e.amount.divide(
            Decimal.parse('3'),
            scale: 2,
            rounding: .halfEven,
          ),
        ),
        'round_half_even_scale_minus_1': db.entry.select(
          (e) => e.amount.rounded(-1, rounding: .halfEven),
        ),
        'window_divide_half_even_scale_2': db.entry.select(
          (e) => e.amount
              .sum()
              .over(orderBy: [e.id.asc()], frame: .rowsToCurrent)
              .divide(Decimal.parse('3'), scale: 2, rounding: .halfEven),
        ),
      };
      for (final entry in cases.entries) {
        final expectedRows = entry.key == 'average_half_even_scale_2'
            ? 1
            : 10000;
        await entry.value.get();
        final samples = <double>[];
        for (var i = 0; i < 3; i++) {
          final timer = Stopwatch()..start();
          final rows = await entry.value.get();
          timer.stop();
          if (rows.length != expectedRows) {
            throw StateError('Incomplete sample');
          }
          samples.add(timer.elapsedMicroseconds / 1000);
        }
        results.add({
          'backend': backend,
          'version': version,
          'case': entry.key,
          'inputRows': 10000,
          'rows': expectedRows,
          'elapsedMs': samples,
          'sqlBytes': entry.value.compile().sql.length,
        });
      }
    } finally {
      try {
        if (created) {
          await db.execute(SqlCommand('DROP SCHEMA $schema CASCADE'));
        }
      } finally {
        await db.close();
      }
    }
  }
  print(
    const JsonEncoder.withIndent('  ').convert({
      'recordedAt': DateTime.now().toUtc().toIso8601String(),
      'dart': Platform.version,
      'os': Platform.operatingSystemVersion,
      'warmupRuns': 1,
      'measuredRuns': 3,
      'scope': 'Single-client end-to-end query fetch and Decimal decoding; 10000 integer-valued rows; not a concurrency or percentile benchmark.',
      'results': results,
    }),
  );
}
