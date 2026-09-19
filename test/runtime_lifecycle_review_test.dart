import 'dart:async';

import 'package:orm/orm.dart';
import 'package:test/test.dart';

final _id = Column('id', Codecs.integer);
final _schema = TableSchema('lifecycle_rows', columns: [_id]);
final _table = Table<int, _Fields>(_schema, _Fields.new, (row) => row.id);

final class _Fields(super.table) extends Fields {
  late final id = column(_id);
}

void main() {
  test('borrowed sessions reject root-resource close listeners', () async {
    final raw = SqlDatabase(_Driver());
    void checkBorrowed(SqlDatabase<Sqlite> view) {
      expect(
        () => view.addCloseListener(() async {}),
        throwsA(
          isA<OrmException>().having(
            (error) => error.code,
            'code',
            'SESSION.BORROWED',
          ),
        ),
      );
    }

    try {
      await raw.session((session) async {
        checkBorrowed(session);
        await session.transaction((tx) async {
          checkBorrowed(tx);
          await tx.savepoint((child) async => checkBorrowed(child));
        });
      });
    } finally {
      await raw.close();
    }
  });

  test(
    'a synchronous close-listener failure still closes bound query watches',
    () async {
      final driver = _Driver();
      final raw = SqlDatabase(driver);
      raw.addCloseListener(() => throw StateError('resource cleanup failed'));
      final db = Database.fromSql(raw);
      final first = Completer<void>();
      var done = false;
      final subscription = SqlBuilder(SqlDialect.sqlite)
          .table(_table)
          .bind(db)
          .watch()
          .listen((_) => first.complete(), onDone: () => done = true);
      try {
        await first.future;
        await expectLater(raw.close(), throwsStateError);
        await Future<void>.delayed(Duration.zero);
        expect(driver.closed, isTrue);
        expect(done, isTrue, reason: 'Every cleanup listener must run.');
      } finally {
        await subscription.cancel();
      }
    },
  );

  test(
    'raw and typed invalidations coalesce across wrappers and savepoints',
    () async {
      final driver = _Driver();
      final raw = SqlDatabase(driver);
      final db = Database.fromSql(raw);
      Database.fromSql(raw); // A second ORM view must not duplicate snapshots.
      final initial = Completer<void>();
      final changed = Completer<void>();
      final rows = <List<int>>[];
      final subscription = SqlBuilder(SqlDialect.sqlite)
          .table(_table)
          .bind(db)
          .watch()
          .listen((value) {
            rows.add(value);
            if (rows.length == 1) initial.complete();
            if (rows.length == 2) changed.complete();
          });
      try {
        await initial.future;
        await raw.transaction((tx) async {
          final orm = Database.fromSql(tx);
          await orm.execute(
            SqlCommand('UPDATE lifecycle_rows SET id = 1'),
            changedTables: [_schema],
          );
          tx.notifyChanged(['lifecycle_rows']);
          await tx.savepoint((child) async {
            Database.fromSql(child).invalidate([_schema]);
            child.notifyChanged(['lifecycle_rows']);
          });
          expect(rows, hasLength(1));
        });
        await changed.future;
        await Future<void>.delayed(Duration.zero);
        expect(rows, hasLength(2));
        expect(driver.reads, 2);
        await expectLater(
          raw.transaction((tx) async {
            await tx.savepoint((child) async {
              Database.fromSql(child).invalidate([_schema]);
            });
            throw StateError('rollback outer transaction');
          }),
          throwsStateError,
        );
        await Future<void>.delayed(Duration.zero);
        expect(rows, hasLength(2));
      } finally {
        await subscription.cancel();
        await db.close();
      }
    },
  );
}

final class _Driver implements Driver<Sqlite> {
  bool closed = false;
  int reads = 0;
  @override
  final capabilities = const Capabilities(
    dialect: SqlDialect.sqlite,
    maxParameters: 999,
  );
  @override
  Future<T> run<T>(Future<T> Function(SqlConnection) action) =>
      action(_Connection(this));
  @override
  Future<void> close() async => closed = true;
}

final class _Connection(final _Driver driver) implements SqlConnection {
  bool active = false;
  @override
  bool get transactionActive => active;
  @override
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    if (command.sql == 'BEGIN') active = true;
    if (command.sql == 'COMMIT' || command.sql == 'ROLLBACK') active = false;
    if (command.sql.startsWith('SELECT')) {
      driver.reads++;
      return const SqlResult([
        [1],
      ]);
    }
    return const SqlResult([], affectedRows: 1);
  }

  @override
  Future<SqlCursor> openCursor(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) =>
      throw UnsupportedError('No cursor needed for this lifecycle regression.');
  @override
  Future<void> invalidate() async {}
}
