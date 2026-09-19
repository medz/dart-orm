part of '../sql.dart';

abstract interface class _CteDefinition {
  String get name;
  String _writeDefinition(_Writer writer);
}

/// A CTE exports SQL expression identities. Dart mapper properties are not
/// mistaken for SQL columns. ref() accepts only expressions the source selected.
final class Cte<R, F extends Fields> implements _CteDefinition {
  final Query<R, F> _source;
  @override
  final String name;
  final _SelectionPlan _plan;
  final _Decoder<R> _decode;
  late final Table<R, CteFields<F>> _table = _makeTable();

  factory Cte._(Query<R, F> source, String name) {
    if (name.isEmpty) throw ArgumentError('CTE name cannot be empty.');
    final (plan, decode) = source._plan(
      deduplicate: _sqlRowShape(source._selection) == null,
    );
    if (plan.relations.isNotEmpty) {
      throw const OrmException(
        'QUERY.CTE',
        'A CTE contains SQL columns, not batch-loaded relations.',
      );
    }
    return Cte._planned(source, name, plan, decode);
  }
  Cte._planned(this._source, this.name, this._plan, this._decode);

  Table<R, CteFields<F>> _makeTable() {
    final optional = {
      for (final join in [..._source._state.joins, ..._plan.joins])
        if (join.left) join.alias.fields.table,
    };
    final nullable = [
      for (final column in _plan.columns)
        column.codec.acceptsNull || _outerNullable(column._node, optional),
    ];
    final schema = TableSchema(
      name,
      columns: [
        for (var i = 0; i < _plan.columns.length; i++)
          Column(
            'c$i',
            nullable[i]
                ? _plan.columns[i].codec.nullable()
                : _plan.columns[i].codec,
            nullable: nullable[i],
          ),
      ],
    );
    return Table(
      schema,
      (table) => CteFields._(table, _source._fields, _plan, nullable),
      (fields) => _ReboundSelection(_decode, [
        for (var i = 0; i < _plan.columns.length; i++)
          Expr._(_ColumnNode(fields.table, 'c$i'), schema.columns[i].codec),
      ], source: _source._selection),
    );
  }

  Query<R, CteFields<F>> get query {
    final fields = _table.createFields(TableRef(_table.schema));
    return Query._(
      _source.database,
      fields,
      _QueryState(fields.table, ctes: [this]),
      _table.selectRow(fields),
    );
  }

  TableAlias<R, CteFields<F>> alias() => TableAlias._(_table, this);

  @override
  String _writeDefinition(_Writer writer) =>
      '${writer.quote(name)} '
      '(${[for (var i = 0; i < _plan.columns.length; i++) writer.quote('c$i')].join(', ')}) '
      'AS (${_source._write(writer, _plan)})';
}

final class CteFields<F extends Fields> extends Fields {
  final F _original;
  final _SelectionPlan _plan;
  final List<bool> _nullable;
  CteFields._(super.table, this._original, this._plan, this._nullable);

  Expr<T> ref<T>(Expr<T> Function(F) expression) {
    final original = expression(_original);
    final index = _plan.columns.indexWhere(
      (e) => _sameSqlNode(e._node, original._node),
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
    return Expr._(_ColumnNode(table, 'c$index'), original.codec);
  }
}

final class _ReboundSelection<R>(
  final _Decoder<R> decode,
  final List<Expr<Object?>> columns, {
  final Selection<Object?>? source,
}) extends Selection<R> {
  @override
  _Decoder<R> _bind(_SelectionPlan plan) {
    for (final column in columns) {
      plan.require(column);
    }
    final indices = [for (final column in columns) plan.column(column)];
    return (row) => decode([for (final index in indices) row[index]]);
  }
}
