# MySQL and MariaDB decimal precision boundaries

Date: 2026-09-19. Tested against the local MySQL 8.4 and MariaDB 11.8
integration containers. This report records actual SQL results, not a claim
about every release in either engine family. The probes used the database CLI,
independently of the Dart driver and SQL compiler.

## Decision

The MySQL and MariaDB `exactDecimal` capability means exact decimal value
transport and typed comparisons within supported storage limits. It does not
promise arbitrary-precision SQL arithmetic. The current typed SQL implementation
rejects decimal addition, subtraction, multiplication, `SUM`, explicit expression
`constrained`, and decimal `UNION` / `UNION ALL` with
`CAPABILITY.DECIMAL_PRECISION`. Explicit rounding, division, and average also
remain unsupported. The Dart `Decimal` value object's local arithmetic is
unaffected by these SQL restrictions.

Decimal columns, exact parameters, comparisons, and `MIN` / `MAX` remain
available. The shared MySQL/MariaDB storage contract is precision 1–65 and scale
0–min(precision, 30); big integers use `DECIMAL(65,0)`. Assignments let the declared
column apply its engine's storage coercion and strict-mode checks. They do not
first cast the value into a narrower expression, which could saturate before
the column sees it. Storage coercion is not a promise of arbitrary precision or
of identical rounding across engines.

Explicit `sql(...)` expressions remain the escape hatch when an application
accepts the selected engine's bounded arithmetic. Future typed support must
propagate concrete precision and scale through expressions and query boundaries,
and prove that the complete expression remains exact. We are not adding a SQL
big-number implementation or assuming that checking warnings makes these
operations safe.

## Conditions and notation

The probe sessions included `STRICT_ALL_TABLES` and `NO_BACKSLASH_ESCAPES`.
Each result-producing statement was immediately followed by `SHOW WARNINGS`.
The probes below only read values; they require no application tables.

For readable result summaries:

- `I = 10^65 - 1`, the maximum positive `DECIMAL(65,0)` value.
- `A = 10^35 - 10^-30`, the maximum positive `DECIMAL(65,30)` value.
- `E = 10^-30`.
- `F = 0.123456789012345678901234567891`.

These symbols describe exact mathematical values; the SQL below uses explicit
literals and casts, not floating-point exponent notation.

| Probe | MySQL 8.4 | MariaDB 11.8 | Warnings |
| --- | --- | --- | --- |
| `A + 1` | Exact, including the 36th integer digit | Same | None |
| `A + E` | Exact carry to `10^35` | Same | None |
| `I + E` | `I.000000000`; loses `E` | Same | None |
| `I - E` | `I.000000000`; loses the fractional subtraction and borrow | Same | None |
| `A - 1`, `A - E` | Exact | Same | None |
| `F + 1.2`, `F - 1.2` | Exact | Same | None |
| Direct `SUM` of two `A` values | Exact `2A` | Same | None |
| Direct `SUM` of two `I` values | Exact `2I` (66 integer digits) | Same | None |
| `SUM` of two `E` values | Exact `2E` | Same | None |
| The `2A` sum selected from a derived table or CTE | Saturates to `A` | Same | None |
| The `2I` sum selected from a derived table or CTE | Saturates to `I` | Same | None |
| Outer `SUM` over either saturated inner sum | Sees the already saturated value | Same | None |
| `F * F` | Result has 30 fractional digits; exact result needs 60 | Result has 38 fractional digits; exact result needs 60 | None |
| `CAST(999 AS DECIMAL(2,0))` | Returns `99` | Same | Warning 1264 |
| `UNION ALL` of `I` and `E` | Large row saturates to `A`; small row remains `E` | Same | None |

Successful small examples do not establish a safe general operator. In
particular, a direct aggregate can appear exact while an ordinary surrounding
query changes the result. Only two input rows are needed to reproduce this.

## Reproduction SQL

Run the statements in a session with the modes above. `SHOW WARNINGS` must stay
immediately after its corresponding `SELECT`; later statements replace the
diagnostics.

### Mixed-scale addition and subtraction

Both operands fit the documented storage contract, but the result silently
discards the nonzero fractional term.

```sql
SELECT
  CAST(99999999999999999999999999999999999999999999999999999999999999999
       AS DECIMAL(65,0))
  + CAST(0.000000000000000000000000000001 AS DECIMAL(65,30)) AS result;
SHOW WARNINGS;

SELECT
  CAST(99999999999999999999999999999999999999999999999999999999999999999
       AS DECIMAL(65,0))
  - CAST(0.000000000000000000000000000001 AS DECIMAL(65,30)) AS result;
SHOW WARNINGS;
```

