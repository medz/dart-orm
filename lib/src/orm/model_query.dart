import '../driver/driver.dart';
import '../query/context.dart';
import '../query/query.dart';
import '../query/table.dart';
import '../query/expression.dart';
import '../query/selection.dart';
import '../query/joins.dart';
import '../query/cursor.dart';
import '../query/mutation.dart';
import '../query/batch.dart';
import '../query/preparation.dart' show prepareInsert;

/// An inert write bound to its original query context.
/// Each terminal prepares again. [prepare] freezes client defaults and returns
/// a [Mutation] for SQL inspection and conflict handling. Descriptions borrow
/// their context; they neither acquire nor own a connection until execution.
/// A description captured from a session cannot execute after that session ends.
///
/// Preparation can run expression callbacks, codecs and client factories. Their
/// Dart side effects are not rolled back. Catching a typed result decoding error
/// inside an explicit transaction leaves it usable; let the error escape when
/// the transaction must roll back.
class Write<R, F extends Fields> {
  final QueryContext _database;
  final F _fields;
  final QueryState _state;
  final Mutation<F> Function(SelectionPlan?) _build;
  final Selection<R> Function(F) _row;
  Write._(this._database, this._fields, this._state, this._build, this._row);

  /// Validates and captures assignments and client defaults without database I/O.
  ///
  /// Replaying the returned mutation reuses these values. Calling this method
  /// again prepares fresh values. Unsupported writes fail before acquisition.
  /// Encoded byte storage is captured as a read-only snapshot; other mutable
  /// custom codec storage remains caller-owned and must stay stable for replays.
  /// The session and known query shape are checked before callbacks. Assignment
  /// expressions produced by callbacks can only be validated after they run.
  Mutation<F> prepare() {
    _database.checkActive();
    preflightMutationQuery(_state);
    final mutation = _build(null);
    mutation.compile();
    return mutation;
  }

  /// Prepares and executes once, returning the affected-row count.
  Future<int> execute({
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    _database.checkActive();
    options.check();
    return prepare().execute(options: options);
  }

  /// Describes native RETURNING with the complete model selection.
  WriteRows<R, F> returning() =>
      WriteRows._(_database, _fields, _state, _build, _row);
}

/// Native RETURNING, with the selection checked before client default factories.
///
/// Each terminal executes the write again. SQL has executed before decoding and
/// cardinality checks; an autocommitted write cannot be undone by a Dart result
/// error. Use an explicit transaction and let errors escape to request rollback.
final class WriteRows<R, F extends Fields> {
  final QueryContext _database;
  final F _fields;
  final QueryState _state;
  final Mutation<F> Function(SelectionPlan) _build;
  final Selection<R> Function(F) _selection;
  WriteRows._(
    this._database,
    this._fields,
    this._state,
    this._build,
    this._selection,
  );

  /// Replaces the returned model with a scalar or composed flat selection.
  WriteRows<S, F> select<S>(Selection<S> Function(F) selection) =>
      WriteRows._(_database, _fields, _state, _build, selection);

  /// Freezes this write and native selection without acquiring a connection.
  Returning<R> prepare() {
    _database.checkActive();
    preflightMutationQuery(_state);
    final selection = _selection(_fields);
    final plan = SelectionPlan();
    selection.bindSelection(plan);
    final mutation = _build(plan);
    mutation.compileQuery(plan);
    return Returning.internal(mutation, selection);
  }

