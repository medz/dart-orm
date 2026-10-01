@Tags(['mysql-suite'])
library;

import 'dart:io';

import 'package:orm/drivers/mariadb.dart';
import 'package:orm/drivers/mysql.dart';
import 'package:orm/runtime.dart';
import 'package:test/test.dart';

import 'support/null_defaults.dart';

void main() {
  for (final engine in ['mysql', 'mariadb']) {
    final variable = 'ORM_TEST_${engine.toUpperCase()}';
    final url = Platform.environment[variable];
    final tls = MysqlTls.values.byName(
      Platform.environment['${variable}_TLS'] ?? 'verifyFull',
    );
    test(
      '$engine NULL defaults survive apply and verify',
      () async {
        Future<Driver<Backend>> open(Uri address) async => engine == 'mysql'
            ? await MysqlDriver.open(MysqlOptions(url: address, tls: tls))
            : await MariadbDriver.open(MariadbOptions(url: address, tls: tls));
        final namespace =
            'orm_null_defaults_${pid}_${DateTime.now().microsecondsSinceEpoch}';
        final admin = SqlDatabase(await open(Uri.parse(url!)));
        var created = false;
        try {
          await admin.execute(SqlCommand('CREATE DATABASE "$namespace"'));
          created = true;
          final db = SqlDatabase(
            await open(Uri.parse(url).replace(path: '/$namespace')),
          );
          try {
            await checkNullDefaults(db);
          } finally {
            await db.close();
          }
        } finally {
          if (created) {
            await admin.execute(SqlCommand('DROP DATABASE "$namespace"'));
          }
          await admin.close();
        }
      },
      tags: engine,
      skip: url == null ? '$variable is not set' : false,
    );
  }
}
