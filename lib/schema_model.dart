/// Physical table, column, key, index, and constraint metadata.
///
/// [TableSchema] and [Column] describe storage independently of Dart row models,
/// generated clients, and live connections. They can be assembled directly for
/// schema tooling or consumed from generated Dart snapshots.
///
/// Collection inputs to [TableSchema] are copied into immutable lists. Creating
/// metadata does not apply DDL: migration tooling validates the target engine and
/// executes reviewed schema changes separately.
///
/// Use `package:orm/schema.dart` for application model declarations.
///
/// {@category Schema}
/// {@canonicalFor model.CheckSchema}
/// {@canonicalFor model.Column}
/// {@canonicalFor model.ComputedColumn}
/// {@canonicalFor model.ComputedStorage}
/// {@canonicalFor model.ForeignKey}
/// {@canonicalFor model.IndexSchema}
/// {@canonicalFor model.TableSchema}
library;

export 'values.dart';
export 'driver.dart' show SqlDialect;
export 'src/schema/model.dart'
    show
        CheckSchema,
        Column,
        ComputedColumn,
        ComputedStorage,
        ForeignKey,
        IndexSchema,
        TableSchema;
