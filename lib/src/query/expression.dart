import 'package:meta/meta.dart';

import '../../driver.dart';
import '../../schema_model.dart';
import 'cursor.dart';
import 'joins.dart';
import 'nodes.dart';
import 'query.dart';
import 'selection.dart';
import 'table.dart';

/// A typed operand accepted by SQL comparison expressions.
///
/// Pass an [Expr] directly to compare SQL expressions. Wrap a Dart value with
/// `Operand.value`, or contextual `.value(...)`, to bind it using the left-hand
/// expression's codec. Constructing an operand performs no encoding or I/O.
/// Expression operands compare SQL storage values without either codec's Dart
/// encoder or decoder. Ensure their storage representations and collations are
/// compatible, especially when distinct custom codecs share one Dart type.
sealed class Operand<T> {
  const Operand._();

  /// A Dart value to parameterize with the receiving expression's codec.
  ///
  /// For equality and inequality, a null value means `IS NULL` or `IS NOT NULL`.
  /// Null operands in ordered comparisons retain SQL UNKNOWN semantics.
  const factory Operand.value(T value) = _Value<T>;
}

final class _Value<T> extends Operand<T> {
  final T value;
  const _Value(this.value) : super._();
}

/// A typed SQL expression that can also be selected as a result.
///
/// Operators build SQL without executing it. The codec controls bound values and
/// result decoding; nullable predicates retain SQL three-valued logic.
class Expr<T> extends Selection<T> implements Operand<T> {
  /// @nodoc
  @internal
  final SqlNode expressionNode;

  /// Encodes parameters and decodes this expression's result column.
  final Codec<T> codec;

  /// @nodoc
  @internal
  Expr.internal(SqlNode node, this.codec)
    : expressionNode = switch (codec.sqlType) {
        'decimal' when node is! DecimalNode => DecimalNode(node),
        'date' || 'time' || 'local_datetime' || 'instant'
            when node is! TemporalNode =>
          TemporalNode(node, codec.sqlType),
        _ => node,
      };

  /// Compares with a value or SQL expression using `=`.
  ///
  /// A literal `.value(null)` produces `IS NULL`. Expression operands retain SQL
  /// NULL semantics: a NULL on either side yields SQL UNKNOWN.
  Expr<bool?> eq(Operand<T> other) => other is _Value<T> && other.value == null
      ? isNull()
      : _compare('=', _operand(other));

  /// Compares with a value or SQL expression using `<>`.
  ///
  /// A literal `.value(null)` produces `IS NOT NULL`. Expression operands retain
  /// SQL NULL semantics.
  Expr<bool?> ne(Operand<T> other) => other is _Value<T> && other.value == null
      ? isNotNull()
      : _compare('<>', _operand(other));

  /// Tests whether this expression is greater than [other].
  ///
  /// Literal operands are encoded by this expression's codec. A SQL NULL on
  /// either side makes the result SQL UNKNOWN.
  Expr<bool?> gt(Operand<T> other) => _compare('>', _operand(other));

  /// Tests whether this expression is greater than or equal to [other].
  ///
  /// SQL NULL on either side makes the result SQL UNKNOWN.
  Expr<bool?> gte(Operand<T> other) => _compare('>=', _operand(other));

  /// Tests whether this expression is less than [other].
  ///
  /// SQL NULL on either side makes the result SQL UNKNOWN.
  Expr<bool?> lt(Operand<T> other) => _compare('<', _operand(other));

  /// Tests whether this expression is less than or equal to [other].
  ///
  /// SQL NULL on either side makes the result SQL UNKNOWN.
  Expr<bool?> lte(Operand<T> other) => _compare('<=', _operand(other));

  SqlNode _operand(Operand<T> other) => switch (other) {
    Expr<T>() => other.expressionNode,
    _Value<T>() => ParameterNode(
      codec.encode(other.value),
      storageType: codec.sqlType,
    ),
  };

  Expr<bool?> _compare(String op, SqlNode right) => Expr.internal(
    BinaryNode(expressionNode, op, right),
    Codecs.boolean.nullable(),
  );

