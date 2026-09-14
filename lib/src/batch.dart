part of '../orm.dart';

/// Inserts consecutive rows of the same shape together, splitting at the
/// driver's parameter limit. All chunks share one transaction by default.
final class BatchInsert<F extends Fields> {
  final Database<Backend> database;
  final F _fields;
  final _QueryState _state;
  final List<List<Assignment>> _rows;
  BatchInsert._(
    this.database,
    this._fields,
    this._state,
    List<List<Assignment>> rows,
  ) : _rows = List.unmodifiable(rows);

  List<SqlCommand> _compile([_SelectionPlan? selection]) {
    final commands = <SqlCommand>[];
    var chunk = <List<Assignment>>[];
    List<String>? shape;
    var parameters = 0;
    final extra = _Writer(database.dialect, {
      _state.source: 't0',
    }, exactDecimal: database.capabilities.exactDecimal);
    if (selection != null) {
      for (final column in selection.columns) {
        column._node.write(extra);
      }
    }
    final limit = database.capabilities.maxParameters - extra.parameters.length;
    void flush() {
      if (chunk.isEmpty) return;
      commands.add(
        Mutation._(
          database,
          _fields,
          _state,
          _MutationKind.insert,
          chunk.first,
          rows: chunk,
        )._compile(selection),
      );
      chunk = [];
      parameters = 0;
    }

    for (final row in _rows) {
      final actual = row.where((a) => a._value != null).toList();
      final columns = [for (final a in actual) a.field.definition.name];
      final writer = _Writer(database.dialect, {
        _state.source: 't0',
      }, exactDecimal: database.capabilities.exactDecimal);
      for (final a in actual) {
        a._value!.write(writer);
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

  List<SqlCommand> compile() => _compile();
  Future<SqlResult> _run({
    _SelectionPlan? selection,
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    options.check();
    final commands = _compile(selection);
    if (commands.isEmpty) return const SqlResult([]);
    Future<SqlResult> execute(Database<Backend> db) async {
      var count = 0;
      final rows = <List<Object?>>[];
      try {
        for (final command in commands) {
          final result = await db._executeCommand(
            command,
            options: options,
            changedTables: [_state.source.schema],
            affectedOnly: true,
            cascade: false,
          );
          count += result.affectedRows;
          rows.addAll(result.rows);
        }
      } catch (_) {
        // Cancellation can happen between statements, after earlier chunks
        // succeeded. Catching it must not allow a partial batch to commit.
        if (db.inTransaction) db._statementFailed = true;
        rethrow;
      }
      return SqlResult(rows, affectedRows: count);
    }

    return database.inTransaction
        ? execute(database)
        : database.transaction(execute, acquire: options._acquisition);
  }

  Future<int> execute({
    ExecutionOptions options = const ExecutionOptions(),
  }) async => (await _run(options: options)).affectedRows;
  BatchReturning<R> returning<R>(Selection<R> Function(F) selection) =>
      BatchReturning._(this, selection(_fields));
}

final class BatchReturning<R> {
  final BatchInsert<Fields> _batch;
  final Selection<R> _selection;
  BatchReturning._(this._batch, this._selection);
  Future<List<R>> get({
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final plan = _SelectionPlan();
    final decode = _selection._bind(plan);
    final result = await _batch._run(selection: plan, options: options);
    return [for (final row in result.rows) decode(row)];
  }
}
