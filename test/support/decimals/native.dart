import 'package:orm/migrate.dart';
import 'package:orm/sqlite.dart';

import 'schema.orm.dart';

Future<void> main() async {
  final db = await sqlite(const SqliteOptions.memory());
  try {
    await Migrator(
      db.sql,
    ).apply([Migration.create('0001_decimal', appSchema, dialect: db.dialect)]);
    final exact = Decimal.parse('9007199254740993.1234567890123456789');
    await db.entries.create(amount: exact, bucket: 'a');
    await db.entries.create(
      amount: Decimal.parse('.0000000000000000001'),
      bucket: 'a',
    );
    if (await db.entries.select((e) => e.amount.sum()).single() !=
        Decimal.parse('9007199254740993.123456789012345679')) {
      throw StateError('Exact sum lost precision');
    }
    final sorted = await db.entries.orderBy((e) => [e.amount.asc()]).get();
    if (sorted.last.amount != exact) throw StateError('Decimal order differs');
    await db.rates.create(id: Decimal.parse('2'), label: 'two');
    await db.execute(
      SqlCommand("INSERT INTO allocations (rate_id) VALUES ('2.000')"),
    );
    final children = await db.rates
        .select((r) => r.allocations.select((a) => a.rateId).many())
        .single();
    if (children.single != Decimal.parse('2')) {
      throw StateError('Decimal relation keys differ');
    }
    final window = await db.entries
        .orderBy((e) => [e.id.asc()])
        .select(
          (e) =>
              e.amount.sum().over(orderBy: [e.id.asc()], frame: .rowsToCurrent),
        )
        .get();
    if (window.last != Decimal.parse('9007199254740993.123456789012345679')) {
      throw StateError('Window sum differs');
    }
    final halves = await db.entries
        .orderBy((e) => [e.id.asc()])
        .select(
          (e) => e.amount
              .sum()
              .over(orderBy: [e.id.asc()], frame: .rowsToCurrent)
              .divide(Decimal.parse('2'), scale: 20, rounding: .halfEven),
        )
        .get();
    if (halves.last != Decimal.parse('4503599627370496.5617283945061728395')) {
      throw StateError('Exact window division differs');
    }
    final rounded = await db.entries
        .orderBy((e) => [e.id.asc()])
        .select((e) => e.amount.rounded(2, rounding: .halfEven))
        .get();
    if (rounded.first != Decimal.parse('9007199254740993.12')) {
      throw StateError('Exact SQL rounding differs');
    }
    final average = await db.entries
        .select((e) => e.amount.average(scale: 20, rounding: .halfEven))
        .single();
    if (average != halves.last) throw StateError('Exact SQL average differs');
    final runningMean = await db.entries
        .orderBy((e) => [e.id.asc()])
        .select(
          (e) => e.amount
              .average(scale: 20, rounding: .halfEven)
              .over(orderBy: [e.id.asc()], frame: .rowsToCurrent),
        )
        .get();
    if (runningMean.first != exact || runningMean.last != average) {
      throw StateError('Exact window average differs');
    }
    final verification = await verifySchema(db.sql, SchemaSnapshot(appSchema));
    if (!verification.matches || verification.unmanaged.isNotEmpty) {
      throw StateError('Decimal catalog differs');
    }
    print(
      'Native AOT: exact decimals, SQL division/rounding/averages, numeric ordering, aggregate/window functions, canonical relation keys and catalog verification passed.',
    );
  } finally {
    await db.close();
  }
}
