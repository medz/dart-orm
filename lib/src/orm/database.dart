import 'package:meta/meta.dart' show internal;

import '../../runtime.dart';
import '../../sql.dart';
import 'changes.dart';
import 'observation.dart';
import 'observation.dart' as observation;

/// Typed queries and change notifications over an owned SQL runtime.
///
/// [sql] manages connections, transactions, and cursor lifetimes. Generated table
/// access and [table] add typed queries; [invalidate] reports external changes to
/// watches. Session and transaction views share ownership with their root runtime
/// and expire when their callback ends.
///
/// {@category Databases}
class Database<B extends Backend> extends QueryContext {
  /// Raw SQL runtime shared by this database and its borrowed session views.
  final SqlDatabase<B> sql;

  /// Optional decode observer; observer exceptions cannot change query outcomes.
  final void Function(DecodeEvent)? onDecode;
  late final ChangeHub _changes = changesFor(driver);
  final Map<String, bool> _pendingChanges = {};
  bool _invalidationQueued = false;

  /// Takes ownership of [driver] through a new SQL runtime.
  Database(
    Driver<B> driver, {
    void Function(QueryEvent)? onQuery,
    void Function(AcquisitionEvent)? onAcquire,
    void Function(DecodeEvent)? onDecode,
  }) : this.fromSql(
         SqlDatabase(driver, onQuery: onQuery, onAcquire: onAcquire),
         onDecode: onDecode,
       );

  /// Adds typed queries and watches to an existing SQL runtime.
  ///
  /// This shares [sql]'s lifecycle: closing a root wrapper closes that runtime;
  /// wrapping a borrowed session does not grant ownership of its driver.
  Database.fromSql(this.sql, {this.onDecode}) {
    if (!sql.inSession) {
      final removeChanges = sql.addChangeListener(
        (tables) => _changes.publish({for (final table in tables) table: true}),
      );
      sql.addCloseListener(() async {
        removeChanges();
        await _changes.stop();
      });
    }
  }

  /// Driver owned by the root SQL runtime.
  Driver<B> get driver => sql.driver;

  /// Operations supported by the concrete engine, adapter, and platform.
  @override
  Capabilities get capabilities => sql.capabilities;

  /// Connected database engine used for SQL rendering and validation.
  @override
  SqlDialect get dialect => sql.dialect;

  /// Whether this view belongs to a transaction or savepoint callback.
  @override
  bool get inTransaction => sql.inTransaction;

  /// Whether this view already holds a connection lease.
  @override
  bool get inSession => sql.inSession;

  /// Statement and cursor observer inherited from the SQL runtime.
  void Function(QueryEvent)? get onQuery => sql.onQuery;

  /// Connection acquisition observer inherited from the SQL runtime.
  void Function(AcquisitionEvent)? get onAcquire => sql.onAcquire;

  /// Binds a manually defined typed table to this database or session.
  @override
  TableSet<R, F> table<R, F extends Fields>(Table<R, F> definition) =>
      TableSet(this, definition);

  /// Registers physical schema for foreign-key-aware query invalidation.
  ///
  /// Generated clients call this when binding tables. Registration executes no
  /// DDL and performs no database introspection.
  @override
  void registerSchema(Iterable<TableSchema> tables) =>
      _changes.register(tables);

  /// Explicit notification for raw SQL, triggers or externally committed work.
  /// A transaction defers notification until commit; confirmed rollback discards
  /// it. An uncertain commit invalidates conservatively.
  void invalidate(Iterable<TableSchema> tables) {
    checkActive();
    _recordChanges(tables, cascade: true);
  }

  void _recordChanges(Iterable<TableSchema> tables, {required bool cascade}) {
    final changes = <String, bool>{};
    for (final table in tables) {
      _changes.registerTable(table);
      changes[table.identity] = cascade;
    }
    if (!inTransaction) {
      _changes.publish(changes);
      return;
    }
    mergeChanges(_pendingChanges, changes);
    if (!_invalidationQueued) {
      _invalidationQueued = true;
      sql.deferInvalidation(() => _changes.publish(_pendingChanges));
    }
  }

  /// @nodoc
  @internal
  void checkActive() => sql.checkActive();

  /// @nodoc
  @internal
  @override
  void markFailed() => sql.markFailed();

  /// Runs an advanced raw operation using an acquired or existing connection.
  ///
  /// The connection remains owned by [sql] and must not escape [action]. This
  /// does not start a transaction or infer which physical tables were changed.
  @override
  Future<R> run<R>(
    Future<R> Function(SqlConnection) action, {
    AcquisitionOptions acquire = const AcquisitionOptions(),
    OrmException? acquisitionTimeoutError,
  }) => sql.run(
    action,
    acquire: acquire,
    acquisitionTimeoutError: acquisitionTimeoutError,
  );

