part of '../orm.dart';

/// Typed ORM access over a raw SQL runtime. The runtime owns connections,
/// transactions and cursor lifetimes; this layer adds tables and invalidation.
class Database<B extends Backend> extends QueryContext {
  final SqlDatabase<B> sql;
  final void Function(DecodeEvent)? onDecode;
  late final _ChangeHub _changes = _changeHubs[driver] ??= _ChangeHub();
  final Map<String, bool> _pendingChanges = {};
  bool _invalidationQueued = false;

  Database(
    Driver<B> driver, {
    void Function(QueryEvent)? onQuery,
    void Function(AcquisitionEvent)? onAcquire,
    void Function(DecodeEvent)? onDecode,
  }) : this.fromSql(
         SqlDatabase(driver, onQuery: onQuery, onAcquire: onAcquire),
         onDecode: onDecode,
       );

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

  Driver<B> get driver => sql.driver;
  @override
  Capabilities get capabilities => sql.capabilities;
  @override
  SqlDialect get dialect => sql.dialect;
  @override
  bool get inTransaction => sql.inTransaction;
  @override
  bool get inSession => sql.inSession;
  void Function(QueryEvent)? get onQuery => sql.onQuery;
  void Function(AcquisitionEvent)? get onAcquire => sql.onAcquire;

  @override
  TableSet<R, F> table<R, F extends Fields>(Table<R, F> definition) =>
      TableSet(this, definition);

  /// Register declared FK effects for query invalidation.
  @override
  void registerSchema(Iterable<TableSchema> tables) =>
      _changes.register(tables);

  /// Explicit notification for raw SQL, triggers or externally committed work.
  /// A transaction defers notification until commit; rollback discards it.
  void invalidate(Iterable<TableSchema> tables) {
    checkActive();
    _recordChanges(tables, cascade: true);
  }

  void _recordChanges(Iterable<TableSchema> tables, {required bool cascade}) {
    final changes = <String, bool>{};
    for (final table in tables) {
      _changes.registerTable(table);
      changes[table.name] = cascade;
    }
    if (!inTransaction) {
      _changes.publish(changes);
      return;
    }
    _mergeChanges(_pendingChanges, changes);
    if (!_invalidationQueued) {
      _invalidationQueued = true;
      sql.deferInvalidation(() => _changes.publish(_pendingChanges));
    }
  }

  void checkActive() => sql.checkActive();
  @override
  void markFailed() => sql.markFailed();

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

  @override
  Future<SqlResult> executeOn(
    SqlConnection connection,
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) => sql.executeOn(connection, command, options: options);

  @override
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
    Iterable<TableSchema> changedTables = const [],
  }) => executeCommand(command, options: options, changedTables: changedTables);

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

  Future<R> session<R>(
    Future<R> Function(Database<B> session) action, {
    AcquisitionOptions acquire = const AcquisitionOptions(),
  }) => sql.session(
    (session) => action(Database.fromSql(session, onDecode: onDecode)),
    acquire: acquire,
  );

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

  Future<R> savepoint<R>(Future<R> Function(Database<B> tx) action) =>
      sql.savepoint((tx) => action(Database.fromSql(tx, onDecode: onDecode)));

  @override
  Stream<R> streamRows<R>(
    SqlCommand command, {
    required int batchSize,
    required ExecutionOptions options,
    required Future<List<R>> Function(
      SqlConnection,
      List<List<Object?>>,
      ExecutionOptions,
    )
    decode,
  }) => sql.streamRows(
    command,
    batchSize: batchSize,
    options: options,
    decode: decode,
  );

  Future<void> discard() => sql.discard();
  Future<void> close() => sql.close();

  @override
  Future<R> atomic<R>(
    Future<R> Function(QueryContext) action, {
    AcquisitionOptions acquire = const AcquisitionOptions(),
  }) => transaction(action, acquire: acquire);

  @override
  T observeDecode<T>(String? sql, int inputRows, T Function() action) =>
      _observeDecode(sql, inputRows, action);
}
