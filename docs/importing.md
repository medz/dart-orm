# Import an existing database

Import reads the catalog and produces an editable Record declaration plus a review
report. It does not sample rows, create migration history, change tables, or copy
data. Generate the client and baseline the reviewed schema as separate steps.

```sh
dart run orm db import --sqlite app.sqlite --output lib/schema.dart
# PostgreSQL alternative:
dart run orm db import --postgres-env DATABASE_URL --database-schema public --output lib/schema.dart

# Review lib/schema.dart and lib/schema.import.json first.
dart run orm generate lib/schema.dart
dart run orm migration create 0001_baseline --schema lib/schema.orm.json
dart run orm db baseline --sqlite app.sqlite
dart run orm db verify --sqlite app.sqlite --schema lib/schema.orm.json
```

Use the PostgreSQL connection options for all database commands when importing
PostgreSQL. Existing database-specific defaults and objects need reviewed migrations;
an imported declaration is not automatically a portable creation script for the
other dialect. Baseline verifies the declared schema before recording history and
does not execute the initial creation SQL.

`--output` must name a new `.dart` file. Neither it nor the adjacent `.import.json`
report may already exist. SQLite opens read-only and requires an existing file.
PostgreSQL uses a read-only, repeatable-read transaction in the selected schema.
Each invocation uses one catalog snapshot. Existing outer transactions are rejected;
a borrowed session without an active transaction is allowed.

To limit the import, put exact physical table names in a JSON array, such as
`["accounts", "notes"]`, and supply `--tables tables.json`. Without this option,
discovery covers SQLite main or the current PostgreSQL schema. Internal ORM history
tables are omitted. Include the referenced tables when importing relationships;
missing targets and temporary objects shadowing selected tables produce issues.

## Declarations and reports

```dart
import 'package:orm/schema.dart';

typedef AccountsRow = ({
  @ColumnName('id') @Id.generated() int id,
  @ColumnName('email') String email,
  @ColumnName('display_name') String? displayName,
});
final accounts = entity<AccountsRow>(table: 'accounts');
final accountsUnique = accounts.unique((row) => row.email);
```

Every table and field retains an explicit physical name. Dart keywords, punctuation,
Unicode-only names and collisions get valid names recorded in the report's
`entities` and `fields` maps. Rename Dart symbols to match your domain while keeping
the physical mappings. Primary/composite keys, unique constraints, simple named
indexes and representable foreign keys become declarations. Relationships get names
and inverse selections; rename these before generation if a domain name is clearer.
Foreign-key actions include SET DEFAULT.

Ordinary enforced [CHECK constraints](checks.md) become `.check(...)` declarations
with their native names and SQL. A nonblocking `IMPORT.CHECK_SQL` note requests
review of backend-specific expressions before deployment on another dialect.
PostgreSQL unvalidated, unenforced and inheritance-specific checks remain unmanaged.

The JSON report records the dialect, schema, name maps, and issues:

- Blocking issues exclude an unsupported table or relation. CLI exit code is 2;
  the partial draft and report are still written for review.
- Nonblocking issues preserve descriptions of unmanaged objects, such as views,
  triggers and specialized indexes. Exit code remains 0, but those objects still
  need separate review and database-specific migration handling.
- Invalid options or existing output paths use exit code 64. Existing files remain.

An empty issue list is not proof of complete database equivalence. Catalog support
and `verifySchema` cover declared facts; they do not prove that grants, extensions,
database settings or every native object can be recreated from a Record schema.

## Types and boundaries

Import uses exact physical mappings. It never infers a semantic type from example
rows or a column name.

