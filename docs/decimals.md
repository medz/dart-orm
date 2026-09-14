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

SQL division, rounded SQL averages and NUMERIC(p, s) column declarations remain
unfinished. There is no implicit conversion to approximate `AVG` or `/`. When
working with values already fetched, use `divide` or `rounded` explicitly.
Trusted raw SQL remains the caller's responsibility, including its result type.

## Storage and other database writers

PostgreSQL uses native NUMERIC and its native arithmetic. SQLite uses TEXT with
the versioned `orm_decimal_v1` numeric collation. Each native SQLite worker
registers pure exact arithmetic functions and a window-capable sum. This is
necessary because ordinary SQLite numeric operations can coerce text to
[approximate floating point](https://www.sqlite.org/floatingpoint.html).
Functions are restricted to direct SQL and are not enabled inside triggers or
views. The driver does not change `trusted_schema`.

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

There is currently no generated finite-decimal CHECK constraint. PostgreSQL
permits special numeric values; SQLite permits arbitrary text. Typed decoders
reject these. SQLite orders invalid external text after valid decimals, using
lexical order between invalid values, because a collation callback cannot report
a SQL error safely. Arithmetic on invalid text fails. Do not treat the absence
of a write error from another client as validation of a `Decimal` value.

## Schema evolution and verification

Snapshots store the `decimal` tag. Catalog verification checks SQLite column
collation as well as storage type, nullability and other declared facts. Import
recognizes unconstrained PostgreSQL NUMERIC and SQLite TEXT columns carrying the
exact managed collation. Plain SQLite NUMERIC is not imported as an exact decimal.
Quoted defaults or nested SQL fragments do not count as column collations.

Changing text to decimal requires reviewed conversion expressions. SQLite rebuilds
the table with the new collation; PostgreSQL changes its native type. Existing
text keys `2` and `2.00` become duplicate numeric keys, so the migration fails and
rolls back data, structure and history together. Repair the data before retrying.
Historical backfills retain exact decimal keys in their resumable checkpoints.

See the [generated fixture](../test/support/decimals/schema.dart),
[database checks](../test/decimal_test.dart) and
[native acceptance executable](../test/support/decimals/native.dart).
These establish correctness on the tested native databases, not performance or
browser/Flutter acceptance.
