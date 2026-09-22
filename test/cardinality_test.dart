@Tags(['sqlite'])
library;

import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

enum _Read { first, firstOrNull, single, singleOrNull }

void main() {
  late Database<Sqlite> db;

  setUp(() async {
    db = Database(await SqliteDriver.open(const SqliteOptions.memory()));
    await db.execute(
      SqlCommand(
        'CREATE TABLE cardinality (id INTEGER PRIMARY KEY, label TEXT, hits INTEGER NOT NULL)',
      ),
    );
  });
  tearDown(() => db.close());

  Future<void> seed(int count) async {
    for (var id = 1; id <= count; id++) {
      await db.execute(
        SqlCommand(
          'INSERT INTO cardinality (id, label, hits) VALUES (?, NULL, 0)',
          [id],
        ),
      );
    }
  }

  for (final count in [0, 1, 2]) {
    for (final read in _Read.values) {
      test('Query ${read.name} distinguishes $count rows', () async {
        await seed(count);
        final query = db
            .table(_table)
            .orderBy((row) => [row.id.asc()])
            .select((row) => row.id);
        final result = _readQuery(query, read);
        if (_rejects(read, count)) {
          await expectLater(result, throwsA(_cardinality));
        } else {
          expect(await result, count == 0 ? null : 1);
        }
      }, tags: 'sqlite');

      test(
        'Returning ${read.name} checks $count rows after the entire write',
        () async {
          await seed(count);
          final returning = db
              .table(_table)
              .update((row) => [row.hits.increment(1)])
              .returning((row) => row.id);
          final result = _readReturning(returning, read);
          if (_rejects(read, count)) {
            await expectLater(result, throwsA(_cardinality));
          } else if (count == 0) {
            expect(await result, isNull);
          } else {
            expect(await result, isIn(List.generate(count, (i) => i + 1)));
          }
          // RETURNING cardinality is a Dart result check, not a SQL row limit.
          expect(
            await db.table(_table).select((row) => row.hits).get(),
            List.filled(count, 1),
          );
        },
        tags: 'sqlite',
      );
    }
  }

  for (final read in _Read.values) {
    test('Query ${read.name} counts SQL NULL as a row', () async {
      await seed(1);
      expect(
        await _readQuery(db.table(_table).select((row) => row.label), read),
        isNull,
      );
      if (read == _Read.single || read == _Read.singleOrNull) {
        await db.execute(
          SqlCommand('INSERT INTO cardinality VALUES (2, NULL, 0)'),
        );
        await expectLater(
          _readQuery(db.table(_table).select((row) => row.label), read),
          throwsA(_cardinality),
        );
      }
    }, tags: 'sqlite');

    test('Returning ${read.name} counts SQL NULL as a row', () async {
      await seed(1);
      final returning = db
          .table(_table)
          .update((row) => [row.hits.increment(1)])
          .returning((row) => row.label);
      expect(await _readReturning(returning, read), isNull);
      if (read == _Read.single || read == _Read.singleOrNull) {
        await db.execute(
          SqlCommand('INSERT INTO cardinality VALUES (2, NULL, 0)'),
        );
        await expectLater(
          _readReturning(returning, read),
          throwsA(_cardinality),
        );
        expect(
          await db
              .table(_table)
              .orderBy((row) => [row.id.asc()])
              .select((row) => row.hits)
              .get(),
          [2, 1],
        );
      }
    }, tags: 'sqlite');
  }

  test('read cardinality respects an explicit limit and offset', () async {
    await seed(2);
    final query = db
        .table(_table)
        .orderBy((row) => [row.id.asc()])
        .select((row) => row.id);
    expect(await query.take(1).single(), 1);
    expect(await query.take(1).singleOrNull(), 1);
    expect(await query.skip(1).single(), 2);
    expect(await query.skip(2).singleOrNull(), isNull);
    expect(await query.take(0).firstOrNull(), isNull);
    expect(await query.take(0).singleOrNull(), isNull);
    await expectLater(query.take(0).first(), throwsA(_cardinality));
    await expectLater(query.take(0).single(), throwsA(_cardinality));
  }, tags: 'sqlite');

  for (final read in [_Read.single, _Read.singleOrNull]) {
    test(
      'Returning ${read.name} failure rolls back an enclosing transaction',
      () async {
        await seed(2);
        await expectLater(
          db.transaction(
            (tx) => _readReturning(
              tx
                  .table(_table)
                  .update((row) => [row.hits.increment(1)])
                  .returning((row) => row.id),
              read,
            ),
          ),
          throwsA(_cardinality),
        );
        expect(await db.table(_table).select((row) => row.hits).get(), [0, 0]);
      },
      tags: 'sqlite',
    );
  }

  test('a strict empty read rolls back preceding transaction writes', () async {
    await seed(1);
    await expectLater(
      db.transaction((tx) async {
        await tx
            .table(_table)
            .update((row) => [row.hits.increment(1)])
            .execute();
        return tx.table(_table).where((row) => row.id.eq(999)).first();
      }),
      throwsA(_cardinality),
    );
    expect(await db.table(_table).select((row) => row.hits).single(), 0);
  }, tags: 'sqlite');
}

bool _rejects(_Read read, int count) => switch (read) {
  _Read.first => count == 0,
  _Read.firstOrNull => false,
  _Read.single => count != 1,
  _Read.singleOrNull => count > 1,
};

Future<T?> _readQuery<T>(Query<T, _Fields> query, _Read read) => switch (read) {
  _Read.first => query.first(),
  _Read.firstOrNull => query.firstOrNull(),
  _Read.single => query.single(),
  _Read.singleOrNull => query.singleOrNull(),
};

Future<T?> _readReturning<T>(Returning<T> returning, _Read read) =>
    switch (read) {
      _Read.first => returning.first(),
      _Read.firstOrNull => returning.firstOrNull(),
      _Read.single => returning.single(),
      _Read.singleOrNull => returning.singleOrNull(),
    };

final _cardinality = isA<OrmException>().having(
  (error) => error.code,
  'code',
  'QUERY.CARDINALITY',
);
final _id = Column('id', Codecs.integer);
final _label = Column('label', Codecs.text.nullable(), nullable: true);
final _hits = Column('hits', Codecs.integer);
final _schema = TableSchema(
  'cardinality',
  columns: [_id, _label, _hits],
  primaryKey: ['id'],
);
final _table = Table(
  _schema,
  _Fields.new,
  (row) => (row.id, row.label, row.hits).row,
);

final class _Fields extends Fields {
  _Fields(super.table);
  late final id = column(_id);
  late final label = column(_label);
  late final hits = column(_hits);
}
