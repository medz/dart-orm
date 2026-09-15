# Declaration-form experiment

The default ORM declaration remains Record schema with separate table identity.
The design's §13.2 experiment now compares the same User/Post/Profile/Follow
schema in three actual Dart forms: Record typedefs, primary-constructor classes,
and classes with typed column fields. These are controlled authoring prototypes;
the package does not add three public schema APIs or alternate runtimes.

Run the experiment from the repository:

```sh
dart run tool/compare_authoring.dart
```

`--smoke` checks only the Record input and writes under `.dart_tool/`. The full
run checks all three forms and writes
[`authoring.json`](../research/benchmarks/authoring.json). Inputs are in
[`authoring_fixture.dart`](../tool/src/authoring_fixture.dart); the report retains
the formatted original/edited sources, normalized schemas, physical snapshots,
hashes, LSP edits and compiler errors. The captured run uses Dart 3.13.3.

## One output contract

Every form is resolved by the Dart analyzer, then converted to a canonical Record
schema. That schema passes through the unchanged production generator. Classes
serve as schema declarations here; outputs are Record rows. This experiment does
not implement materialization of nominal domain objects, inheritance, arbitrary
constructor logic or computed getters. Its adapter accepts the fixture's built-in
int/String/bool/DateTime codecs and nullability, and rejects custom codec behavior
instead of silently discarding it. Constructor bodies are also rejected.

The fixtures contain generated identities, physical column names, nullable fields,
a SQL boolean default, two composite user uniqueness constraints, composite profile
and follow primary keys, four composite foreign keys, both Follow-to-User edges,
different deletion actions, an ordered four-column index and a row CHECK.

For each of these three variants, the normalized Dart schema, entire generated
client and physical snapshot must be byte-identical across all authoring forms:

1. The base four-model schema.
2. Changing Profile.bio from String? to int?.
3. Renaming User.email to contactEmail while retaining physical column `email`.

The third variant must also retain the base physical snapshot exactly. Independent
report readback checks the individual key/FK/default/index/CHECK metadata and that
the type-edit snapshot changes only the intended field's storage type.

A shared consumer compiles generated create/patch methods and a typed named Record
projection containing posts, an optional profile and nested following-user emails.
After each schema edit, the old consumer must fail static analysis. Updating its
affected references/types must restore clean analysis. This checks the generated
API, not only a successful schema parse or matching snapshot hashes.

## Authoring and refactoring cost

Formatted model declarations, including their imports/language directive and
excluding the common table/constraint block:

| Form | UTF-8 bytes | Lines | Field rename in schema |
| --- | ---: | ---: | --- |
| Record | 487 | 24 | Manual declaration and selector edit |
| Primary constructor | 585 | 24 | LSP updates declaration and unique-key selector |
| Table class | 1,574 | 43 | LSP updates field and selector, retaining SQL name |

These are measurements of this fixture and formatter style, not a universal code
reduction claim. Primary constructors substantially reduce class boilerplate, so
Record has no line-count advantage in this sample. Primary constructors are a
[Dart 3.13 language feature](https://dart.dev/language/primary-constructors).

The checked SDK returns null for both prepare/rename on the Record field. This
differs from renaming its typedef, and Record aliases do not create nominal types;
see [Dart's Record semantics](https://dart.dev/language/records). The class/table
probes receive and apply two edits: field declaration and the constraint's typed
reference. They use a clean Analysis Server session.

All three forms still require regeneration and application-reference repair.
The experiment's authoring classes are separate from the generated Record/client
symbols, so their successful schema rename does not automatically refactor that
generated API. Six stale-consumer runs—type edit and rename for every form—fail
as expected; all repaired consumers and final projects analyze cleanly.

Retaining Record as the default preserves the current data-first contract and the
smallest input in this fixture. Its missing automatic field rename is a real cost,
documented for users rather than hidden by generated setters or string lookup.
The comparison does not establish that Record is universally easier than a primary
class, and does not add nominal class rows as an untested feature.

## Error locations and measurement limits

Every form checks an unknown member, a computed index selector, a repeated key
field and a foreign key whose exact target uniqueness was removed. Dart catches
the unknown member. The generator rejects the latter three and their offsets map
back to the original authoring source, including the multiline FK expression.
The report retains phase, code, offset, line, column and source line. Additional
checks reject a primary-constructor body and a custom table codec: fourteen located
failures in total. The adapter's offset mapping is an experimental tool facility,
not a newly shipped IDE plugin or public generator diagnostic format.

Stage timings are retained as single observations in a fixed Record/class/table
order. They include analyzer/formatter JIT warmup effects and cannot rank the
frontends' generation speed. Offline dependency resolution is outside timing;
shared caches are warm. Actual 10/100/1000-model generation and LSP completion
measurements remain in [generation](generation.md). The earlier mixed-session
rename timeout is still an unverified workflow; this clean-session capture does
not resolve it. This authoring experiment does not execute a database or prove
native Flutter behavior.
