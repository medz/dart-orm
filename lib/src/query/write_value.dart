import 'expression.dart';
import 'mutation.dart';
import 'table.dart';

/// A reusable typed write intent, before it is bound to a table occurrence.
///
/// Omission, a literal (including an allowed null), SQL DEFAULT and an SQL
/// expression remain distinct while generated inputs are composed and forwarded.
/// Creating or overlaying an intent does not evaluate an expression or a client
/// default. Expressions are evaluated and literals encoded when the input enters
/// a mutation builder. Mutable literal objects and captured application state
/// remain caller-owned and must remain stable until then.
/// Bound byte storage is copied into a read-only snapshot. Other mutable
/// storage returned by custom codecs must remain stable for every replay.
sealed class WriteValue<T, F extends Fields> {
  const WriteValue._();

  /// Omits this field. During overlay, omission preserves the earlier intent.
  const factory WriteValue.keep() = _Keep<T, F>;

  /// Supplies a literal, which is encoded when the mutation is prepared.
  const factory WriteValue.set(T value) = _Set<T, F>;

  /// Requests the database default rather than a client default.
  ///
  /// The mutation compiler checks whether this is legal for the column and
  /// database engine before executing SQL.
  const factory WriteValue.databaseDefault() = _Default<T, F>;

  /// Supplies an expression constructed against the actual mutation fields.
  const factory WriteValue.expression(Expr<T> Function(F) expression) =
      _Expression<T, F>;

  /// Whether this intent represents an omitted field.
  bool get isMissing => this is _Keep<T, F>;

  /// Uses the later supplied intent, or keeps the earlier one when omitted.
  ///
  /// This is static so the runtime type of an inferred `WriteValue<Never, F>`
  /// cannot narrow the accepted type of a later value through covariance.
  static WriteValue<T, F> overlay<T, F extends Fields>(
    WriteValue<T, F> earlier,
    WriteValue<T, F> later,
  ) => later.isMissing ? earlier : later;
}

final class _Keep<T, F extends Fields> extends WriteValue<T, F> {
  const _Keep() : super._();
}

final class _Set<T, F extends Fields> extends WriteValue<T, F> {
  final T value;
  const _Set(this.value) : super._();
}

final class _Default<T, F extends Fields> extends WriteValue<T, F> {
  const _Default() : super._();
}

final class _Expression<T, F extends Fields> extends WriteValue<T, F> {
  final Expr<T> Function(F) expression;
  const _Expression(this.expression) : super._();
}

/// Binds a typed input intent using the ordinary mutation assignment path.
extension WriteValueField<T> on Field<T> {
  /// Produces no assignment for omission, and one for a supplied intent.
  ///
  /// Expression callbacks and literal codecs run here, before SQL execution.
  /// Generated input builders call this once per surviving field intent.
  List<Assignment> write<F extends Fields>(WriteValue<T, F> input, F fields) =>
      switch (input) {
        _Keep<T, F>() => [],
        _Set<T, F>(:final value) => [set(value)],
        _Default<T, F>() => [defaultValue()],
        _Expression<T, F>(:final expression) => [
          setExpression(expression(fields)),
        ],
      };
}
