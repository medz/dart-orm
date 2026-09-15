# Exact decimals

`Decimal` stores a normalized BigInt coefficient and decimal scale. Construction,
typed writes and reads never pass through `double`. Equal values such as `2`,
`2.00` and `20e-1` have the same equality and hash code. Display precision is not
retained; `toString()` produces ordinary canonical decimal text.

```dart
import 'package:orm/schema.dart';

typedef Invoice = ({
  @Id.generated() int id,
  Decimal total,
  Decimal? discount,
});
final invoices = entity<Invoice>();

// After generation:
await db.invoices.create(total: Decimal.parse('9007199254740993.01'));
final total = await db.invoices.select((i) => i.total.sum()).single();
```

Use `Decimal.parse(String)` or `Decimal.fromBigInt(value, scale: 2)`.
Scientific notation is accepted. Whitespace, NaN, Infinity and floating-point
codec inputs are rejected. The supported finite range is at most 131072 integer
digits and 16383 fractional digits, matching unconstrained PostgreSQL
[NUMERIC limits](https://www.postgresql.org/docs/current/datatype-numeric.html).
Parsing also bounds input length and exponents. Out-of-range arithmetic throws;
there is no saturation or automatic precision reduction.

## Arithmetic

Value operations `+`, `-`, `*`, comparisons and sorting are exact. Division and
rounding require an explicit scale and default to rejecting a discarded nonzero
remainder:

```dart
final third = Decimal.parse('1').divide(
  Decimal.parse('3'),
  scale: 8,
  rounding: DecimalRounding.halfEven,
); // 0.33333333
final cents = Decimal.parse('2.345').rounded(
  2,
  rounding: DecimalRounding.halfEven,
); // 2.34
```

Other modes are `exact`, `towardZero`, `floor`, `ceiling` and
`halfAwayFromZero`. Negative scales round integer digits. Rounding changes the
value, not its display padding.

SQL fields provide `plus`, `minus`, `times`, `plusExpression`, `minusExpression`
and `timesExpression`. Combining expressions can produce SQL NULL and returns a
nullable decimal expression. `sum(distinct: true)` is optional; empty/all-null
sums return null. Aggregate accumulation permits temporary overflow that cancels
before a valid final result; range checks apply when producing the result. `min`, `max`, `count`, grouping and aggregate windows compose
with the existing query API. Predicates, IN/subqueries, computed CTE references,
UNIONs, streaming and transported cursors preserve decimal comparison semantics.

SQL expressions also provide `divide`, `divideExpression` and `rounded`, with the
same explicit scale and six rounding modes as values:

```dart
final installments = await db.invoices.select(
  (i) => i.total.divide(
    Decimal.parse('3'),
    scale: 2,
    rounding: .halfEven,
  ),
).get();
final roundedTotal = await db.invoices.select(
  (i) => i.total.sum().rounded(2, rounding: .halfEven),
).single();
```

Scale is -131072..16383. The default `exact` rejects discarded nonzero digits;
division by zero and a result outside the finite range fail the statement.
`divideExpression` accepts a nullable decimal expression and returns a nullable
result. SQL NULL propagates, including a null numerator with a zero divisor.
Each operand is evaluated once for a division evaluation, including volatile
PostgreSQL expressions. Expression assignments participate in ordinary transaction
rollback. These methods also compose with grouping, windows, CTEs, sets, streamed
results and per-parent relationship pagination.

PostgreSQL division uses [integer quotients and exact remainders](https://www.postgresql.org/docs/current/functions-math.html), rather than
rounding native `/`, whose chosen result scale can already have discarded digits.
Large remainders use a bounded decomposition to avoid overflowing an intermediate
product. Scalar stages use `MATERIALIZED` CTEs (PostgreSQL 12+); window operands
are evaluated in the original query before the final scalar projection. This
remains one statement and installs no database functions. It requires more SQL
work than native limited-scale division; cost depends on row count, operand size
and requested scale. SQLite calls the native worker's BigInt-based decimal
functions. No floating-point fallback is used.

Trusted raw SQL remains the caller's responsibility, including its result type.

## Exact averages

`average(scale: ..., rounding: ...)` returns `Expr<Decimal?>`. It ignores SQL NULL
and returns null for empty/all-null input, following normal
[aggregate semantics](https://www.postgresql.org/docs/current/functions-aggregate.html).
Scale is required; the default `exact` rejects a nonzero discarded remainder.
All six rounding modes work across the full supported scale range.

```dart
final average = await db.invoices.select(
  (i) => i.total.average(scale: 2, rounding: .halfEven),
).single();
final running = await db.invoices.orderBy((i) => [i.id.asc()]).select(
  (i) => i.total.average(scale: 2, rounding: .halfEven).over(
    orderBy: [i.id.asc()],
    frame: .rowsToCurrent,
  ),
).get();
```

The result rounds once. It does not use a previously rounded native AVG or require
the total to fit Decimal first: averaging two `9e131071` values succeeds even
though their sum is outside the finite range. PostgreSQL splits each input into
an integer high part and a low remainder at base 10^20, sums those parts and counts
non-null inputs, then computes the exact quotient/remainder before rounding.
The base exceeds the maximum signed 64-bit count; both component sums fit NUMERIC.
This uses three native aggregates and no array of input rows or installed server
function. SQLite maintains one BigInt accumulator plus count and uses an integer
fraction to produce the final value. Sliding frames remove values incrementally.

An input expression is evaluated once per contributing row for each average,
including volatile PostgreSQL expressions. Ordinary PostgreSQL aggregation uses
a correlated lateral input; window averages share their input, partition and order
values in a preceding projection. Grouping/HAVING happens before the window;
DISTINCT, final ordering and pagination apply to final results. Averages also work
in CTEs, correlated scalar subqueries, batched relation windows and streamed results.
Use a scalar subquery when assigning an aggregate result in a mutation.

To average unique values, deduplicate the input projection first:

```dart
final unique = db.invoices.select((i) => i.total).distinct().asCte('unique_totals');
final mean = await unique.query.select(
  (i) => i.ref((source) => source.total).average(scale: 2, rounding: .halfEven),
).single();
```

`distinct()` after the average instead deduplicates result rows. Window results
must similarly become CTE/subquery columns before another aggregate consumes them.

For application-side integer fractions, use
`Decimal.fromFraction(numerator, denominator, scale: ..., rounding: ...)`.
The numerator and denominator are BigInt values; only the final rounded result
must fit the Decimal range. A zero denominator is rejected. This avoids constructing
an out-of-range Decimal just to divide it back into range.

## Column precision and scale

Declare column precision independently of the Decimal value codec:

```dart
typedef Balance = ({
  @Id.generated() int id,
  @DecimalDigits(12, 2) Decimal amount,
  @DecimalDigits(12, 2) @Default.sql("'1.235'") Decimal initial,
});
```

Precision is 1..1000 and scale is -1000..1000. Omitting scale means zero.
These are [PostgreSQL NUMERIC declarations](https://www.postgresql.org/docs/current/datatype-numeric.html):
negative scale rounds integer digits, and scale may exceed precision. For example,
`DecimalDigits(3, -2)` stores multiples of 100 through 99900 in magnitude;
`DecimalDigits(3, 5)` stores up to 0.00999 in magnitude. Negative/excess scales
require PostgreSQL 15 or newer. Native verification uses PostgreSQL 18.4.

ORM writes round ties away from zero and then check the range. `1.235` becomes
`1.24`, `-1.235` becomes `-1.24`; `999.995` overflows NUMERIC(5,2) after rounding.
This applies to generated creation/patches, expression assignments, batches,
upserts and defaults. Generated records contain the stored value; use the
returned key if a decimal primary key was rounded. Query parameters are not
implicitly rounded to a column's scale.

Computed values and aggregates retain the unconstrained Decimal codec. A sum may
therefore exceed the column's precision. To coerce a SQL expression explicitly,
use `amount.sum().constrained(12, 2)`; this composes with predicates and CTEs.
For an application value, `value.constrained(12, 2)` performs the same rounding
and range check, while `value.fits(12, 2)` checks whether it fits without rounding.
Choose `rounded(..., rounding: ...)` before a write when another rounding policy
is needed. Column coercion then preserves the already rounded value.

PostgreSQL uses native NUMERIC(p,s). SQLite uses the existing numeric TEXT
collation plus a managed precision CHECK. ORM assignments and defaults call the
exact coercion function. A raw SQLite writer must supply an already fitting value
or explicitly call `orm_decimal_cast_v1(value, precision, scale)`; the CHECK
rejects values requiring rounding, out-of-range values and invalid decimal text.
A raw PostgreSQL writer receives PostgreSQL's native coercion. As with the native
NUMERIC type, NaN remains a PostgreSQL write possibility and fails typed decoding.

Precision/scale are included in snapshots, CLI inspection and import drafts.
Changing either requires explicit migration conversion expressions. SQLite
rebuilds and coerces the copied values; PostgreSQL changes the column type.
Rounding can turn distinct keys into duplicates, which rolls back structure and
history together. Imported SQLite declarations remove the managed outer default
coercion before generation; verification still detects a missing coercion in the
actual database default. Custom decimal-backed codecs retain their Dart types.

## Storage and other database writers

PostgreSQL uses native NUMERIC and its native arithmetic. SQLite uses TEXT with
the versioned `orm_decimal_v1` numeric collation. Each native SQLite worker
registers pure exact arithmetic functions and a window-capable sum. This is
necessary because ordinary SQLite numeric operations can coerce text to
[approximate floating point](https://www.sqlite.org/floatingpoint.html).
Arithmetic and sum functions are restricted to direct SQL. Column coercion and
validation functions additionally run in defaults and CHECK constraints. The
current SQLite binding does not mark these two functions innocuous, so SQLite
rejects their use in schema expressions with `trusted_schema = OFF`. The driver
preserves that setting; constrained decimal schemas currently require it ON.

The collation also governs indexes, primary/unique keys and foreign keys: `2.00`
conflicts with `2`. Batch relationship keys normalize before matching returned
rows. Applications opening these SQLite files through another driver must provide
the same collation before using affected keys, sorting or schema changes. Raw
decimal arithmetic additionally needs the corresponding functions. The native
ORM driver registers these per connection; browser support has not been verified.

Always bind strings for externally written decimal values. SQLite TEXT affinity
cannot recover precision already lost in an incoming REAL value. SQL defaults
should be quoted decimal strings, for example `@Default.sql("'0.10'")`.
Ordinary numeric literals can be evaluated approximately by SQLite first.

Unconstrained decimal columns have no generated finite-value CHECK. PostgreSQL
permits special numeric values; unconstrained SQLite columns permit arbitrary text. Typed decoders
reject these. SQLite orders invalid external text after valid decimals, using
lexical order between invalid values, because a collation callback cannot report
a SQL error safely. Arithmetic on invalid text fails. Do not treat the absence
of a write error from another client as validation of a `Decimal` value.

## Schema evolution and verification

Snapshots store the `decimal` tag. Catalog verification checks SQLite column
collation as well as storage type, nullability and other declared facts. Import
recognizes PostgreSQL NUMERIC, optional precision/scale, and SQLite TEXT columns
carrying the exact managed collation and optional managed precision check. Plain SQLite NUMERIC is not imported as an exact decimal.
Quoted defaults or nested SQL fragments do not count as column collations.

Changing text to decimal requires reviewed conversion expressions. SQLite rebuilds
the table with the new collation; PostgreSQL changes its native type. Existing
text keys `2` and `2.00` become duplicate numeric keys, so the migration fails and
rolls back data, structure and history together. Repair the data before retrying.
Historical backfills retain exact decimal keys in their resumable checkpoints.

See the [generated fixture](../test/support/decimals/schema.dart),
[database checks](../test/decimal_test.dart),
[division/window checks](../test/decimal_division_test.dart),
[average checks](../test/decimal_average_test.dart) and the
[native acceptance executable](../test/support/decimals/native.dart).
These establish correctness on the tested native databases. Browser/Flutter
acceptance remains open.

## Native cost probe

The [benchmark script](../tool/benchmark_decimal.dart) fetches and decodes 10000
integer-valued Decimal rows. Each case has one warmup and three measured runs.
The checked-in [raw report](../research/benchmarks/decimal-division.json) was
recorded with a native macOS ARM64 AOT executable, Dart 3.13.3, in-memory SQLite
3.51.0 and local PostgreSQL 18.4. Median elapsed milliseconds:

| Operation | SQLite | PostgreSQL |
| --- | ---: | ---: |
| Read Decimal values | 10.13 | 22.72 |
| Divide by 3, scale 2, half-even | 30.09 | 32.63 |
| Round to tens, half-even | 21.64 | 25.25 |
| Running sum then divide by 3 | 48.17 | 36.85 |

The expanded [average report](../research/benchmarks/decimal-average.json) uses
the same native AOT method and database versions. All cases consume 10000 rows;
the ordinary average returns one row, while the running average returns 10000:

| Operation | Returned rows | SQLite ms | PostgreSQL ms |
| --- | ---: | ---: | ---: |
| Average, scale 2, half-even | 1 | 8.78 | 2.74 |
| Running average, scale 2, half-even | 10000 | 29.12 | 47.25 |

Both reports retain individual samples; the expanded script also reruns the
read/divide/round controls. The earlier division table above refers to its original
report, rather than mixing results from separate runs.

These are single-client end-to-end samples, including query compilation, database
work, row transport and Decimal decoding. They are not latency percentiles,
concurrency measurements, or estimates for large coefficients/high scales.
No other ORM test/build workload ran during measurement.

```sh
dart compile exe tool/benchmark_decimal.dart -o /tmp/orm-decimal-benchmark
/tmp/orm-decimal-benchmark > /tmp/decimal-division.json
```

Set `ORM_TEST_POSTGRES` to an accessible disposable local PostgreSQL URL to include
PostgreSQL. The script disables TLS for that local connection, creates a uniquely
named schema and drops its schema afterward; the account needs schema-creation
permission. Without the variable it measures SQLite only. Run separately from
tests and builds. Compilation happens before timing.
