/// Compile-time schema declarations. Key selectors are analyzed as source and
/// never called with synthetic row values.
library;

import 'orm.dart' show Codec;
export 'orm.dart' show Codec, Codecs, SqlJson, Decimal, DecimalRounding;

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

/// Signed integer column storage. SQL expression results retain the int codec.
final class IntegerBits {
  final int value;
  const IntegerBits(this.value);
}

enum ReferentialAction { restrict, cascade, setNull, setDefault, noAction }

Entity<M> entity<M>({String? table}) => Entity<M>(table);

final class Entity<M> {
  final String? table;
  const Entity(this.table);
  EntityKey<M, K> key<K>(K Function(M) selector) => EntityKey(this, selector);
  SchemaConstraint primaryKey<K>(K Function(M) selector) =>
      const SchemaConstraint();
  SchemaConstraint unique<K>(K Function(M) selector) =>
      const SchemaConstraint();
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
}

final class SchemaConstraint {
  const SchemaConstraint();
}
