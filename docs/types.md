# Domain types and storage

Record fields keep their Dart types throughout generated creation, patches,
predicates, projections, relationships and cursor values. A codec describes the
storage boundary: `encode` produces a driver value, and `decode` validates and
constructs the application value.

## Custom IDs and values

Declare a public constant codec beside its type:

```dart
import 'package:orm/schema.dart';

extension type const UserId(int value) {
  static const codec = Codec<UserId>.integer(_decode, _encode);
  static UserId _decode(Object? value) => UserId(value as int);
  static int _encode(UserId value) => value.value;
}

typedef User = ({
  @Id.generated() @UseCodec(UserId.codec) UserId id,
  String name,
});
final users = entity<User>();
```

After generation, `db.users.byId(UserId(1))` accepts the domain ID;
`db.users.byId(1)` is a static error. Use the same domain ID codec on foreign-key
fields. Required integer primary keys can retain database-generated identities.

`Codec<T>.text(decode, encode)` and `Codec<T>.integer(decode, encode)` constrain
the encoder's return type. The general `Codec<T>(storage, decode, encode)` accepts
the storage tags in the table below. It is the application's responsibility to
validate the representation and keep encoding deterministic.

`@UseCodec` accepts a **public const variable or public static const field**.
The generator checks the reference's resolved Dart type and reads the constant
storage tag. It never calls application encoders, decoders or model constructors.
Private references and inline codec constructors are rejected. A nullable field
can use a non-nullable codec; the generated client adds `.nullable()` so SQL
`NULL` bypasses the domain decoder. A nullable codec cannot back a required field.

Imported types, extension types, public record aliases and nested generic types
retain qualified names in generated code. Two different libraries may both
declare `Email`. Output can be generated into a different directory.

See the complete [domain fixture](../test/support/codecs/schema.dart) and its
[types](../test/support/codecs/types.dart). `Codec.map` remains available when
constructing table definitions directly at runtime.

## Enums

```dart
enum Membership {
  @EnumValue('pending-payment') pending,
  active,
  @EnumValue('closed') cancelled,
}

typedef Account = ({
  @Id() int id,
  Membership membership,
  Membership? previousMembership,
});
```

Enums use text labels. Without `@EnumValue`, the label is the constant's Dart
name. Explicit labels allow a Dart rename without changing stored data. Ordinals
are never stored. Duplicate labels fail generation; an unknown stored label fails
decoding with `CODEC.ENUM`. The runtime equivalent is `Codecs.enumeration` with
an explicit enum-to-label map.

This is portable text storage, with no native enum or automatically generated
`CHECK` constraint. A database writer can therefore insert an unknown label;
the decoder detects it when read. Adding or renaming stored labels requires a
reviewed data migration and compatibility with any still-running application
versions.

## Structured JSON

Use a codec for a structured value, including a record:

```dart
import 'dart:convert';
import 'package:orm/schema.dart';

typedef Location = ({String city, int zone});
const locationCodec = Codec<Location>('json', decodeLocation, encodeLocation);

Location decodeLocation(Object? raw) {
  final json = Codecs.json.decode(raw) as Map<String, Object?>;
  return (city: json['city'] as String, zone: json['zone'] as int);
}
String encodeLocation(Location value) =>
    jsonEncode({'city': value.city, 'zone': value.zone});

typedef Place = ({
  @Id() int id,
  @UseCodec(locationCodec) Location? location,
});
```

Use `Codecs.json.decode(raw)` inside a custom JSON decoder. SQLite supplies JSON
text; PostgreSQL supplies parsed data wrapped in `SqlJson`. This bridge handles
JSON strings without decoding them twice. A JSON document containing `null` is
passed to the domain decoder; it does not bypass validation as SQL `NULL` does.

For an arbitrary document with explicit presence:

```dart
typedef Event = ({
  @Id() int id,
  @UseCodec(Codecs.jsonDocument) SqlJson? payload,
});

// In generated create/patch arguments:
// null            -> SQL NULL
// SqlJson(null)   -> JSON null
// SqlJson('text') -> JSON string
// SqlJson({'a': 1}) -> JSON object
```

Read the document through `.value`. `field.isNull()` tests SQL nullness. For
ordinary JSON values, `Codecs.json` returns the parsed Dart value, including
`null`; that value alone cannot distinguish JSON null from SQL null. `jsonEncode`
determines which payloads are serializable. Use a domain codec to validate their
shape and reconstruct application types.

