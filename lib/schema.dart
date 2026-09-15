/// Compile-time schema declarations. Key selectors are analyzed as source and
/// never called with synthetic row values.
library;

import 'orm.dart' show Codec, ComputedStorage;
export 'orm.dart'
    show
        Codec,
        ComputedStorage,
        Codecs,
        SqlJson,
        Decimal,
        DecimalRounding,
        LocalDate,
        LocalTime,
        LocalDateTime;

/// A public const codec reference. Generation reads its type and storage tag;
/// it never executes the application's encode/decode functions.
final class UseCodec<T> {
  final Codec<T> codec;
  const UseCodec(this.codec);
}

/// Stable database text for an enum constant, independent of its Dart name.
final class EnumValue {
  final String value;
  const EnumValue(this.value);
}

final class Id {
  final bool generated;
  const Id() : generated = false;
  const Id.generated() : generated = true;
}

final class Unique {
  const Unique();
}

final class ColumnName {
  final String name;
  const ColumnName(this.name);
}

final class Default {
  final String expression;
  const Default.sql(this.expression);
}

/// Generates an omitted insert value in Dart. This never declares SQL DEFAULT.
/// The factory is referenced during generation, not invoked.
final class ClientDefault<T> {
  final T Function() factory;
  const ClientDefault(this.factory);
}

/// SQL computed by the database; omitted from generated writes.
final class Computed {
  final String expression;
  final String? sqlite, postgres;
  final ComputedStorage storage;
  const Computed.sql(
    this.expression, {
    this.sqlite,
    this.postgres,
    this.storage = ComputedStorage.stored,
  });
}

/// Signed integer column storage. SQL expression results retain the int codec.
final class IntegerBits {
  final int value;
  const IntegerBits(this.value);
}

/// Decimal column precision and scale, matching PostgreSQL NUMERIC(p, s).
final class DecimalDigits {
  final int precision;
  final int scale;
  const DecimalDigits(this.precision, [this.scale = 0]);
}

enum ReferentialAction { restrict, cascade, setNull, setDefault, noAction }

/// A fixed SQL file with declared result and parameter Record types.
/// Run query generation, then check the manifest against each target database.
SqlDeclaration<R, P> sqlQuery<R, P>({String? sqlite, String? postgres}) =>
    SqlDeclaration(sqlite, postgres);

final class SqlDeclaration<R, P> {
  final String? sqlite, postgres;
  const SqlDeclaration(this.sqlite, this.postgres);
}

Entity<M> entity<M>({String? table}) => Entity<M>(table);

final class Entity<M> {
  final String? table;
  const Entity(this.table);
  EntityKey<M, K> key<K>(K Function(M) selector) => EntityKey(this, selector);
  SchemaConstraint primaryKey<K>(K Function(M) selector) =>
      const SchemaConstraint();
  SchemaConstraint unique<K>(K Function(M) selector) =>
      const SchemaConstraint();

  /// Trusted SQL using physical column names. Omitted name uses the declaration
  /// name; explicit name: null preserves an unnamed imported constraint.
  SchemaConstraint check(
    String expression, {
    String? name,
    String? sqlite,
    String? postgres,
  }) => const SchemaConstraint();
  SchemaConstraint index<K>(
    K Function(M) selector, {
    String? name,
    bool unique = false,
  }) => const SchemaConstraint();
}

final class EntityKey<M, K> {
  final Entity<M> entity;
  final K Function(M) selector;
  const EntityKey(this.entity, this.selector);
  SchemaConstraint references<N>(
    EntityKey<N, K> target, {
    String? inverse,
    ReferentialAction onDelete = ReferentialAction.restrict,
  }) => const SchemaConstraint();

  /// Read-only query navigation without a database foreign key. Matching rows
  /// may be absent or duplicated; this declaration creates no write effects.
  SchemaConstraint relatesTo<N>(EntityKey<N, K> target, {String? inverse}) =>
      const SchemaConstraint();
}

final class SchemaConstraint {
  const SchemaConstraint();
}
