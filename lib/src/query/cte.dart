import 'package:meta/meta.dart';

import '../../schema_model.dart';
import 'expression.dart';
import 'joins.dart';
import 'nodes.dart';
import 'query.dart';
import 'selection.dart';
import 'table.dart';
import 'union.dart';

/// @nodoc
@internal
abstract interface class CteDefinition {
  String get name;
  String writeDefinition(SqlWriter writer);
}

/// A CTE exports SQL expression identities. Dart mapper properties are not
/// mistaken for SQL columns. ref() accepts only expressions the source selected.
///
/// Create one with [Query.asCte]. Accessing [query] or [alias] only builds a
/// description; database work starts when the resulting query executes.
final class Cte<R, F extends Fields> implements CteDefinition {
  final Query<R, F> _source;

  /// SQL name used for this common table expression.
  @override
  final String name;

  /// @nodoc
  @internal
  final SelectionPlan planQuery;
  final RowDecoder<R> _decode;
  late final Table<R, CteFields<F>> _table = _makeTable();

  /// @nodoc
  @internal
  factory Cte.internal(Query<R, F> source, String name) {
    if (name.isEmpty) throw ArgumentError('CTE name cannot be empty.');
    final (plan, decode) = source.planQuery(
      deduplicate: sqlRowShape(source.querySelection) == null,
    );
    if (plan.relations.isNotEmpty) {
      throw const OrmException(
        'QUERY.CTE',
        'A CTE contains SQL columns, not batch-loaded relations.',
      );
    }
    return Cte._planned(source, name, plan, decode);
  }
  Cte._planned(this._source, this.name, this.planQuery, this._decode);

  Table<R, CteFields<F>> _makeTable() {
    final optional = {
      for (final join in [..._source.queryState.joins, ...planQuery.joins])
        if (join.left) join.alias.fields.table,
    };
    final nullable = [
      for (final column in planQuery.columns)
        column.codec.acceptsNull ||
            outerNullable(column.expressionNode, optional),
    ];
    final schema = TableSchema(
      name,
      columns: [
        for (var i = 0; i < planQuery.columns.length; i++)
          Column(
            'c$i',
            nullable[i]
                ? planQuery.columns[i].codec.nullable()
                : planQuery.columns[i].codec,
            nullable: nullable[i],
          ),
      ],
    );
    return Table(
      schema,
      (table) =>
          CteFields.internal(table, _source.queryFields, planQuery, nullable),
      (fields) => ReboundSelection(_decode, [
        for (var i = 0; i < planQuery.columns.length; i++)
          Expr.internal(
            ColumnNode(fields.table, 'c$i'),
            schema.columns[i].codec,
          ),
      ], source: _source.querySelection),
    );
  }

  /// Starts a query over the CTE while retaining the source's decoded row type.
  ///
  /// The result belongs to the same database or transaction view as its source.
  Query<R, CteFields<F>> get query {
    final fields = _table.createFields(TableRef(_table.schema));
    return Query.internal(
      _source.database,
      fields,
      QueryState(fields.table, ctes: [this]),
      _table.selectRow(fields),
    );
  }

  /// Creates a fresh CTE occurrence for a join or self join.
  TableAlias<R, CteFields<F>> alias() => TableAlias.internal(_table, this);

  /// @nodoc
  @internal
  @override
  String writeDefinition(SqlWriter writer) =>
      '${writer.quote(name)} '
      '(${[for (var i = 0; i < planQuery.columns.length; i++) writer.quote('c$i')].join(', ')}) '
      'AS (${_source.writeQuery(writer, planQuery)})';
}

/// SQL columns exported by a CTE, referenced through its original expressions.
final class CteFields<F extends Fields> extends Fields {
  /// @nodoc
  @internal
  final F sourceFields;

  /// @nodoc
  @internal
  final SelectionPlan planQuery;
  final List<bool> _nullable;

  /// @nodoc
  @internal
  CteFields.internal(
    super.table,
    this.sourceFields,
    this.planQuery,
    this._nullable,
  );

  /// References an expression selected by the CTE's source query.
  ///
  /// The expression must match an exported SQL column. Columns made nullable by
  /// a left join require a nullable reference; Dart mapper properties are not
  /// SQL columns and cannot be referenced here.
  Expr<T> ref<T>(Expr<T> Function(F) expression) {
    final original = expression(sourceFields);
    final index = planQuery.columns.indexWhere(
      (e) => sameSqlNode(e.expressionNode, original.expressionNode),
    );
    if (index < 0) {
      throw const OrmException(
        'QUERY.CTE_COLUMN',
        'The CTE did not export this SQL expression.',
      );
    }
    if (_nullable[index] && !original.codec.acceptsNull) {
      throw const OrmException(
        'QUERY.NULLABILITY',
        'This CTE column is nullable; reference it with a nullable expression.',
      );
    }
    return Expr.internal(ColumnNode(table, 'c$index'), original.codec);
  }
}

/// @nodoc
@internal
final class ReboundSelection<R>(
  final RowDecoder<R> decode,
  final List<Expr<Object?>> columns, {
  final Selection<Object?>? source,
}) extends Selection<R> {
  @override
  RowDecoder<R> bindSelection(SelectionPlan plan) {
    for (final column in columns) {
      plan.require(column);
    }
    final indices = [for (final column in columns) plan.column(column)];
    return (row) => decode([for (final index in indices) row[index]]);
  }
}
