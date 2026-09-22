/// Typed SQL construction, projections and query inspection.
///
/// [SqlBuilder] compiles a query without opening a connection. Select a scalar,
/// a typed Record with `.row`, or map selected values into an application model.
/// Executing a query requires binding it to an ORM database session.
///
/// {@category Queries}
/// {@canonicalFor context.QueryContext}
/// {@canonicalFor context.SqlBuilder}
/// {@canonicalFor expression.Expr}
/// {@canonicalFor expression.value}
/// {@canonicalFor expression.sql}
/// {@canonicalFor expression.Predicate}
/// {@canonicalFor expression.TextExpression}
/// {@canonicalFor expression.NumericExpression}
/// {@canonicalFor expression.OrderTerm}
/// {@canonicalFor expression.TimeExpression}
/// {@canonicalFor expression.LocalDateTimeExpression}
/// {@canonicalFor expression.InstantExpression}
/// {@canonicalFor expression.DecimalExpression}
/// {@canonicalFor selection.Selection}
/// {@canonicalFor selection.Selection2}
/// {@canonicalFor selection.Selection3}
/// {@canonicalFor selection.Selection4}
/// {@canonicalFor selection.Selection5}
/// {@canonicalFor selection.Selection6}
/// {@canonicalFor selection.fields}
/// {@canonicalFor table.TableRef}
/// {@canonicalFor table.Fields}
/// {@canonicalFor table.ReadField}
/// {@canonicalFor table.Field}
/// {@canonicalFor table.NumericField}
/// {@canonicalFor table.Table}
/// {@canonicalFor table.Change}
/// {@canonicalFor table.ChangeField}
/// {@canonicalFor query.Query}
/// {@canonicalFor query.TableSet}
/// {@canonicalFor plan.PlannedColumn}
/// {@canonicalFor plan.PlannedJoin}
/// {@canonicalFor plan.QueryPlan}
/// {@canonicalFor plan.RelationLoadPlan}
/// {@canonicalFor mutation.Assignment}
/// {@canonicalFor mutation.Mutation}
/// {@canonicalFor mutation.Returning}
/// {@canonicalFor relation.ToOneStrategy}
/// {@canonicalFor relation.Relation}
/// {@canonicalFor batch.BatchInsert}
/// {@canonicalFor batch.BatchReturning}
/// {@canonicalFor joins.TableAlias}
/// {@canonicalFor joins.WindowFrame}
/// {@canonicalFor joins.rowNumber}
/// {@canonicalFor joins.rank}
/// {@canonicalFor cte.Cte}
/// {@canonicalFor cte.CteFields}
/// {@canonicalFor cursor.NullOrder}
/// {@canonicalFor cursor.CursorTerm}
/// {@canonicalFor cursor.KeysetQuery}
/// {@canonicalFor union.SqlRow2}
/// {@canonicalFor union.SqlRow3}
/// {@canonicalFor union.SqlRow4}
/// {@canonicalFor union.SqlRow5}
/// {@canonicalFor union.SqlRow6}
/// {@canonicalFor union.SetQueries}
/// {@canonicalFor union.UnionFields}
/// {@canonicalFor stream.QueryStreaming}
/// {@canonicalFor raw_sql.Sql}
/// {@canonicalFor raw_sql.SqlValue}
/// {@canonicalFor raw_sql.SqlQuery}
/// {@canonicalFor raw_sql.ColumnSql}
/// {@canonicalFor raw_sql.FieldSql}
/// {@canonicalFor result.ResultShape}
/// {@canonicalFor result.ResultColumn}
/// {@canonicalFor result.Result2}
/// {@canonicalFor result.Result3}
/// {@canonicalFor result.Result4}
/// {@canonicalFor result.Result5}
/// {@canonicalFor result.Result6}
/// {@canonicalFor raw_execution.SqlExecution}
library;

export 'driver.dart';
export 'schema_model.dart';
export 'src/query/context.dart' show QueryContext, SqlBuilder;
export 'src/query/expression.dart'
    show
        Expr,
        value,
        sql,
        Predicate,
        TextExpression,
        NumericExpression,
        OrderTerm,
        TimeExpression,
        LocalDateTimeExpression,
        InstantExpression,
        DecimalExpression;
export 'src/query/selection.dart'
    show
        Selection,
        Selection2,
        Selection3,
        Selection4,
        Selection5,
        Selection6,
        fields;
export 'src/query/table.dart'
    show
        TableRef,
        Fields,
        ReadField,
        Field,
        NumericField,
        Table,
        Change,
        ChangeField;
export 'src/query/query.dart' show Query, TableSet;
export 'src/query/plan.dart'
    show PlannedColumn, PlannedJoin, QueryPlan, RelationLoadPlan;
export 'src/query/mutation.dart' show Assignment, Mutation, Returning;
export 'src/query/relation.dart' show ToOneStrategy, Relation;
export 'src/query/batch.dart' show BatchInsert, BatchReturning;
export 'src/query/joins.dart' show TableAlias, WindowFrame, rowNumber, rank;
export 'src/query/cte.dart' show Cte, CteFields;
export 'src/query/cursor.dart' show NullOrder, CursorTerm, KeysetQuery;
export 'src/query/union.dart'
    show SqlRow2, SqlRow3, SqlRow4, SqlRow5, SqlRow6, SetQueries, UnionFields;
export 'src/query/stream.dart' show QueryStreaming;

export 'src/query/raw_sql.dart'
    show Sql, SqlValue, SqlQuery, ColumnSql, FieldSql;
export 'src/query/result.dart'
    show ResultShape, ResultColumn, Result2, Result3, Result4, Result5, Result6;
export 'src/query/raw_execution.dart' show SqlExecution;
