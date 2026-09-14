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
| `timestamp` | UTC `DateTime` | ISO text | `TIMESTAMPTZ` |
| `blob` | `Uint8List` | `BLOB` | `BYTEA` |
| `json` | JSON value or custom codec | JSON text | `JSONB` |

Snapshots record physical storage, nullability, defaults and constraints. They
do not embed application functions. Changing a codec's validation or enum labels
without changing storage does not create a DDL diff; write an explicit data
migration when existing stored values need conversion. Changing storage uses the
normal reviewed migration diff/conversion workflow.

Storage semantics still belong to each database. In particular, SQLite `bigint`
text retains exact digits but does not provide numeric text ordering/arithmetic.
Precise-decimal query semantics, native enum types and browser numeric boundaries
remain pending. Do not substitute `double`
for exact decimal data.

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
