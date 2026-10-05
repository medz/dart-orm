import 'package:meta/meta.dart';

import '../driver/driver.dart';
import '../values/codec.dart';
import 'context.dart';
import 'mutation.dart';
import 'nodes.dart';
import 'preparation.dart';
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
  final Mutation<F> _template;

  /// @nodoc
  @internal
  BatchInsert.internal(
    this.database,
    this.queryFields,
    this.queryState,
    List<List<Assignment>> rows, {
    F Function(TableRef)? fieldsFactory,
    Mutation<F>? template,
  }) : insertRows = List.unmodifiable(rows),
       _template =
           template ??
           Mutation.internal(
             database,
             queryFields,
             queryState,
             MutationKind.insert,
             const [],
             fieldsFactory: fieldsFactory,
           );

  /// Applies one SQLite/PostgreSQL conflict-update rule to every statement chunk.
  ///
  /// [target] must name a declared primary or unique key. [set] receives existing
  /// and proposed incoming fields and must supply at least one assignment. These
  /// callbacks run once here; they do not resample the batch's frozen defaults.
  /// Only explicit assignments update existing rows. Assigning an incoming field
  /// copies its proposed insert value, including defaults for omitted inputs;
  /// this method does not infer per-row patch or omission semantics.
  ///
  /// Chunks remain separate native statements inside one atomic transaction.
  /// Repeated keys follow each statement's database rules: PostgreSQL rejects
  /// updating one row twice in a single statement, but separate chunks may update
  /// it again. Parameter limits and input shapes can therefore change duplicate
  /// outcomes. No cross-chunk deduplication or database-equality check is made.
  /// For chunk-independent results, supply inputs that do not conflict with one
  /// another under the database's unique-key rules.
  ///
  /// MySQL/MariaDB cannot select this conflict target and are rejected before I/O.
  /// SQLite also rejects an upsert row with no non-default insert columns,
  /// because its `DEFAULT VALUES` form cannot carry an ON CONFLICT clause.
  BatchInsert<F> onConflictUpdate({
    required List<ReadField<Object?>> Function(F) target,
    required List<Assignment> Function(F existing, F incoming) set,
  }) => BatchInsert.internal(
    database,
    queryFields,
    queryState,
    insertRows,
    template: _template.onConflictUpdate(target: target, set: set),
  );

  /// @nodoc
  @internal
  List<SqlCommand> compileQuery([SelectionPlan? selection]) {
    preflightAssignments(queryState.source, insertRows);
    final commands = <SqlCommand>[];
    var chunk = <List<Assignment>>[];
    List<String>? shape;
    var parameters = 0;
    // Compile the row-free template to validate the complete clause/selection
    // and reserve their parameters before any chunk is built or submitted.
    final extra = _template.compileQuery(selection);
    final limit = database.capabilities.maxParameters - extra.parameters.length;
    void flush() {
      if (chunk.isEmpty) return;
      commands.add(_template.withInsertRows(chunk).compileQuery(selection));
      chunk = [];
      parameters = 0;
    }

    for (final row in insertRows) {
      final actual = row.where((a) => a.assignedValue != null).toList();
      if (actual.isEmpty &&
          _template.hasConflict &&
          database.dialect == SqlDialect.sqlite) {
        throw const OrmException(
          'CAPABILITY.CONFLICT_DEFAULT_VALUES',
          'SQLite DEFAULT VALUES cannot carry ON CONFLICT.',
        );
      }
      final columns = [for (final a in actual) a.field.definition.name];
      final writer = SqlWriter(
        database.dialect,
        // VALUES has no current target row, just like Mutation's real writer.
        // A scalar subquery may introduce the same occurrence as its source.
        {},
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
  Future<T> _run<T>({
    required T Function(QueryContext, SqlResult) complete,
    SelectionPlan? selection,
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    options.check();
    final commands = compileQuery(selection);
    if (commands.isEmpty) return complete(database, const SqlResult([]));
    Future<T> execute(QueryContext db) async {
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
        // A failed statement/cancellation cannot commit earlier chunks.
        db.markFailed();
        rethrow;
      }
      // An owned transaction commits only after typed results are accepted.
      // In an explicit transaction the caller chooses whether to catch this.
      return complete(db, SqlResult(rows, affectedRows: count));
    }

    return database.inTransaction
        ? execute(database)
        : database.atomic(execute, acquire: options.acquisition);
  }

  /// Executes all chunks atomically and returns their total affected-row count.
  ///
  /// Counts sum the driver's native results, including conflict updates; they
  /// are not normalized across engines or a count of distinct input keys.
  /// An empty batch returns zero without acquiring a connection.
  Future<int> execute({ExecutionOptions options = const ExecutionOptions()}) =>
      _run(options: options, complete: (_, result) => result.affectedRows);

  /// Prepares typed scalar projections from every inserted chunk's RETURNING.
  ///
  /// The connected engine must support RETURNING. Scalar subqueries and
  /// relationship `count`/`any` expressions stay within each chunk's statement.
  /// Related row selections and top-level aggregate or window selections are
  /// rejected before executing a chunk.
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
  /// Decoding completes before the batch's owned transaction commits. Inside
  /// an existing transaction, let decoding errors escape if they must roll back.
  Future<List<R>> get({
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final plan = SelectionPlan();
    final decode = querySelection.bindSelection(plan);
    return _batch._run(
      selection: plan,
      options: options,
      complete: (db, result) => db.observeDecode(
        null,
        result.rows.length,
        () => [for (final row in result.rows) decode(row)],
      ),
    );
  }
}