  /// @nodoc
  @internal
  @override
  Future<SqlResult> executeOn(
    SqlConnection connection,
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) => sql.executeOn(connection, command, options: options);

  /// Executes bound SQL and returns raw rows without typed model decoding.
  ///
  /// Declare [changedTables] for writes that should invalidate watched queries.
  /// Notifications follow transaction commit and rollback boundaries.
  @override
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
    Iterable<TableSchema> changedTables = const [],
  }) => executeCommand(command, options: options, changedTables: changedTables);

  /// @nodoc
  @internal
  @override
  Future<SqlResult> executeCommand(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
    Iterable<TableSchema> changedTables = const [],
    bool affectedOnly = false,
    bool cascade = true,
  }) {
    options.check();
    if (options.cancellation != null && !capabilities.cancellation) {
      throw const OrmException(
        'CAPABILITY.CANCEL',
        'This driver cannot cancel a running statement.',
      );
    }
    if (options.timeout != null && !capabilities.statementTimeout) {
      throw const OrmException(
        'CAPABILITY.CANCEL',
        'This driver does not support statement timeouts.',
      );
    }
    final tables = List<TableSchema>.unmodifiable(changedTables);
    if (tables.isEmpty) return sql.execute(command, options: options);
    return run((connection) async {
      final result = await executeOn(connection, command, options: options);
      if (!affectedOnly || result.affectedRows > 0) {
        _recordChanges(tables, cascade: cascade);
      }
      return result;
    }, acquire: options.acquisition);
  }

  /// Holds one connection for [action] without automatically starting a transaction.
  ///
  /// The supplied view expires when the callback finishes. Await all its work
  /// and finish streams before returning; nested leased sessions are rejected.
  Future<R> session<R>(
    Future<R> Function(Database<B> session) action, {
    AcquisitionOptions acquire = const AcquisitionOptions(),
  }) => sql.session(
    (session) => action(Database.fromSql(session, onDecode: onDecode)),
    acquire: acquire,
  );

  /// Runs typed queries on one transaction and returns after confirmed commit.
  ///
  /// Use the supplied transaction view for every operation. A failed statement
  /// prevents commit even when its error is caught; use [savepoint] for a
  /// recoverable sub-operation. Confirmed rollback drops pending notifications;
  /// an uncertain commit invalidates watches conservatively.
  ///
  /// [retry] explicitly permits replay after confirmed rollback, so the callback
  /// must be safe to repeat. An uncertain commit is never automatically replayed.
  /// [timeout] applies after acquisition; retry budgets also include acquisition.
  Future<R> transaction<R>(
    Future<R> Function(Database<B> tx) action, {
    TransactionOptions<B>? options,
    AcquisitionOptions acquire = const AcquisitionOptions(),
    Duration? timeout,
    CancellationToken? cancellation,
    TransactionRetry? retry,
  }) => sql.transaction(
    (tx) => action(Database.fromSql(tx, onDecode: onDecode)),
    options: options,
    acquire: acquire,
    timeout: timeout,
    cancellation: cancellation,
    retry: retry,
  );

  /// Runs recoverable nested work inside an existing transaction.
  ///
  /// Use the child view exclusively until it finishes. On failure, the runtime
  /// rolls back to its savepoint; failed cleanup invalidates the connection.
  Future<R> savepoint<R>(Future<R> Function(Database<B> tx) action) =>
      sql.savepoint((tx) => action(Database.fromSql(tx, onDecode: onDecode)));

  /// @nodoc
  @internal
  @override
  Stream<R> streamRows<R>(
    SqlCommand command, {
    required int batchSize,
    required ExecutionOptions options,
    required Future<List<R>> Function(
      SqlConnection,
      SqlResult,
      ExecutionOptions,
    )
    decode,
  }) => sql.streamRows(
    command,
    batchSize: batchSize,
    options: options,
    decode: decode,
  );

  /// Permanently invalidates this view's leased connection.
  ///
  /// Requires a session or transaction view. Discarding is for unrecoverable
  /// state; it does not establish the outcome of a write already submitted.
  Future<void> discard() => sql.discard();

  /// Stops watches and streams, drains pending work, and closes the root runtime.
  ///
  /// Borrowed session and transaction views cannot close their owner's driver.
  Future<void> close() => sql.close();

  /// @nodoc
  @internal
  @override
  Future<R> atomic<R>(
    Future<R> Function(QueryContext) action, {
    AcquisitionOptions acquire = const AcquisitionOptions(),
  }) => transaction(action, acquire: acquire);

  /// @nodoc
  @internal
  @override
  T observeDecode<T>(String? sql, int inputRows, T Function() action) =>
      observation.observeDecode(onDecode, sql, inputRows, action);
}