  /// Tests for SQL NULL, yielding a non-null boolean.
  Expr<bool> isNull() => Expr.internal(
    UnaryNode('IS NULL', expressionNode, postfix: true),
    Codecs.boolean,
  );

  /// Tests for a non-NULL value, yielding a non-null boolean.
  Expr<bool> isNotNull() => Expr.internal(
    UnaryNode('IS NOT NULL', expressionNode, postfix: true),
    Codecs.boolean,
  );

  /// Tests membership in separately bound values; an empty list is false.
  Expr<bool?> isIn(Iterable<T> values) => Expr.internal(
    InNode(expressionNode, [
      for (final value in values)
        ParameterNode(codec.encode(value), storageType: codec.sqlType),
    ]),
    Codecs.boolean.nullable(),
  );

  /// Tests membership in a subquery selecting one SQL expression.
  ///
  /// The subquery must belong to the enclosing query's context and dialect.
  Expr<bool?> isInQuery<F extends Fields>(Query<T, F> query) {
    if (query.querySelection is! Expr<T>) {
      throw const OrmException(
        'QUERY.SCALAR',
        'IN subqueries select one SQL expression.',
      );
    }
    return Expr.internal(
      BinaryNode(expressionNode, 'IN', SubqueryNode(query)),
      Codecs.boolean.nullable(),
    );
  }

  /// Turns an aggregate into a window expression.
  ///
  /// Partition and ordering expressions cannot contain nested windows. The selected
  /// database must support window functions.
  Expr<T> over({
    List<Expr<Object?>> partitionBy = const [],
    List<OrderTerm> orderBy = const [],
    WindowFrame? frame,
  }) {
    final function = unwrapStorage(expressionNode);
    if ((function is! FunctionNode && function is! DecimalAverage) ||
        !aggregate(function)) {
      throw const OrmException(
        'QUERY.WINDOW',
        'over() applies to an aggregate expression.',
      );
    }
    if ([
      ...partitionBy.map((e) => e.expressionNode),
      ...orderBy.map((o) => o.expression.expressionNode),
    ].any(window)) {
      throw const OrmException(
        'QUERY.WINDOW',
        'Window partition/order expressions cannot contain another window.',
      );
    }
    return Expr.internal(
      WindowNode(
        function,
        List.unmodifiable(partitionBy),
        List.unmodifiable(orderBy),
        frame,
      ),
      codec,
    );
  }

  /// Orders ascending, optionally specifying where NULL values appear.
  OrderTerm asc({NullOrder? nulls}) => OrderTerm.internal(this, false, nulls);

  /// Orders descending, optionally specifying where NULL values appear.
  OrderTerm desc({NullOrder? nulls}) => OrderTerm.internal(this, true, nulls);

  /// Builds a typed keyset boundary from this expression and a row value.
  CursorTerm cursor(T value, {bool descending = false, NullOrder? nulls}) =>
      CursorTerm.internal(
        OrderTerm.internal(this, descending, nulls),
        codec.encode(value),
      );

  /// Counts non-NULL values, optionally counting only distinct values.
  Expr<int> count({bool distinct = false}) => Expr.internal(
    FunctionNode('COUNT', [expressionNode], distinct: distinct),
    Codecs.integer,
  );

  /// Selects the minimum value, or null for an empty group.
  Expr<T?> min() =>
      Expr.internal(FunctionNode('MIN', [expressionNode]), codec.nullable());

  /// Selects the maximum value, or null for an empty group.
  Expr<T?> max() =>
      Expr.internal(FunctionNode('MAX', [expressionNode]), codec.nullable());

  /// @nodoc
  @internal
  @override
  RowDecoder<T> bindSelection(SelectionPlan plan) {
    plan.require(this);
    final index = plan.column(this);
    return (row) => codec.decode(row[index]);
  }
}

/// Creates a bound SQL value using an explicit storage codec.
Expr<T> value<T>(T value, Codec<T> codec) => Expr.internal(
  ParameterNode(codec.encode(value), sqlType: codec.sqlType),
  codec,
);