  /// Executes once and decodes every returned row.
  Future<List<R>> get({
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    _database.checkActive();
    options.check();
    return prepare().get(options: options);
  }

  /// Executes the entire write, then requires exactly one returned row.
  Future<R> single({
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    _database.checkActive();
    options.check();
    return prepare().single(options: options);
  }

  /// Executes the entire write and requires at least one returned row.
  Future<R> first({ExecutionOptions options = const ExecutionOptions()}) async {
    _database.checkActive();
    options.check();
    return prepare().first(options: options);
  }

  /// Executes the entire write and returns its first row, or null.
  Future<R?> firstOrNull({
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    _database.checkActive();
    options.check();
    return prepare().firstOrNull(options: options);
  }

  /// Executes the entire write and rejects more than one returned row.
  Future<R?> singleOrNull({
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    _database.checkActive();
    options.check();
    return prepare().singleOrNull(options: options);
  }
}

/// Logical insert result, including key readback when RETURNING is unavailable.
final class InsertWrite<R, F extends Fields> extends Write<R, F> {
  final TableSet<R, F> _table;
  final Mutation<F> Function(SelectionPlan?) _buildRow;
  InsertWrite._(
    super.database,
    super.fields,
    super.state,
    super.build,
    super.row,
    this._table,
    this._buildRow,
  ) : super._();

  /// Inserts and returns the complete model, with key readback if necessary.
  ///
  /// When native RETURNING is unavailable, the insert and key lookup share one
  /// transaction. Keys must be literal values or at most one generated identity.
  /// Preparation validates this requirement before sampling client defaults.
  Future<R> row({ExecutionOptions options = const ExecutionOptions()}) async {
    _database.checkActive();
    options.check();
    preflightMutationQuery(_state);
    final plan = _database.capabilities.returning ? SelectionPlan() : null;
    if (plan != null) _row(_fields).bindSelection(plan);
    final prepared = _buildRow(plan);
    return _table.createPreparedRow(prepared, options: options);
  }
}

/// A batch description whose input iterable was captured during construction.
///
/// Assignments and defaults prepare once per terminal call. Prepared chunks
/// share an owned transaction unless execution already borrows an explicit one.
final class BatchWrite<F extends Fields> {
  final QueryContext _database;
  final BatchInsert<F> Function() _build;
  BatchWrite._(this._database, this._build);

  /// Freezes every row and returns the core batch for SQL or RETURNING access.
  /// Byte storage is captured as for [Write.prepare]; other mutable custom
  /// codec storage remains caller-owned across replays.
  BatchInsert<F> prepare() {
    _database.checkActive();
    return _build();
  }

  /// Prepares and executes once, returning the affected-row count.
  Future<int> execute({
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    _database.checkActive();
    options.check();
    return prepare().execute(options: options);
  }
}

/// A complete entity query retaining the generated patch type.
/// Read execution, relations, streaming and watches are inherited unchanged.
/// Selecting, mapping, grouping and DISTINCT deliberately return read-only Query.
/// Filters, ordering, limits, aliases and rebinding retain this type. Mutations
/// still reject ordering, limits and joins at preparation; this type never grants
/// permission to execute an unsupported SQL write. A bound description expires
/// with its original session, exactly as the underlying Query does.
class ModelQuery<R, F extends Fields, P> extends Query<R, F> {
  final List<Assignment> Function(F, P) _patch;

  /// Binds a generated patch converter to a complete model query.
  ModelQuery.internal(Query<R, F> source, this._patch)
    : super.internal(
        source.database,
        source.queryFields,
        source.queryState,
        source.querySelection,
      );
  @override
  ModelQuery<R, F, P> copyQuery(QueryState state) =>
      ModelQuery.internal(super.copyQuery(state), _patch);
  @override
  ModelQuery<R, F, P> where(Expr<bool?> Function(F) condition) =>
      super.where(condition) as ModelQuery<R, F, P>;
  @override
  ModelQuery<R, F, P> orderBy(List<OrderTerm> Function(F) order) =>
      super.orderBy(order) as ModelQuery<R, F, P>;
  @override
  ModelQuery<R, F, P> take(int count) =>
      super.take(count) as ModelQuery<R, F, P>;
  @override
  ModelQuery<R, F, P> skip(int count) =>
      super.skip(count) as ModelQuery<R, F, P>;
  @override
  ModelQuery<R, F, P> join<S, G extends Fields>(
    TableAlias<S, G> alias, {
    required Expr<bool?> Function(F, G) on,
  }) => super.join(alias, on: on) as ModelQuery<R, F, P>;
  @override
  ModelQuery<R, F, P> leftJoin<S, G extends Fields>(
    TableAlias<S, G> alias, {
    required Expr<bool?> Function(F, G) on,
  }) => super.leftJoin(alias, on: on) as ModelQuery<R, F, P>;
  @override
  ModelQuery<R, F, P> bind(QueryContext context) =>
      ModelQuery.internal(super.bind(context), _patch);

  /// Applies a keyset cursor while preserving this model's patch type.
  ModelQuery<R, F, P> seekAfter(List<CursorTerm> Function(F) cursor) =>
      KeysetQuery(this).seekAfter(cursor) as ModelQuery<R, F, P>;

  /// Applies a validated cursor token while preserving the model's patch type.
  ModelQuery<R, F, P> seekToken(
    String token, {
    required List<OrderTerm> Function(F) orderBy,
  }) =>
      KeysetQuery(this).seekToken(token, orderBy: orderBy)
          as ModelQuery<R, F, P>;

  /// Describes advanced writes without preparing values or executing SQL.
  ///
  /// Use this boundary for RETURNING, SQL inspection, or explicit preparation.
  /// Plans borrow this query's context and cannot extend its session lifetime.
  ModelWritePlan<R, F, P> get plan => ModelWritePlan._(this);

  /// Executes one update using this model's immutable patch input.
  ///
  /// Returns the driver's affected-row count. Session, options and known query
  /// shape are checked before input callbacks. Invalid expressions built by a
  /// callback can only be rejected afterwards. Empty patches fail without SQL.
  /// For RETURNING or frozen values, describe the update through [plan].
  Future<int> update(
    P input, {
    ExecutionOptions options = const ExecutionOptions(),
  }) => plan.update(input).execute(options: options);

  /// Executes deletion of the matched rows and returns the affected-row count.
  /// For RETURNING or SQL inspection, describe the delete through [plan].
  Future<int> delete({ExecutionOptions options = const ExecutionOptions()}) =>
      plan.delete().execute(options: options);
}

/// An unfiltered model root. Insert is intentionally unavailable after filters.
class ModelTable<R, F extends Fields, I, P> extends ModelQuery<R, F, P> {
  final TableSet<R, F> _table;
  final List<Assignment> Function(F, I) _insert;

  /// Binds a generated model definition and its typed input converters.
  ModelTable(
    QueryContext database,
    Table<R, F> definition,
    List<Assignment> Function(F, I) insert,
    List<Assignment> Function(F, P) patch,
  ) : this._(TableSet(database, definition), insert, patch);
  ModelTable._(this._table, this._insert, List<Assignment> Function(F, P) patch)
    : super.internal(_table, patch);

  /// Describes advanced writes, including inserts into this unfiltered table.
  @override
  ModelTableWritePlan<R, F, I, P> get plan => ModelTableWritePlan._(this);

  /// Executes one insert and returns the affected-row count.
  ///
  /// Use the generated named `create` to return a model, or [plan] for an input
  /// with RETURNING, key readback, conflict handling or explicit preparation.
  Future<int> insert(
    I input, {
    ExecutionOptions options = const ExecutionOptions(),
  }) => plan.insert(input).execute(options: options);

  /// Captures inputs and executes one atomic, parameter-aware batch.
  ///
  /// Checks the session and options before traversing [inputs]. Client defaults
  /// are sampled after preparing and validating all rows. An existing explicit
  /// transaction is borrowed; otherwise the batch owns one transaction.
  Future<int> insertMany(
    Iterable<I> inputs, {
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    database.checkActive();
    options.check();
    return plan.insertMany(inputs).execute(options: options);
  }
}

/// Advanced descriptions for a complete model query.
///
/// Creating a plan or update/delete description does not evaluate input
/// expressions, sample client defaults or acquire a connection. Terminals prepare
/// fresh values; explicit [Write.prepare] freezes them. The original query scope
/// is borrowed, so a plan captured inside a session expires with that session.
class ModelWritePlan<R, F extends Fields, P> {
  final ModelQuery<R, F, P> _query;
  ModelWritePlan._(this._query);

  /// Describes an update using this model's immutable patch input.
  Write<R, F> update(P input) => Write._(
    _query.database,
    _query.queryFields,
    _query.queryState,
    (_) => Mutation.internal(
      _query.database,
      _query.queryFields,
      _query.queryState,
      MutationKind.update,
      _query._patch(_query.queryFields, input),
    ),
    (_) => _query.querySelection,
  );

  /// Describes deletion of the rows matched by the query.
  Write<R, F> delete() => Write._(
    _query.database,
    _query.queryFields,
    _query.queryState,
    (_) => Mutation.internal(
      _query.database,
      _query.queryFields,
      _query.queryState,
      MutationKind.delete,
      const [],
    ),
    (_) => _query.querySelection,
  );
}

/// Advanced insert descriptions available only on an unfiltered model table.
///
/// Shares the preparation core and borrowed lifetime of [ModelWritePlan]. No
/// insert runs until a terminal is called on its description.
final class ModelTableWritePlan<R, F extends Fields, I, P>
    extends ModelWritePlan<R, F, P> {
  final ModelTable<R, F, I, P> _model;
  ModelTableWritePlan._(this._model) : super._(_model);

  /// Describes an insert; omitted client defaults wait until preparation.
  InsertWrite<R, F> insert(I input) {
    final table = _model._table;
    return InsertWrite._(
      table.database,
      table.queryFields,
      table.queryState,
      (selection) => prepareInsert(
        table,
        _model._insert(table.queryFields, input),
        selection,
      ),
      table.definition.selectRow,
      table,
      (selection) => prepareInsert(
        table,
        _model._insert(table.queryFields, input),
        selection,
        needsRow: true,
      ),
    );
  }

  /// Captures inputs now and describes one atomic, parameter-aware batch.
  BatchWrite<F> insertMany(Iterable<I> inputs) {
    final frozen = List<I>.unmodifiable(inputs);
    return BatchWrite._(
      _model.database,
      () => _model._table.insertMany(frozen, _model._insert),
    );
  }
}
