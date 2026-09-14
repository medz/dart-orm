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
Configurable native integer widths, precise-decimal query semantics, native enum
types and browser numeric boundaries remain pending. Do not substitute `double`
for exact decimal data.

## Verification

The generated domain fixture runs against native SQLite and PostgreSQL. Checks
cover writes, parameters, patches, invalid stored values, JSON scalar/null
semantics, joined/batched relations, batch/upsert, cursor transport, streaming and
catalog verification. Generator tests reject mismatched codecs and preserve
nullable aliases. Negative compilation tests use the actual generated APIs.
`test/support/codecs/native.dart` also compiles and runs as a native macOS AOT
program. These checks do not establish browser support.