/// [parts] are trusted SQL, [values] are expressions. Never put user input in parts.
Expr<T> sql<T>(List<String> parts, List<Expr<Object?>> values, Codec<T> codec) {
  if (parts.length != values.length + 1) {
    throw ArgumentError('SQL needs one more text part than expression.');
  }
  for (final part in parts) {
    checkSqlText(part);
  }
  return Expr.internal(
    RawNode(List.of(parts), [for (final v in values) v.expressionNode]),
    codec,
  );
}

/// Requires every predicate to be SQL TRUE; an empty group is TRUE.
///
/// The iterable is consumed once when this expression is built. SQL NULL
/// retains its three-valued meaning. Use collection `if` and `for` elements
/// to construct dynamic groups, and [anyOf] for alternatives.
Expr<bool?> allOf(Iterable<Expr<bool?>> predicates) =>
    _predicateGroup(predicates, 'AND', true);

/// Requires at least one predicate to be SQL TRUE; an empty group is FALSE.
///
/// The iterable is consumed once when this expression is built. SQL NULL
/// retains its three-valued meaning. Nest this with [allOf] to express groups.
Expr<bool?> anyOf(Iterable<Expr<bool?>> predicates) =>
    _predicateGroup(predicates, 'OR', false);

Expr<bool?> _predicateGroup(
  Iterable<Expr<bool?>> predicates,
  String operator,
  bool empty,
) {
  final iterator = predicates.iterator;
  if (!iterator.moveNext()) return value(empty, Codecs.boolean);
  var node = iterator.current.expressionNode;
  while (iterator.moveNext()) {
    node = BinaryNode(node, operator, iterator.current.expressionNode);
  }
  return Expr.internal(node, Codecs.boolean.nullable());
}

/// Boolean negation using SQL's three-valued NULL semantics.
extension Predicate on Expr<bool?> {
  /// Negates this predicate; SQL NULL remains unknown.
  Expr<bool?> not() => Expr.internal(
    UnaryNode('NOT', expressionNode),
    Codecs.boolean.nullable(),
  );
}

/// String operations evaluated by the selected database, preserving SQL NULL.
///
/// Matching and case conversion follow database collation and Unicode rules.
extension TextExpression<T extends String?> on Expr<T> {
  /// Matches a bound SQL LIKE pattern; `%` and `_` remain wildcards.
  Expr<bool?> like(String pattern) => _compare('LIKE', ParameterNode(pattern));

  /// Matches literal text anywhere, escaping LIKE wildcards `%`, `_` and `!`.
  ///
  /// The escaped pattern is bound as a parameter with SQL `ESCAPE '!'`.
  /// An empty [text] matches every non-NULL string. NULL inputs produce NULL.
  Expr<bool?> contains(String text) => _literalLike(text, '%', '%');

  /// Matches a literal prefix; LIKE wildcards in [text] have no special meaning.
  ///
  /// An empty prefix matches every non-NULL string. NULL inputs produce NULL.
  Expr<bool?> startsWith(String text) => _literalLike(text, '', '%');

  /// Matches a literal suffix; LIKE wildcards in [text] have no special meaning.
  ///
  /// An empty suffix matches every non-NULL string. NULL inputs produce NULL.
  Expr<bool?> endsWith(String text) => _literalLike(text, '%', '');

  Expr<bool?> _literalLike(String text, String prefix, String suffix) {
    final escaped = text
        .replaceAll('!', '!!')
        .replaceAll('%', '!%')
        .replaceAll('_', '!_');
    return Expr.internal(
      LikeNode(expressionNode, ParameterNode('$prefix$escaped$suffix')),
      Codecs.boolean.nullable(),
    );
  }

  /// Converts text to lowercase using database rules, preserving nullability.
  ///
  /// Decodes the derived value with the standard text codec, without applying
  /// the source expression's custom or mapped decoder.
  Expr<T> lower() =>
      Expr.internal(FunctionNode('LOWER', [expressionNode]), _textResultCodec);

  /// Converts text to uppercase using database rules, preserving nullability.
  ///
  /// Decodes the derived value with the standard text codec, without applying
  /// the source expression's custom or mapped decoder.
  Expr<T> upper() =>
      Expr.internal(FunctionNode('UPPER', [expressionNode]), _textResultCodec);

