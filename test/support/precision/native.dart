import 'package:orm/migrate.dart';
import 'package:orm/sqlite.dart';

import 'schema.orm.dart';

Future<void> main() async {
  final db = await sqlite(const SqliteOptions.memory());
  try {
    await Migrator(db).apply([
      Migration.create('0001_precision', appSchema, dialect: db.dialect),
    ]);
    final row = await db.wallets.create(
      amount: Decimal.parse('1.235'),
      hundreds: Decimal.parse('-12350'),
      fraction: Decimal.parse('.001235'),
    );
    if (row.amount != Decimal.parse('1.24') ||
        row.hundreds != Decimal.parse('-12400') ||
        row.fraction != Decimal.parse('.00124') ||
        row.defaulted != Decimal.parse('1.24')) {
      throw StateError('Decimal column coercion differs');
    }
    await db.prices.create(id: Decimal.parse('1.234'), label: 'one');
    await db.receipts.create(priceId: Decimal.parse('1.234'));
    if (await db.receipts
            .select((r) => r.price.select((p) => p.label).required())
            .single() !=
        'one') {
      throw StateError('Rounded relation keys differ');
    }
    var rejected = false;
    try {
      await db.prices.create(id: Decimal.parse('99.995'), label: 'overflow');
    } on SqlFailure {
      rejected = true;
    }
    if (!rejected || await db.prices.count() != 1) {
      throw StateError('Precision overflow was not rejected');
    }
    final check = await verifySchema(db, SchemaSnapshot(appSchema));
    if (!check.matches || check.unmanaged.isNotEmpty) {
      throw StateError('Constrained decimal catalog differs');
    }
    print(
      'Native AOT: decimal precision/scale, signed coercion, defaults, relation keys, overflow and catalog checks passed.',
    );
  } finally {
    await db.close();
  }
}
