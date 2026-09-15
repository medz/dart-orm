part of '../../sqlite.dart';

void _registerDecimals(native.Database db) {
  db.createFunction(
    functionName: 'orm_decimal_div_v1',
    argumentCount: const native.AllowedArgumentCount(4),
    deterministic: true,
    function: (args) => args[0] == null || args[1] == null
        ? null
        : Codecs.decimal
              .decode(args[0])
              .divide(
                Codecs.decimal.decode(args[1]),
                scale: args[2] as int,
                rounding: DecimalRounding.values[args[3] as int],
              )
              .toString(),
  );
  db.createFunction(
    functionName: 'orm_decimal_round_v1',
    argumentCount: const native.AllowedArgumentCount(3),
    deterministic: true,
    function: (args) => args[0] == null
        ? null
        : Codecs.decimal
              .decode(args[0])
              .rounded(
                args[1] as int,
                rounding: DecimalRounding.values[args[2] as int],
              )
              .toString(),
  );
  db.createFunction(
    functionName: 'orm_decimal_cast_v1',
    argumentCount: const native.AllowedArgumentCount(3),
    deterministic: true,
    directOnly: false,
    function: (args) => args[0] == null
        ? null
        : Codecs.decimal
              .decode(args[0])
              .constrained(args[1] as int, args[2] as int)
              .toString(),
  );
  db.createFunction(
    functionName: 'orm_decimal_fits_v1',
    argumentCount: const native.AllowedArgumentCount(3),
    deterministic: true,
    directOnly: false,
    function: (args) =>
        args[0] is String &&
            (Decimal.tryParse(args[0] as String)
                    ?.fits(args[1] as int, args[2] as int) ??
                false)
        ? 1
        : 0,
  );
  db.createCollation(
    name: 'orm_decimal_v1',
    function: (a, b) {
      // SQLite collation callbacks cannot signal a SQL error. Invalid external
      // text gets a deterministic total order after valid decimals; typed reads
      // and arithmetic reject it. Never let a parse exception escape through FFI.
      if (a == b) return 0;
      if (a == null) return -1;
      if (b == null) return 1;
      final da = Decimal.tryParse(a), db = Decimal.tryParse(b);
      if (da != null && db != null) return da.compareTo(db);
      if (da != null) return -1;
      if (db != null) return 1;
      return a.compareTo(b);
    },
  );
  for (final op in ['add', 'sub', 'mul']) {
    db.createFunction(
      functionName: 'orm_decimal_${op}_v1',
      argumentCount: const native.AllowedArgumentCount(2),
      deterministic: true,
      function: (args) {
        if (args[0] == null || args[1] == null) return null;
        final a = Codecs.decimal.decode(args[0]),
            b = Codecs.decimal.decode(args[1]);
        return (switch (op) {
          'add' => a + b,
          'sub' => a - b,
          _ => a * b,
        }).toString();
      },
    );
  }
  db.createAggregateFunction(
    functionName: 'orm_decimal_sum_v1',
    argumentCount: const native.AllowedArgumentCount(1),
    deterministic: true,
    function: const _DecimalSum(),
  );
}

final class _DecimalTotal {
  // Intermediate sums can exceed the final NUMERIC range and subsequently
  // cancel. Enforce the range only when SQLite requests the result.
  BigInt coefficient = BigInt.zero;
  int scale = 0;
  int count = 0;
  void add(Decimal value, int direction) {
    if (count == 0) {
      coefficient = value.coefficient;
      scale = value.scale;
    } else {
      if (value.scale > scale) {
        coefficient *= BigInt.from(10).pow(value.scale - scale);
        scale = value.scale;
      }
      coefficient +=
          value.coefficient *
          BigInt.from(direction) *
          BigInt.from(10).pow(scale - value.scale);
    }
    count += direction;
    if (count == 0) {
      coefficient = BigInt.zero;
      scale = 0;
    }
  }

  String? result() => count == 0
      ? null
      : Decimal.fromBigInt(coefficient, scale: scale).toString();
}

final class _DecimalSum implements native.WindowFunction<_DecimalTotal> {
  const _DecimalSum();
  @override
  native.AggregateContext<_DecimalTotal> createContext() =>
      native.AggregateContext(_DecimalTotal());
  @override
  void step(
    native.SqliteArguments args,
    native.AggregateContext<_DecimalTotal> context,
  ) {
    if (args[0] == null) return;
    context.value.add(Codecs.decimal.decode(args[0]), 1);
  }

  @override
  void inverse(
    native.SqliteArguments args,
    native.AggregateContext<_DecimalTotal> context,
  ) {
    if (args[0] == null) return;
    context.value.add(Codecs.decimal.decode(args[0]), -1);
  }

  @override
  String? value(native.AggregateContext<_DecimalTotal> context) =>
      context.value.result();
  @override
  String? finalize(native.AggregateContext<_DecimalTotal> context) =>
      value(context);
}