  Codec<T> get _textResultCodec =>
      (null is T ? Codecs.text.nullable() : Codecs.text) as Codec<T>;
}

/// SQL arithmetic and aggregation for Dart numeric values.
extension NumericExpression<T extends num> on Expr<T> {
  /// Adds a bound value in SQL.
  Expr<T> plus(T n) => Expr.internal(
    BinaryNode(
      expressionNode,
      '+',
      ParameterNode(codec.encode(n), storageType: codec.sqlType),
    ),
    codec,
  );

  /// Subtracts a bound value in SQL.
  Expr<T> minus(T n) => Expr.internal(
    BinaryNode(
      expressionNode,
      '-',
      ParameterNode(codec.encode(n), storageType: codec.sqlType),
    ),
    codec,
  );

  /// Multiplies by a bound value in SQL.
  Expr<T> times(T n) => Expr.internal(
    BinaryNode(
      expressionNode,
      '*',
      ParameterNode(codec.encode(n), storageType: codec.sqlType),
    ),
    codec,
  );

  /// Sums values, returning null for an empty group.
  Expr<T?> sum() =>
      Expr.internal(FunctionNode('SUM', [expressionNode]), codec.nullable());

  /// Computes a floating-point SQL average, or null for an empty group.
  Expr<double?> average() => Expr.internal(
    FunctionNode('AVG', [expressionNode]),
    Codecs.real.nullable(),
  );
}

/// An expression's sort direction and optional NULL ordering policy.
final class OrderTerm {
  /// The SQL expression to order by.
  final Expr<Object?> expression;

  /// Whether larger values appear first.
  final bool descending;

  /// Explicit NULL ordering, or null to use the database default.
  final NullOrder? nulls;

  /// @nodoc
  @internal
  const OrderTerm.internal(this.expression, this.descending, [this.nulls]);

  /// @nodoc
  @internal
  String writeQuery(SqlWriter writer) {
    final text = expression.expressionNode.write(writer);
    if (writer.mysql && nulls != null) {
      return '($text IS NULL) ${nulls == NullOrder.first ? 'DESC' : 'ASC'}, '
          '${expression.expressionNode.write(writer)} ${descending ? 'DESC' : 'ASC'}';
    }
    return '$text$orderSuffix';
  }

  /// @nodoc
  @internal
  String get orderSuffix =>
      ' ${descending ? 'DESC' : 'ASC'}'
      '${nulls == null ? '' : ' NULLS ${nulls!.name.toUpperCase()}'}';
}

/// @nodoc
@internal
String projection(Expr<Object?> expression, SqlWriter writer) {
  final text = expression.expressionNode.write(writer);
  // Preserve JSON null separately from SQL NULL through native driver decoders.
  return writer.mysql && expression.codec.sqlType == 'json'
      ? 'CAST($text AS CHAR CHARACTER SET utf8mb4)'
      : text;
}

/// @nodoc
@internal
void checkTemporalPrecision(int digits) {
  if (digits < 0 || digits > 6) throw RangeError.range(digits, 0, 6, 'digits');
}

/// Precision control for SQL time expressions.
extension TimeExpression<T extends LocalTime?> on Expr<T> {
  /// Rounds to the requested fractional-second digits (0 through 6).
  Expr<T> withPrecision(int digits) {
    checkTemporalPrecision(digits);
    return Expr.internal(TemporalCast(expressionNode, 'time', digits), codec);
  }
}

/// Precision control for local timestamps without a time zone.
extension LocalDateTimeExpression<T extends LocalDateTime?> on Expr<T> {
  /// Rounds to the requested fractional-second digits (0 through 6).
  Expr<T> withPrecision(int digits) {
    checkTemporalPrecision(digits);
    return Expr.internal(
      TemporalCast(expressionNode, 'local_datetime', digits),
      codec,
    );
  }
}