Raw PostgreSQL results also use `SqlJson` for non-SQL-null `json`/`jsonb` columns.
Decode these with `Codecs.json` when consuming portable raw results. JSON values
as relational keys have not been validated and are outside the current verified
key support; use scalar IDs for relationships.

## Physical storage and migrations

| Storage tag | Built-in Dart value | SQLite | PostgreSQL |
| --- | --- | --- | --- |
| `integer` | `int` | `INTEGER` | `BIGINT` |
| `bigint` | `BigInt` | `TEXT` | `NUMERIC` |
| `decimal` | `Decimal` | collated `TEXT` | `NUMERIC` |
| `real` | `double` | `REAL` | `DOUBLE PRECISION` |
| `text` | `String`, enums | `TEXT` | `TEXT` |
| `boolean` | `bool` | `INTEGER` | `BOOLEAN` |
| `instant` | UTC `DateTime` | collated UTC text | `TIMESTAMPTZ` |
| `date` | `LocalDate` | collated `TEXT` | `DATE` |
| `time` | `LocalTime` | collated `TEXT` | `TIME WITHOUT TIME ZONE` |
| `local_datetime` | `LocalDateTime` | collated `TEXT` | `TIMESTAMP WITHOUT TIME ZONE` |
| `blob` | `Uint8List` | `BLOB` | `BYTEA` |
| `json` | JSON value or custom codec | JSON text | `JSONB` |

Snapshots record physical storage, nullability, defaults and constraints. They
do not embed application functions. Changing a codec's validation or enum labels
without changing storage does not create a DDL diff; write an explicit data
migration when existing stored values need conversion. Changing storage uses the
normal reviewed migration diff/conversion workflow.

Storage semantics still belong to each database. In particular, SQLite `bigint`
text retains exact digits but does not provide numeric text ordering/arithmetic.
Native enum types and browser numeric boundaries remain pending. Use `Decimal`
for exact decimal data.

## UTC instants

Declare an instant as `DateTime`. Generated writes accept UTC or local DateTime
objects and preserve their actual instant; reads return UTC. `Codecs.dateTime`
is a constant codec with the `instant` storage tag. Its text representation has
six fractional digits, a `+00` offset and an explicit BC suffix when applicable.

SQLite uses `TEXT COLLATE orm_instant_v1`; comparisons operate on instants rather
than lexicographic text. This preserves microsecond order, equivalent offsets,
BC and extended years, uniqueness, relationship keys, window aggregates and
stable cursors. The same collation backs column indexes. PostgreSQL uses native
TIMESTAMPTZ and binary decoding independent of session DateStyle and timezone.

Timestamp text may have a numeric UTC offset or `Z`. Zone-less database text is
defined as UTC, including SQLite's CURRENT_TIMESTAMP default; it is never parsed
using the process timezone. Invalid dates, leap seconds, excessive fractional
precision and invalid offsets fail decoding. IANA timezone names are not parsed
by this codec. Applications must explicitly resolve civil times and timezone rules
before constructing the DateTime they store. SQLite's default itself has second
resolution; precise application values retain their microseconds.