| SQLite | PostgreSQL | Draft Dart type |
|---|---|---|
| INTEGER | SMALLINT / INTEGER / BIGINT | int, with width metadata where needed |
| TEXT | TEXT | String |
| TEXT COLLATE orm_decimal_v1, optional precision CHECK | NUMERIC, NUMERIC(p,s) | Decimal, optional DecimalDigits |
| REAL | DOUBLE PRECISION | double |
| BLOB | BYTEA | Uint8List |
| — | BOOLEAN | bool |
| TEXT COLLATE orm_instant_v1 | TIMESTAMPTZ | DateTime |
| TEXT COLLATE orm_date_v1 | DATE | LocalDate |
| TEXT COLLATE orm_time_v1 | TIME WITHOUT TIME ZONE | LocalTime |
| TEXT COLLATE orm_local_datetime_v1 | TIMESTAMP WITHOUT TIME ZONE | LocalDateTime |
| — | JSONB | SqlJson with Codecs.jsonDocument |

Nullability is preserved. SQLite TEXT may contain timestamps, enums, bigints or
JSON, and INTEGER may hold application booleans. Add reviewed codecs when needed;
the catalog does not establish those meanings. PostgreSQL NUMERIC
imports as finite `Decimal`, never as BigInt; constrained columns retain
`@DecimalDigits(precision, scale)`. Import does not sample values;
existing NaN or Infinity values will fail typed decoding. SQLite requires the
recognized column collation to establish decimal storage and recognizes only the
emitted precision CHECK. Varchar, arrays, domains and other native types still
need explicit support. See
[decimal boundaries](decimals.md) before reviewing a draft.

SQLite rowid integer primary keys and PostgreSQL BY DEFAULT integer primary-key
identities get `@Id.generated()`. [Computed expressions](computed.md) become
`@Computed.sql` with their stored/virtual mode and an `IMPORT.COMPUTED_SQL`
portability review note. ALWAYS identities,
non-primary identities and nullable primary keys require explicit write semantics
and are currently blocking. Sequence defaults such as a BIGSERIAL default retain
their catalog SQL; import does not convert them to identities or reset sequences.
Review their dependencies before baselining.

PostgreSQL SMALLINT/INTEGER columns and SQLite INTEGER columns with recognized
ORM range checks retain their `@IntegerBits(16)` or `@IntegerBits(32)` declaration.
See [integer widths](types.md#signed-integer-column-widths) for range enforcement,
aggregation and migration behavior.

SQLite import requires 3.37 or later to distinguish ordinary, virtual and shadow
tables using [table_list](https://www.sqlite.org/pragma.html#pragma_table_list).
Virtual tables and their backing tables are reported rather than emitted as ordinary
models. PostgreSQL partitioned/inherited and foreign tables need explicit declarations.
Identity modes and generated expressions have separate
[catalog attributes](https://www.postgresql.org/docs/current/catalog-pg-attribute.html).

Specialized index semantics remain in the report: partial/expression indexes and
PostgreSQL nondefault operator classes, collation overrides, storage options and
NULLS NOT DISTINCT. These differ from plain unique keys; see the
[PostgreSQL index catalog](https://www.postgresql.org/docs/current/catalog-pg-index.html).

PostgreSQL policy objects stay unmanaged. Their `definition` is JSON containing
`permissive`, `roles`, `command`, `using` and `withCheck`, preserving the fields in
[`pg_policies`](https://www.postgresql.org/docs/18/view-pg-policies.html).
A separate `row_security` object contains the table's `enabled` and `forced`
flags from [`pg_class`](https://www.postgresql.org/docs/18/catalog-pg-class.html).
It is reported when either flag is set or a policy exists, including disabled
policies. These metadata descriptions are not executable migration SQL.
`verifySchema` and baseline return them for review without claiming that the
Record snapshot models access-control policy. Neither operation changes those
settings. Trigger definitions likewise remain unmanaged; import/verification
tests exercise real triggers on both databases and verify they still execute.

## Tooling API

```dart
import 'package:orm/generate.dart';

final draft = await importSchema(db, tables: ['accounts', 'notes']);
print(draft.dart);
print(draft.toJson());
if (draft.hasBlockingIssues) {
  // Resolve the reported native types or relationships before baselining.
}
```

The API returns values and writes no files. It belongs to the generator/tooling
entry point. Generated applications continue using the normal ORM and driver
entry points. The CLI does not automatically generate a client or apply a baseline.
