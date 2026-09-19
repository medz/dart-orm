/// Raw SQL sessions, transactions and cursor lifetimes without a query builder.
library;

import 'dart:async';
import 'dart:math' as math;

import 'driver.dart';
export 'driver.dart';

part 'src/runtime/database.dart';
part 'src/runtime/session_connection.dart';
part 'src/runtime/mysql_transaction.dart';
part 'src/runtime/options.dart';
part 'src/runtime/stream.dart';
part 'src/execution.dart';
part 'src/transaction.dart';

enum QueryOperation { execute, cursorOpen, cursorFetch, cursorClose }

final class QueryEvent {
  final QueryOperation operation;
  final String sql;
  final int parameterCount;
  final Duration elapsed;
  final int? rowCount;
  final Object? error;
  const QueryEvent({
    this.operation = QueryOperation.execute,
    required this.sql,
    required this.parameterCount,
    required this.elapsed,
    this.rowCount,
    this.error,
  });
}

/// Time until a driver lease is granted or acquisition fails. Includes native
/// pool wait/connection setup; it does not separate those driver internals.
final class AcquisitionEvent {
  final Duration elapsed;
  final bool reusedConnection;
  final Object? error;
  const AcquisitionEvent({
    required this.elapsed,
    required this.reusedConnection,
    this.error,
  });
}
