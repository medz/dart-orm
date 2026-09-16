# Public API and correctness audit

Scope: the `next` implementation at `6d1ba30`, followed by the changes in this
review. This is a source and behavior audit of entrypoints, generation, query
composition, decoding, writes, sessions, drivers and migration boundaries.

## Findings and changes

| Finding | Consequence | Correction and evidence |
| --- | --- | --- |
| Subqueries and CTEs checked dialect but not owning session | A root, expired or other database's query could silently execute inside another transaction/connection | The SQL writer carries the owning `Database`; every nested query checks identity. `query_boundary_test` exercises rejection before SQL and valid same-session composition |
| Optional selection disabled nullability validation for every joined table | One alias's presence could incorrectly justify decoding a different absent alias as required | Selection plans retain the exact presence guards of each required expression; nested guards remain composable |
| Mutation validation omitted aggregate/window predicates and assignments | Invalid typed SQL reached the database and could poison a transaction | Mutation compilation rejects invalid placement; scalar subqueries remain available |
| Empty RETURNING and joined relation RETURNING lacked a direct contract check | Invalid SQL or unrelated alias errors instead of a useful ORM error | Reject empty projections and all relationship loading in RETURNING before execution |
| A second close() returned before the first shutdown drained its lease | Awaiting shutdown did not consistently imply resource cleanup | All close callers await the same shutdown future; real SQLite/PostgreSQL tests hold and release a pending lease |
| One throwing cancellation listener blocked the remaining listeners | Running operations could miss a requested cancellation | Isolate listener failures and preserve idempotence; regression covers subsequent and already-cancelled listeners |
| Generator imposed both engines' computed-column restrictions | Valid SQLite virtual indexes and PostgreSQL stored computed primary keys could not be declared | Generation checks structure; selecting a migration engine checks native capabilities. `schema_boundary_test` executes both cases on real databases |
| Catalog import retained the same portability restriction and a separate reserved-name list | Valid native tables could not round-trip through import and generation | Preserve the inspected engine's computed keys; share Database member names across declaration, named-query and import readers. Native import → generate → verify cases cover both engines |
| Schema validation missed malformed keys, index collisions, identifier spelling and target case rules | Invalid schemas failed late; case rules were inconsistently applied | Validate names/local keys and shared table/index names; resolve SQLite case and PostgreSQL identifier length only for that target |
| Generated extension getters could shadow Database members; generated symbols could collide | Accepted declarations produced unusable getters or uncompilable clients | Reject the declaration with a generation error and retain physical names through `table:`/`ColumnName` |
| Named SQL silently accepted some storage-only annotations | Defaults/computation/precision annotations appeared to configure a query result but were discarded | Reject all storage-only metadata; named results retain codec/column-name annotations |
| Generated clients did not export their row aliases; generated schema lists were mutable | Additional model imports and mutations could break the declaration/runtime contract | Export only row aliases, keep declaration objects private to the schema import, and freeze `appSchema` |
| Generator build factories were also public through generate.dart | Two tooling entrypoints exposed the same implementation hooks | Explicit generation facade; build factories live behind builder.dart. Migration entrypoint exports its required schema primitives |
| README still suggested changing an environment variable switched migration engines | Contradicted the fixed-engine history model | One SQLite onboarding path and an explicit explanation of separate histories |

The initial six-case SQLite reproduction passed one preservation case and failed
five boundary cases. After the runtime correction, the related SQLite query,
relation, selection and UNION suites passed 39 cases. Full final validation is
recorded below after all generation and documentation changes.

## Decisions retained after review

- One package. `orm.dart` contains portable runtime code; database entrypoints
  re-export it. Driver/codec/manual-table interfaces are intentional advanced API,
  not extra application layers. SQL AST and decoding internals remain private.
- One query belongs to one `Database` view. Queries are immutable descriptions;
  get/execute/stream perform work. A transaction callback receives a borrowed view.
  Helpers must receive that view; separate calls on a captured root remain separate
  operations. No ambient transaction context is introduced to hide ownership.
- A Record describes data shape. Table and alias objects carry SQL identity.
  Relationship selection is explicit; no lazy object graph or hidden writes.
- Current declarations and generated clients can evolve. Saved Dart migrations
  retain their historical schema, selected engine, fixed checksums and imports.
- Reviewed raw SQL is an escape hatch. The ORM does not claim to parse arbitrary
  raw expressions or prove their result codec, external effects or deployment safety.
- The apparent `_withConflict`/batch-row issue was not reachable through the public
  API: BatchInsert has no conflict method and uses its own chunk execution path.
  It is not reported as a confirmed data-loss bug or used to add a new feature.
- Record field rename limitations, platform support, retry/unknown-COMMIT rules,
  watch invalidation boundaries and backfill recovery remain explicit contracts.

## Database references

PostgreSQL quoted identifiers are case-sensitive and normally limited to 63 bytes;
the ORM rejects oversized explicit names instead of relying on truncation.
[PostgreSQL 18 lexical structure](https://www.postgresql.org/docs/18/sql-syntax-lexical.html#SQL-SYNTAX-IDENTIFIERS).
Computed-column support is checked per engine, including the PostgreSQL virtual
column restrictions. [PostgreSQL 18 generated columns](https://www.postgresql.org/docs/18/ddl-generated-columns.html).
The integration cases validate the actual installed SQLite and PostgreSQL behavior.

## Validation

The final native suite passes **872 tests in 10:41** with real SQLite and
PostgreSQL enabled. Real Chrome JS and Dart WASM each pass **20 checks**, including
new session/optional-selection/write guards. Static analysis passes. Exact logs,
runtime source digest and validation limits are in
[the final record](validation/api-audit.md).

The first full attempt was stopped to complete the catalog-import correction.
It also exposed two existing decimal-average assertions that needed the shared
`QUERY.AGGREGATE` code, and a transient SQLite download TLS failure. Mutation
validation now uses the shared error code. Test consumers reuse the root's
content-addressed download cache through the normal hash-verifying sqlite3 hook.
The clean full rerun above supersedes that interrupted attempt.

No Android/Apple runtime or performance capture was repeated. Earlier captures
remain historical evidence, not certification of this refactor. No push or
package publication is part of this review.