/// Precision control for UTC instant expressions.
extension InstantExpression<T extends DateTime?> on Expr<T> {
  /// Rounds to the requested fractional-second digits (0 through 6).
  Expr<T> withPrecision(int digits) {
    checkTemporalPrecision(digits);
    return Expr.internal(
      TemporalCast(expressionNode, 'instant', digits),
      codec,
    );
  }
}

/// Exact decimal arithmetic using the selected database's capabilities.
extension DecimalExpression<T extends Decimal?> on Expr<T> {
  /// Averages non-null inputs, rounding once at the requested result scale.
  /// Empty/all-null input returns null; the default rejects lost digits.
  Expr<Decimal?> average({
    required int scale,
    DecimalRounding rounding = DecimalRounding.exact,
  }) {
    Decimal.validateScale(scale);
    if (window(expressionNode)) {
      throw const OrmException(
        'QUERY.WINDOW',
        'Project a window result through a CTE before averaging it.',
      );
    }
    return Expr.internal(
      DecimalAverage(expressionNode, scale, rounding),
      Codecs.decimal.nullable(),
    );
  }

  /// Rounds in SQL; [DecimalRounding.exact] rejects any lost nonzero digits.
  Expr<T> rounded(
    int scale, {
    DecimalRounding rounding = DecimalRounding.exact,
  }) {
    Decimal.validateScale(scale);
    return Expr.internal(
      DecimalRatio(expressionNode, null, scale, rounding),
      codec,
    );
  }

  /// Divides in SQL to an explicit scale without a floating-point intermediate.
  Expr<T> divide(
    Decimal divisor, {
    required int scale,
    DecimalRounding rounding = DecimalRounding.exact,
  }) {
    Decimal.validateScale(scale);
    return Expr.internal(
      DecimalRatio(
        expressionNode,
        value(divisor, Codecs.decimal).expressionNode,
        scale,
        rounding,
      ),
      codec,
    );
  }

  /// Divides two SQL expressions. A null operand produces null.
  Expr<Decimal?> divideExpression(
    Expr<Decimal?> divisor, {
    required int scale,
    DecimalRounding rounding = DecimalRounding.exact,
  }) {
    Decimal.validateScale(scale);
    return Expr.internal(
      DecimalRatio(expressionNode, divisor.expressionNode, scale, rounding),
      Codecs.decimal.nullable(),
    );
  }

  /// Rounds and checks a decimal against the requested precision and scale.
  Expr<T> constrained(int precision, int scale) {
    Decimal.validateDigits(precision, scale);
    return Expr.internal(DecimalCast(expressionNode, precision, scale), codec);
  }

  /// Adds an exactly encoded decimal value.
  Expr<T> plus(Decimal n) => _arithmetic('+', value(n, Codecs.decimal));

  /// Subtracts an exactly encoded decimal value.
  Expr<T> minus(Decimal n) => _arithmetic('-', value(n, Codecs.decimal));

  /// Multiplies by an exactly encoded decimal value.
  Expr<T> times(Decimal n) => _arithmetic('*', value(n, Codecs.decimal));

  /// Adds another decimal SQL expression.
  Expr<Decimal?> plusExpression(Expr<Decimal?> other) => _binary('+', other);

  /// Subtracts another decimal SQL expression.
  Expr<Decimal?> minusExpression(Expr<Decimal?> other) => _binary('-', other);

  /// Multiplies by another decimal SQL expression.
  Expr<Decimal?> timesExpression(Expr<Decimal?> other) => _binary('*', other);
  Expr<T> _arithmetic(String op, Expr<Decimal> other) => Expr.internal(
    DecimalArithmetic(expressionNode, op, other.expressionNode),
    codec,
  );
  Expr<Decimal?> _binary(String op, Expr<Decimal?> other) => Expr.internal(
    DecimalArithmetic(expressionNode, op, other.expressionNode),
    Codecs.decimal.nullable(),
  );

  /// Sums decimal values exactly, returning null for an empty group.
  Expr<Decimal?> sum({bool distinct = false}) => Expr.internal(
    FunctionNode('SUM', [expressionNode], decimal: true, distinct: distinct),
    Codecs.decimal.nullable(),
  );
}
