import 'package:meta/meta.dart';

import '../../driver.dart';
import 'context.dart';
import 'mutation.dart';
import 'nodes.dart';
import 'query.dart';
import 'selection.dart';
import 'table.dart';

/// Inserts consecutive rows of the same shape together, splitting at the
/// driver's parameter limit. All chunks share one transaction by default.
///
/// Preparing or compiling a batch performs no I/O. Inside an existing
/// transaction, every chunk uses that transaction. A failure between chunks
/// marks it failed, preventing a caught error from committing a partial batch.
final class BatchInsert<F extends Fields> {
  /// Query context that owns the batch's execution and transaction scope.
  final QueryContext database;

  /// @nodoc
  @internal
  final F queryFields;

  /// @nodoc
  @internal
  final QueryState queryState;

  /// @nodoc
  @internal
  final List<List<Assignment>> insertRows;

  /// @nodoc
  @internal
  BatchInsert.internal(
    this.database,
    this.queryFields,
    this.queryState,
    List<List<Assignment>> rows,
  ) : insertRows = List.unmodifiable(rows);

  /// @nodoc
  @internal
  List<SqlCommand> compileQuery([SelectionPlan? selection]) {
    final commands = <SqlCommand>[];
    var chunk = <List<Assignment>>[];
    List<String>? shape;
    var parameters = 0;
    final extra = SqlWriter(
      database.dialect,
      {queryState.source: 't0'},
      database: database,
      exactDecimal: database.capabilities.exactDecimal,
      temporal: database.capabilities.temporal,
    );
    if (selection != null) {
      for (final column in selection.columns) {
        column.expressionNode.write(extra);
      }
    }
    final limit = database.capabilities.maxParameters - extra.parameters.length;
    void flush() {
      if (chunk.isEmpty) return;
      commands.add(
        Mutation.internal(
          database,
          queryFields,
          queryState,
          MutationKind.insert,
          chunk.first,
          insertRows: chunk,
        ).compileQuery(selection),
      );
      chunk = [];
      parameters = 0;
    }

    for (final row in insertRows) {
      final actual = row.where((a) => a.assignedValue != null).toList();
      final columns = [for (final a in actual) a.field.definition.name];
      final writer = SqlWriter(
        database.dialect,
        {queryState.source: 't0'},
        database: database,
        exactDecimal: database.capabilities.exactDecimal,
        temporal: database.capabilities.temporal,
      );
      for (final a in actual) {
        a.assignedValue!.write(writer);
      }
      final count = writer.parameters.length;
      if (count > limit) {
        throw const OrmException(
          'QUERY.PARAMETERS',
          'A single insert row exceeds the parameter limit.',
        );
      }
      final sameShape =
          shape != null &&
          shape.length == columns.length &&
          columns.indexed.every((entry) => shape![entry.$1] == entry.$2);
      if (!sameShape || parameters + count > limit || actual.isEmpty) flush();
      shape = columns;
      chunk.add(row);
      parameters += count;
      if (actual.isEmpty) flush();
    }
    flush();
    return List.unmodifiable(commands);
  }

  /// Returns the SQL chunks without acquiring a connection or inserting rows.
  ///
  /// A row that alone exceeds the parameter limit is rejected. An empty batch
  /// returns an empty command list.
  List<SqlCommand> compile() => compileQuery();
  Future<SqlResult> _run({
    SelectionPlan? selection,
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    options.check();
    final commands = compileQuery(selection);
    if (commands.isEmpty) return const SqlResult([]);
    Future<SqlResult> execute(QueryContext db) async {
      var count = 0;
      final rows = <List<Object?>>[];
      try {
        for (final command in commands) {
          final result = await db.executeCommand(
            command,
            options: options,
            changedTables: [queryState.source.schema],
            affectedOnly: true,
            cascade: false,
          );
          count += result.affectedRows;
          rows.addAll(result.rows);
        }
      } catch (_) {
        // Cancellation can happen between statements, after earlier chunks
        // succeeded. Catching it must not allow a partial batch to commit.
        if (db.inTransaction) db.markFailed();
        rethrow;
      }
      return SqlResult(rows, affectedRows: count);
    }

    return database.inTransaction
        ? execute(database)
        : database.atomic(execute, acquire: options.acquisition);
  }

  /// Executes all chunks atomically and returns their total affected-row count.
  ///
  /// An empty batch returns zero without acquiring a connection.
  Future<int> execute({
    ExecutionOptions options = const ExecutionOptions(),
  }) async => (await _run(options: options)).affectedRows;

  /// Prepares typed scalar projections from every inserted chunk's RETURNING.
  ///
  /// The connected engine must support RETURNING. Relationships and aggregate
  /// or window selections are rejected before executing a chunk.
  BatchReturning<R> returning<R>(Selection<R> Function(F) selection) =>
      BatchReturning.internal(this, selection(queryFields));
}

/// Typed returned rows from a prepared batch insert.
///
/// Each [get] call executes the batch again. Results are collected across chunks;
/// do not assume that database return order establishes an input-row mapping.
final class BatchReturning<R> {
  final BatchInsert<Fields> _batch;

  /// @nodoc
  @internal
  final Selection<R> querySelection;

  /// @nodoc
  @internal
  BatchReturning.internal(this._batch, this.querySelection);

  /// Executes every chunk in one transaction and decodes the returned rows.
  ///
  /// Decoding happens after the batch executes. Use an enclosing transaction
  /// when a decoding exception must roll back the inserted data.
  Future<List<R>> get({
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final plan = SelectionPlan();
    final decode = querySelection.bindSelection(plan);
    final result = await _batch._run(selection: plan, options: options);
    return _batch.database.observeDecode(
      null,
      result.rows.length,
      () => [for (final row in result.rows) decode(row)],
    );
  }
}