Supported instants run from 4714-11-24 00:00:00 BC through 275760-09-13 00:00:00
UTC. The upper bound follows [Dart DateTime's range](https://api.dart.dev/dart-core/DateTime-class.html),
and the lower bound follows PostgreSQL. The PostgreSQL decoder checks bounds
before adding epoch offsets, so larger native values cannot wrap through int64.
Raw finite values beyond DateTime's range and infinities remain text; typed
instant decoding rejects them. These range and precision guarantees are verified
on native Dart, not JavaScript or browser storage.

Native drivers advertise `Capabilities.temporal`, covering the local types below
and UTC instants. Borrowed PostgreSQL pools must use `postgresTypeRegistry()` and
`PostgresDriver.borrow(pool, temporal: true)`. Without that capability, typed
temporal queries fail before execution. This replaces the earlier preview's
`localTemporal` flag; no compatibility alias is provided.

### Upgrading historical timestamp storage

Previously generated `timestamp` snapshots retain their original storage meaning:
SQLite TEXT with BINARY ordering, or PostgreSQL TIMESTAMPTZ. Their serialized
snapshots, SQL and migration checksums remain unchanged. New generation emits
`instant`, which produces a visible, reviewed type change. Do not recreate an
applied migration from the current application schema.

```dart
final upgrade = Migration.diff(
  '0002_instants',
  from: previous.snapshot!,
  to: SchemaSnapshot(currentSchema),
  previous: previous.checksum,
  using: {
    SqlDialect.sqlite: {
      'events': {'created_at': 'orm_instant_v1(created_at)'},
    },
    SqlDialect.postgres: {
      'events': {'created_at': 'created_at'},
    },
  },
);
```

The SQLite converter parses and canonicalizes each value with UTC semantics;
the rebuild installs the new collation. Invalid timestamps or newly equivalent
unique keys abort the migration and roll back its changes. Audit zone-less legacy
text before conversion: if an external writer stored local civil time there,
provide a reviewed conversion using its actual timezone. PostgreSQL already stores
instants, so the shown conversion preserves values; existing infinities or values
beyond DateTime's range still require separate data review. Old cursor tokens
carry the old storage tag and cannot be reused under the new ordering contract.

The [captured legacy migration](../test/support/instants/0001_legacy.json) is tested
against its checksum from commit `00853b4`, including upgrade and rollback on real
databases. Plain unmanaged SQLite TEXT still imports as String; the managed
instant collation lets the importer infer DateTime without sampling data.

## Local calendar values

```dart
typedef Appointment = ({
  @Id.generated() int id,
  LocalDate day,
  @Default.sql("'12:30'") LocalTime time,
  LocalDateTime? starts,
});
final appointments = entity<Appointment>();

// After generation:
await db.appointments.create(
  day: LocalDate(2024, 2, 29),
  time: Change.set(LocalTime(12, 30)),
  starts: LocalDateTime.parse('2024-02-29 12:30:00.000001'),
);
```

These values have no timezone or implied UTC instant. `DateTime`, strings and
other local temporal types cannot be substituted in generated predicates or
writes. `LocalDateTime` combines a `LocalDate` and `LocalTime`. Its `add(Duration)`
uses calendar days of exactly 24 hours; it does not perform timezone or daylight
saving conversion. `LocalDate.addDays` and `daysUntil` operate on calendar dates.

| Value | Supported finite range |
| --- | --- |
| LocalDate | 4714-11-24 BC through 5874897-12-31 |
| LocalTime | 00:00:00 through 24:00:00, at microsecond resolution |
| LocalDateTime | 4714-11-24 00:00:00 BC through 294276-12-31 23:59:59.999999 |

Constructors use astronomical year numbers: year 0 is 1 BC, and year -1 is 2 BC.
Text parsing accepts those year numbers or PostgreSQL's trailing ` BC` notation.
Serialization uses era notation; times always include six fractional digits.
Invalid calendar dates, offsets, leap seconds and excess fractional precision are
rejected. `24:00` is a distinct time-of-day endpoint; combining it with a date
normalizes to the next date at `00:00`. Addition beyond the finite range fails.
The exact endpoints come from PostgreSQL's [timestamp constants](https://github.com/postgres/postgres/blob/REL_18_STABLE/src/include/datatype/timestamp.h).
The Gregorian ordinal conversion uses March-based 400-year cycles, as described
in [civil date algorithms](https://howardhinnant.github.io/date_algorithms.html).

`Codecs.date`, `Codecs.time` and `Codecs.localDateTime` accept their corresponding
value type or valid text, never a `DateTime`. An owned PostgreSQL pool uses native
binary decoders, so it does not truncate these ranges to Dart's `DateTime` range.
Binary reads remain independent of session DateStyle and timezone. Raw date and
timestamp infinity values remain strings; typed calendar decoding rejects them.
For a borrowed PostgreSQL pool, configure it before opening connections:

```dart
import 'package:orm/postgres.dart';
import 'package:postgres/postgres.dart' as pg;

final pool = pg.Pool<void>.withEndpoints(endpoints,
  settings: pg.PoolSettings(typeRegistry: postgresTypeRegistry()),
);
final db = Database(PostgresDriver.borrow(pool, temporal: true));
```

The default borrowed-pool capability is false; temporal queries fail before
execution until explicitly enabled. The registry's text fallback accepts ISO
DateStyle only. The capability covers these three scalar types and UTC instants; arrays, ranges,
intervals, time with timezone and timezone conversions are still outside it.

SQLite stores text with `orm_date_v1`, `orm_time_v1` or `orm_local_datetime_v1`
collations. They compare parsed calendar values, including equivalent text forms,
BC dates and extended years. Predicates, min/max, grouping, unique keys, foreign
keys, relations and keyset cursors preserve that ordering, and column indexes
use the same collation. External SQLite connections need matching registrations
to use those tables and indexes. No calendar-validation CHECK is emitted:
invalid external text sorts after valid values and fails typed decoding.

Snapshots preserve distinct storage tags. Catalog import recognizes native
PostgreSQL scalar types and the three managed SQLite collations. Plain SQLite
TEXT does not imply a calendar type. Changing text to a calendar type requires a
reviewed migration; newly equivalent unique keys can make conversion fail and
roll back. Historical backfills persist canonical text keys for resumable paging.

Column precision declarations (`TIME(p)` / `TIMESTAMP(p)`), SQL calendar
arithmetic and timezone-aware conversions remain pending. Use local types when
the domain value actually has no timezone; use DateTime for resolved instants.

## Signed integer column widths

```dart
typedef Counter = ({
  @Id.generated() @IntegerBits(32) int id,
  @IntegerBits(16) int small,
  @IntegerBits(32) int? optional,
  int total,
});
final counters = entity<Counter>();
```

`@IntegerBits` accepts 16, 32 or 64 on fields with integer storage, including
integer-backed domain codecs. Omitting it means 64. For manual tables, pass
`integerBits: 16` to `Column`. Explicit 64 and the default have the same serialized
schema and produce no migration difference.

Width belongs to the column metadata. It does not replace the `int` value codec
or constrain an aggregate to its source column's range. PostgreSQL SUM over
SMALLINT/INTEGER produces BIGINT; the generated API decodes wider results normally.
Other arithmetic and overflow follow the database's native rules. See PostgreSQL's
[numeric types](https://www.postgresql.org/docs/current/datatype-numeric.html) and
[aggregate return types](https://www.postgresql.org/docs/current/functions-aggregate.html).

| Width | PostgreSQL | SQLite column constraint |
|---|---|---|
| 16 | SMALLINT | integer storage value between -32768 and 32767 |
| 32 | INTEGER | integer storage value between -2147483648 and 2147483647 |
| 64/default | BIGINT | normal INTEGER storage |

SQLite still uses its native variable-sized integer representation, not a forced
two- or four-byte layout. For 16/32, DDL adds a CHECK which permits NULL when the
column is nullable and otherwise requires an integer within the signed range.
Default 64 retains ordinary SQLite INTEGER affinity. ORM writes use Dart `int`;
SQLite's affinity and raw SQL rules are documented in
[its datatype reference](https://www.sqlite.org/datatype3.html).

Catalog inspection recognizes the emitted SQLite range checks while ignoring
quoted defaults and comments. It does not claim to prove equivalence of arbitrary
handwritten CHECK expressions; those remain unmanaged. Column checks and full
schema verification both compare the inferred width. Catalog import emits
`@IntegerBits` for PostgreSQL SMALLINT/INTEGER and recognized SQLite range checks.

Width changes are type changes in migration history. Supply reviewed conversion
expressions for both dialects, even for widening. PostgreSQL alters the native
type; SQLite rebuilds the table with the new constraint. Data outside a narrowed
range fails and rolls back the migration/history together. Physical column renames
retain the width. Changing an identity column's width preserves generation and, on PostgreSQL,
the associated sequence type. Backfills use their saved width metadata when
verifying the historical schema.

Native JIT and AOT checks include integer values beyond JavaScript's exact-number
range. They do not establish browser-safe 64-bit transport. Browser numeric
boundaries remain a separate acceptance requirement.

## Verification

The generated domain fixture runs against native SQLite and PostgreSQL. Checks
cover writes, parameters, patches, invalid stored values, JSON scalar/null
semantics, joined/batched relations, batch/upsert, cursor transport, streaming and
catalog verification. Generator tests reject mismatched codecs and preserve
nullable aliases. Negative compilation tests use the actual generated APIs.
`test/support/codecs/native.dart` also compiles and runs as a native macOS AOT
program. These checks do not establish browser support.

## Exact decimals

Use `Decimal` for finite base-ten values, including money. Generated fields use
`Codecs.decimal` without an annotation. See [exact decimals](decimals.md) for
construction, arithmetic, numeric keys, SQLite storage requirements and current
limits. `BigInt` storage does not provide these fractional or SQLite numeric
ordering semantics.