Both statements return the 65-digit integer followed by `.000000000`. Neither
engine reports a warning. The exact addition should preserve the final
fractional `1`; the exact subtraction should decrement the integer part and
produce 30 fractional nines.

### Aggregate precision changes at a query boundary

The first statement returns the exact 66-digit sum. The next statements return
only `I`, silently saturating the same sum.

```sql
SELECT SUM(v) AS result
FROM (
  SELECT CAST(99999999999999999999999999999999999999999999999999999999999999999
              AS DECIMAL(65,0)) AS v
  UNION ALL
  SELECT CAST(99999999999999999999999999999999999999999999999999999999999999999
              AS DECIMAL(65,0))
) AS inputs;
SHOW WARNINGS;

SELECT s
FROM (
  SELECT SUM(v) AS s
  FROM (
    SELECT CAST(99999999999999999999999999999999999999999999999999999999999999999
                AS DECIMAL(65,0)) AS v
    UNION ALL
    SELECT CAST(99999999999999999999999999999999999999999999999999999999999999999
                AS DECIMAL(65,0))
  ) AS inputs
) AS sums;
SHOW WARNINGS;

WITH sums AS (
  SELECT SUM(v) AS s
  FROM (
    SELECT CAST(99999999999999999999999999999999999999999999999999999999999999999
                AS DECIMAL(65,0)) AS v
    UNION ALL
    SELECT CAST(99999999999999999999999999999999999999999999999999999999999999999
                AS DECIMAL(65,0))
  ) AS inputs
)
SELECT s FROM sums;
SHOW WARNINGS;
```

The fractional case was also tested: replace each value with
`99999999999999999999999999999999999.999999999999999999999999999999`
and each cast with `DECIMAL(65,30)`. The direct result is
`199999999999999999999999999999999999.999999999999999999999999999998`.
The derived-table and CTE results instead equal the original single input `A`.
Changing the outer `SELECT s` to `SELECT SUM(s)` also observes the saturated
value. All these statements produce no warnings on either tested engine.

### Multiplication

```sql
SELECT
  CAST(0.123456789012345678901234567891 AS DECIMAL(65,30))
  * CAST(0.123456789012345678901234567891 AS DECIMAL(65,30)) AS result;
SHOW WARNINGS;
```

The exact product requires 60 fractional digits. MySQL returns 30 and MariaDB
returns 38, with no warning. The different result scales also rule out treating
native multiplication as a single cross-engine exact contract.

### Explicit narrowing cast

```sql
SELECT CAST(CAST(999 AS DECIMAL(65,0)) AS DECIMAL(2,0)) AS result;
SHOW WARNINGS;
```

Both engines return `99` and warning 1264 rather than raising a statement error.
A preceding cast therefore cannot enforce an overflow-error contract on behalf
of a later column assignment.

### Set-operation precision unification

```sql
SELECT v
FROM (
  SELECT CAST(99999999999999999999999999999999999999999999999999999999999999999
              AS DECIMAL(65,0)) AS v
  UNION ALL
  SELECT CAST(0.000000000000000000000000000001 AS DECIMAL(65,30))
) AS combined;
SHOW WARNINGS;
```

Both engines return `A` for the large row and `E` for the small row, without
warnings. The large input loses 30 integer digits merely by sharing a result
column with another valid decimal. The current typed guard covers both `UNION`
and `UNION ALL`; this concrete probe used `UNION ALL`.

## Evidence and scope

The SQL results above are the deciding evidence. They show that strict mode and
an empty warnings list are insufficient to establish exact expression results.
They do not imply that every native decimal operation is inaccurate, or that
all expressions with known small bounds must remain unsupported forever.

MySQL's [decimal characteristics documentation](https://dev.mysql.com/doc/refman/8.4/en/precision-math-decimal-characteristics.html)
describes its bounded decimal representation. Its
[8.4 aggregate implementation](https://github.com/mysql/mysql-server/blob/8.4/sql/item_sum.cc)
contains separate aggregate result-type and temporary-field paths. Those are
useful implementation references; this report does not infer identical internals
for MariaDB or rely on an unverified explanation of the optimizer's decisions.

The present policy deliberately rejects an operation whose complete bounds are
unknown instead of guessing from a value's Dart type. Restoring an operator
requires precision/scale propagation through parameters, columns, aggregates,
casts, subqueries, CTEs, and set operations, with regression coverage against
both real servers.
