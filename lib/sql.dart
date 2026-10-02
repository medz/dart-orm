/// Parameterized SQL execution, typed expressions and query inspection.
///
/// [SqlBuilder] compiles a query without opening a connection. Select a scalar,
/// a typed Record with `.row`, or map selected values into an application model.
/// [SqlDatabase] executes [Sql] without model declarations or generation. Typed
/// table queries bind to an ORM view of that same runtime. Named [Projection]
/// outputs retain their field names through CTE and UNION composition.
///
/// {@category Queries}
/// {@canonicalFor context.QueryContext}
/// {@canonicalFor context.SqlBuilder}
/// {@canonicalFor expression.Operand}
/// {@canonicalFor expression.Expr}
/// {@canonicalFor expression.allOf}
/// {@canonicalFor expression.anyOf}
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
/// {@canonicalFor query.Query}
/// {@canonicalFor query.SelectQuery}
/// {@canonicalFor query.TableQuery}
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
/// {@canonicalFor cte.DerivedQuery}
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
/// {@canonicalFor database.SqlDatabase}
/// {@canonicalFor database.SqlDatabaseStreaming}
/// {@canonicalFor events.QueryOperation}
/// {@canonicalFor events.QueryEvent}
/// {@canonicalFor events.AcquisitionEvent}
/// {@canonicalFor options.TransactionOptions}
/// {@canonicalFor options.Isolation}
/// {@canonicalFor options.PostgresTransaction}
/// {@canonicalFor options.SqliteTransactionMode}
/// {@canonicalFor options.SqliteTransaction}
/// {@canonicalFor options.MysqlTransaction}
/// {@canonicalFor options.MariadbTransaction}
/// {@canonicalFor transaction.TransactionRetry}
/// {@canonicalFor sql_check.SqlCheck}
/// {@canonicalFor sql_check.checkSqlQuery}
library;

export 'src/query/runtime_execution.dart' show RuntimeSqlExecution;
export 'src/query/context.dart' show QueryContext, SqlBuilder;
export 'src/query/expression.dart'
    show
        Operand,
        Expr,
        allOf,
        anyOf,
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
    show TableRef, Fields, ReadField, Field, NumericField, Table;
export 'src/query/query.dart' show Query, SelectQuery, TableQuery, TableSet;
export 'src/query/write_value.dart' show WriteValue, WriteValueField;
export 'src/query/plan.dart'
    show PlannedColumn, PlannedJoin, QueryPlan, RelationLoadPlan;
export 'src/query/mutation.dart' show Assignment, Mutation, Returning;
export 'src/query/relation.dart' show ToOneStrategy, Relation;
export 'src/query/batch.dart' show BatchInsert, BatchReturning;
export 'src/query/joins.dart' show TableAlias, WindowFrame, rowNumber, rank;
export 'src/query/cte.dart' show DerivedQuery, CteFields, QueryCtes;
export 'src/query/projection.dart'
    show
        Slot,
        SlotBinding,
        ProjectionType,
        ProjectionFields,
        ProjectionOutput,
        Projection,
        SelectedQuery,
        ProjectedSql;
export 'src/query/cursor.dart' show NullOrder, CursorTerm, KeysetQuery;
export 'src/query/union.dart'
    show SqlRow2, SqlRow3, SqlRow4, SqlRow5, SqlRow6, SetQueries, UnionFields;
export 'src/query/stream.dart' show QueryStreaming;

export 'src/query/raw_sql.dart'
    show Sql, SqlValue, SqlQuery, ColumnSql, FieldSql;
export 'src/query/result.dart'
    show ResultShape, ResultColumn, Result2, Result3, Result4, Result5, Result6;
export 'src/query/raw_execution.dart' show SqlExecution;

export 'src/runtime/database.dart' show SqlDatabase, SqlDatabaseStreaming;
export 'src/runtime/events.dart'
    show QueryOperation, QueryEvent, AcquisitionEvent;
export 'src/runtime/options.dart'
    show
        TransactionOptions,
        Isolation,
        PostgresTransaction,
        SqliteTransactionMode,
        SqliteTransaction,
        MysqlTransaction,
        MariadbTransaction;
export 'src/runtime/transaction.dart' show TransactionRetry;
export 'src/query/sql_check.dart' show SqlCheck, checkSqlQuery;
