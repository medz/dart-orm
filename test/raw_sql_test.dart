import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:orm/sqlite.dart';
import 'package:orm/postgres.dart';
import 'package:test/test.dart';

final idColumn = Column('id', AuthorId.codec);
final nameColumn = Column('name', Codecs.text);
final authorSchema = TableSchema(
  'authors',
  columns: [idColumn, nameColumn],
  primaryKey: ['id'],
);
final authorTable = Table<({AuthorId id, String name}), _AuthorFields>(
  authorSchema,
  _AuthorFields.new,
  (a) => (a.id, a.name).map((id, name) => (id: id, name: name)),
);
final u = authorTable.alias().fields;
final titleColumn = Column('title', Codecs.text);
final authorRow = (
  u.id.result(),
  u.name.result(),
).map((id, name) => (id: id, name: name));
final allAuthors = Sql('SELECT id, name FROM authors ORDER BY id')
    .returns(authorRow);
SqlQuery<({AuthorId id, String name})> authorById(AuthorId id) => Sql(
  'SELECT name, id FROM authors WHERE id = :id',
  parameters: {'id': u.id.bind(id)},
).returns(authorRow);

void main() {
  shared(
    'sqlite',
    (observe, decode) => sqlite(
      const SqliteOptions.memory(),
      onQuery: observe,
      onDecode: decode,
    ),
  );
  final pgUrl = Platform.environment['ORM_TEST_POSTGRES'];
  if (pgUrl != null) {
    shared(
      'postgres',
      (observe, decode) async => postgres(
        PostgresOptions(
          url: Uri.parse(pgUrl),
          tls: PostgresTls.disable,
          maxConnections: 2,
          schema: 'orm_raw_sql_tests',
        ),
        onQuery: observe,
        onDecode: decode,
      ),
    );
  }

  test('detached description executes against independent SQLite databases', () async {
    final first = await sqlite(const SqliteOptions.memory());
    final second = await sqlite(const SqliteOptions.memory());
    try {
      for (final (db, name) in [(first, 'first'), (second, 'second')]) {
        await db.raw(
          Sql(
            'CREATE TABLE authors(id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
          ),
        );
        await db.raw(
          Sql(
            'INSERT INTO authors VALUES(1, :name)',
            parameters: {'name': name},
          ),
        );
      }
      expect((await first.query(allAuthors)).single.name, 'first');
      expect((await second.query(allAuthors)).single.name, 'second');
    } finally {
      await first.close();
      await second.close();
    }
  });
  test('nested bindings renumber per engine and repeat positional values', () {
    final a = Sql('SELECT :id AS value WHERE :id = :id', parameters: {'id': 1});
    final b = Sql('SELECT :id AS value', parameters: {'id': 2});
    final union = Sql.join([a, b], separator: ' UNION ALL ');
    final pg = union.compile(
      const Capabilities(dialect: SqlDialect.postgres, maxParameters: 10),
    );
    expect(
      pg.sql.replaceAll(RegExp(r'\s+'), ' '),
      r'SELECT $1 AS value WHERE $1 = $1 UNION ALL SELECT $2 AS value',
    );
    expect(pg.parameters, [1, 2]);
    for (final dialect in [SqlDialect.mysql, SqlDialect.mariadb]) {
      final mysql = union.compile(
        Capabilities(dialect: dialect, maxParameters: 10),
      );
      expect(
        mysql.sql.replaceAll(RegExp(r'\s+'), ' '),
        'SELECT ? AS value WHERE ? = ? UNION ALL SELECT ? AS value',
      );
      expect(mysql.parameters, [1, 1, 1, 2]);
    }
  });
  test(
    'PostgreSQL physical namespace quotes separately and rejects other engines',
    () {
      final table = TableSchema(
        'weird"table',
        namespace: 'orm_raw_auth_tests',
        columns: [],
      );
      final fragment = Sql.table(table);
      expect(
        fragment
            .compile(
              const Capabilities(
                dialect: SqlDialect.postgres,
                maxParameters: 10,
              ),
            )
            .sql,
        '"orm_raw_auth_tests"."weird""table"',
      );
      expect(
        () => fragment.compile(
          const Capabilities(dialect: SqlDialect.sqlite, maxParameters: 10),
        ),
        throwsA(isA<OrmException>()),
      );
    },
  );
}

void shared(
  String name,
  Future<Database<Backend>> Function(
    void Function(QueryEvent),
    void Function(DecodeEvent),
  )
  open,
) {
  group(name, () {
    late Database<Backend> db;
    var selects = 0, decodes = 0;
    setUp(() async {
      db = await open(
        (e) {
          if (e.sql.trimLeft().startsWith('SELECT')) selects++;
        },
        (_) {
          decodes++;
        },
      );
      if (name == 'postgres') {
        await db.raw(Sql('DROP SCHEMA IF EXISTS orm_raw_sql_tests CASCADE'));
        await db.raw(Sql('CREATE SCHEMA orm_raw_sql_tests'));
      }
      await db.raw(Sql('DROP TABLE IF EXISTS posts'));
      await db.raw(Sql('DROP TABLE IF EXISTS authors'));
      await db.raw(
        Sql(
          'CREATE TABLE authors(id BIGINT PRIMARY KEY, name TEXT NOT NULL, email TEXT)',
        ),
      );
      await db.raw(
        Sql(
          'CREATE TABLE posts(id BIGINT PRIMARY KEY, author_id BIGINT NOT NULL, title TEXT NOT NULL, points BIGINT NOT NULL)',
        ),
      );
      await db.raw(
        Sql("INSERT INTO authors VALUES(1, 'Ada', NULL), (2, 'Empty', NULL)"),
      );
      await db.raw(Sql("INSERT INTO posts VALUES(1, 1, 'SQL', 3)"));
      selects = decodes = 0;
    });
    tearDown(() async {
      if (name == 'postgres') {
        await db.raw(Sql('DROP SCHEMA IF EXISTS orm_raw_sql_tests CASCADE'));
        await db.raw(Sql('DROP SCHEMA IF EXISTS orm_raw_auth_tests CASCADE'));
      }
      await db.close();
    });

    test('raw SQL works without schema and retains duplicate labels and write counts', () async {
      final raw = await db.raw(Sql('SELECT 1 AS n, 2 AS n'));
      expect(raw.columns, ['n', 'n']);
      expect(raw.rows.single, [1, 2]);
      final update = await db.raw(
        Sql(
          'UPDATE authors SET name = :name WHERE id = :id',
          parameters: {'name': 'changed', 'id': 2},
        ),
      );
      expect(update.affectedRows, 1);
    });
    test('reuses result mapping and validates type independently of SQL column order', () async {
      AuthorId.encodes = AuthorId.decodes = 0;
      final List<({AuthorId id, String name})> result = await db.query(
        authorById(const AuthorId(1)),
      );
      expect((result.single.id.value, result.single.name), (1, 'Ada'));
      expect((AuthorId.encodes, AuthorId.decodes), (1, 1));
      expect((selects, decodes), (1, 1));
      expect(await db.query(authorById(const AuthorId(99))), isEmpty);
      expect((await db.query(allAuthors)).length, 2);
    });
    test('missing column is rejected even on an empty result without invoking mapper', () async {
      var calls = 0;
      final shape = u.name.result().map((name) {
        calls++;
        return name;
      });
      await expectLater(
        db.query(Sql('SELECT id FROM authors WHERE 1=0').returns(shape)),
        throwsA(isA<OrmException>()),
      );
      expect(calls, 0);
      expect(selects, 1);
    });
    test('ambiguous selected aliases are rejected even with no rows', () async {
      await expectLater(
        db.query(
          Sql('SELECT id AS name, name FROM authors WHERE 1=0')
              .returns(u.name.result()),
        ),
        throwsA(isA<OrmException>()),
      );
    });
    test('separate fragments have separate parameter names; CTE reuses result schema', () async {
      final left = Sql(
        'SELECT id, name FROM authors WHERE id = :id',
        parameters: {'id': 1},
      );
      final right = Sql(
        'SELECT id, name FROM authors WHERE id = :id',
        parameters: {'id': 2},
      );
      final union = Sql.join([left, right], separator: ' UNION ALL ');
      final q = Sql.parts([
        'WITH candidates AS (',
        union,
        ') SELECT id, name FROM candidates ORDER BY id',
      ]).returns(authorRow);
      expect((await db.query(q)).map((r) => r.id.value), [1, 2]);
      expect(q.sql.compile(db.capabilities).parameters, [1, 2]);
    });
    test(
      'schema identifier and bound values cannot become SQL syntax',
      () async {
        final q = Sql.parts([
          'SELECT id, name FROM ',
          Sql.table(authorSchema),
          ' WHERE ',
          Sql('name = :name', parameters: {'name': "Ada' OR 1=1 --"}),
        ]).returns(authorRow);
        expect(await db.query(q), isEmpty);
        final id = Sql.identifier('a"b');
        expect(
          (await db.raw(Sql.parts(['SELECT 7 AS ', id]))).columns.single,
          'a"b',
        );
      },
    );
    test('explicit nullable result handles LEFT JOIN without changing physical codec', () async {
      final title = titleColumn.result().nullable();
      final shape = (
        u.id.result(as: 'owner'),
        title,
      ).map((id, title) => (id: id, title: title));
      final rows = await db.query(
        Sql(
          'SELECT a.id AS owner, p.title FROM authors a LEFT JOIN posts p ON a.id=p.author_id ORDER BY a.id',
        ).returns(shape),
      );
      expect(rows.map((r) => (r.id.value, r.title)), [(1, 'SQL'), (2, null)]);
      expect(titleColumn.codec.acceptsNull, isFalse);
    });
    test('same descriptor uses caller transaction and rollback', () async {
      await expectLater(
        db.transaction((tx) async {
          await tx.raw(Sql("UPDATE authors SET name='pending' WHERE id=1"));
          expect(
            (await tx.query(authorById(const AuthorId(1)))).single.name,
            'pending',
          );
          throw StateError('rollback');
        }),
        throwsStateError,
      );
      expect(
        (await db.query(authorById(const AuthorId(1)))).single.name,
        'Ada',
      );
    });
    test('typed DML returns rows; decode failure invalidates transaction even if caught', () async {
      final change = Sql(
        "UPDATE authors SET name='pending' WHERE id=1 RETURNING id, name",
      ).returns(authorRow);
      await expectLater(
        db.transaction((tx) async {
          expect(
            (await tx.query(change, changedTables: [authorSchema])).single.name,
            'pending',
          );
          try {
            await tx.query(
              Sql("UPDATE authors SET name='bad' WHERE id=1 RETURNING id")
                  .returns(authorRow),
            );
          } on OrmException {
            /* commit must still fail */
          }
        }),
        throwsA(isA<OrmException>()),
      );
      expect(
        (await db.query(authorById(const AuthorId(1)))).single.name,
        'Ada',
      );
    });
    test(
      'outside a transaction decoding failure does not undo executed writes',
      () async {
        await expectLater(
          db.query(
            Sql("UPDATE authors SET name='committed' WHERE id=1 RETURNING id")
                .returns(authorRow),
          ),
          throwsA(isA<OrmException>()),
        );
        expect(
          (await db.query(authorById(const AuthorId(1)))).single.name,
          'committed',
        );
      },
    );
    test(
      'descriptor has metadata before execution and explicit dialect dispatch',
      () async {
        expect(authorRow.columns.map((c) => (c.name, c.codec.acceptsNull)), [
          ('id', false),
          ('name', false),
        ]);
        final byEngine = Sql.dialects({
          SqlDialect.sqlite: Sql('SELECT 1 AS number'),
          SqlDialect.postgres: Sql('SELECT 2::bigint AS number'),
        }).returns(ResultColumn('number', Codecs.integer));
        expect((await db.query(byEngine)).single, name == 'sqlite' ? 1 : 2);
        expect(
          () => Sql.dialects({}).compile(db.capabilities),
          throwsA(isA<OrmException>()),
        );
      },
    );
    test(
      'named placeholders ignore quotes/comments and preserve PostgreSQL cast',
      () async {
        final q = Sql(
          "SELECT ':ignored' AS literal, :id AS value /* :ignored */",
          parameters: {'id': 3},
        );
        expect((await db.raw(q)).rows.single, [
          ':ignored',
          name == 'postgres' ? '3' : 3,
        ]);
        if (name == 'postgres') {
          final pg = Sql(
            r'SELECT $tag$:ignored$tag$ AS literal, :id::bigint AS value',
            parameters: {'id': 4},
          );
          expect((await db.raw(pg)).rows.single, [':ignored', 4]);
        }
      },
    );
    test('parameter maps are copied; missing bindings and limits fail before execution', () {
      final parameters = <String, Object?>{'n': 3};
      final q = Sql('SELECT :n AS number', parameters: parameters);
      parameters['n'] = 4;
      expect(q.compile(db.capabilities).parameters, [3]);
      expect(
        () => Sql('SELECT :missing').compile(db.capabilities),
        throwsA(isA<OrmException>()),
      );
      expect(
        () => q.compile(Capabilities(dialect: db.dialect, maxParameters: 0)),
        throwsA(isA<OrmException>()),
      );
      expect(selects, 0);
    });
    test(
      'scalar and nested result mappings preserve their Dart types',
      () async {
        final nested = (
          authorRow,
          ResultColumn('total', Codecs.integer),
        ).map((author, total) => (author: author, total: total));
        final rows = await db.query(
          Sql('SELECT id, name, 1 AS total FROM authors ORDER BY id')
              .returns(nested),
        );
        final List<({({AuthorId id, String name}) author, int total})> typed =
            rows;
        expect(typed.first.author.name, 'Ada');
      },
    );
    test(
      'driver cursor preserves column metadata for an empty batch',
      () async {
        await db.transaction(
          (tx) => tx.run((connection) async {
            final cursor = await connection.openCursor(
              SqlCommand('SELECT id, name FROM authors WHERE 1=0'),
            );
            try {
              final batch = await cursor.fetch(8);
              expect(batch.rows, isEmpty);
              expect(batch.columns, ['id', 'name']);
              expect(
                authorRow.bind(batch.columns),
                isA<({AuthorId id, String name}) Function(List<Object?>)>(),
              );
            } finally {
              await cursor.close();
            }
          }),
        );
      },
    );
    test('native checks accept declared shape and preserve prepared-statement state', () async {
      final result = await checkSqlQuery(
        db.sql,
        Sql('SELECT 42 AS n').returns(ResultColumn('n', Codecs.integer)),
      );
      expect(result.structureChecked, true);
      expect(result.nullabilityChecked, false);
      expect(result.storageTypesChecked, name == 'postgres');
      if (name == 'postgres') {
        final left = await db.execute(
          SqlCommand(
            "SELECT COUNT(*) FROM pg_catalog.pg_prepared_statements WHERE name LIKE '_orm_check_%'",
          ),
        );
        expect(left.rows.single.single, 0);
      }
    });

    test(
      'native checks reject syntax, missing tables and missing result aliases',
      () async {
        for (final sql in [
          'SELECT FROM',
          'SELECT n FROM missing_table',
          'SELECT 1 AS wrong',
        ]) {
          await expectLater(
            checkSqlQuery(
              db.sql,
              Sql(sql).returns(ResultColumn('n', Codecs.integer)),
            ),
            throwsA(isA<OrmException>()),
            reason: sql,
          );
        }
        if (name == 'postgres') {
          await expectLater(
            checkSqlQuery(
              db.sql,
              Sql("SELECT 'text'::text AS n")
                  .returns(ResultColumn('n', Codecs.integer)),
            ),
            throwsA(isA<OrmException>()),
          );
        }
        expect((await db.raw(Sql('SELECT 42'))).rows.single.single, 42);
      },
    );

    test('native checks do not evaluate application expressions', () async {
      final sql = name == 'sqlite'
          ? 'SELECT abs(-9223372036854775808) AS n'
          : 'SELECT 1 / 0 AS n';
      expect(
        await checkSqlQuery(
          db.sql,
          Sql(sql).returns(ResultColumn('n', Codecs.integer)),
        ),
        isA<SqlCheck>(),
      );
      await expectLater(db.execute(SqlCommand(sql)), throwsA(anything));
      if (name == 'postgres') {
        await db.execute(SqlCommand('CREATE SEQUENCE query_check_counter'));
        await checkSqlQuery(
          db.sql,
          Sql("SELECT nextval('query_check_counter') AS n")
              .returns(ResultColumn('n', Codecs.integer)),
        );
        expect(
          (await db.execute(
            SqlCommand('SELECT is_called FROM query_check_counter'),
          )).rows.single.single,
          false,
        );
      }
    });

    test(
      'all codec families preserve typed bound values in queries and streams',
      () async {
        Future<void> echo<T>(
          T value,
          Codec<T> codec, [
          Object? expected,
        ]) async {
          final query = Sql(
            'SELECT :v AS v',
            parameters: {'v': SqlValue(value, codec)},
          ).returns(ResultColumn('v', codec));
          final result = (await db.query(query)).single;
          if (result is SqlJson) {
            expect(result.value, (value as SqlJson).value);
          } else {
            expect(result, expected ?? value);
          }
          expect(await db.streamSql(query, batchSize: 1).length, 1);
        }

        await echo(true, Codecs.boolean);
        await echo(3.25, Codecs.real);
        await echo(BigInt.parse('900719925474099312345'), Codecs.bigint);
        await echo(
          Decimal.parse('12345678901234567890.00000000001'),
          Codecs.decimal,
        );
        await echo(DateTime.utc(2024, 1, 2, 3, 4, 5, 6, 7), Codecs.dateTime);
        await echo(LocalDate.parse('0001-01-01 BC'), Codecs.date);
        await echo(LocalTime.parse('12:34:56.123456'), Codecs.time);
        await echo(
          LocalDateTime.parse('2024-01-02T12:34:56.123456'),
          Codecs.localDateTime,
        );
        await echo(Uint8List.fromList([0, 1, 255]), Codecs.bytes);
        await echo({
          'a': [1, null],
        }, Codecs.json);
        await echo(const SqlJson(null), Codecs.jsonDocument);
        await echo<String?>(null, Codecs.text.nullable());
      },
    );

    test('typed cursor checks empty metadata, releases on cancel and poisons failed transactions', () async {
      expect(
        await db
            .streamSql(allAuthors, batchSize: 1)
            .map((r) => r.name)
            .toList(),
        ['Ada', 'Empty'],
      );
      expect(
        await db.streamSql(authorById(const AuthorId(99))).toList(),
        isEmpty,
      );
      await expectLater(
        db
            .streamSql(
              Sql('SELECT id FROM authors WHERE 1=0').returns(authorRow),
            )
            .toList(),
        throwsA(isA<OrmException>()),
      );
      expect((await db.streamSql(allAuthors, batchSize: 1).first).name, 'Ada');
      expect((await db.query(allAuthors)).length, 2);
      await expectLater(
        db.transaction((tx) async {
          await tx.raw(Sql("UPDATE authors SET name='pending' WHERE id=1"));
          try {
            await tx
                .streamSql(
                  Sql('SELECT id FROM authors WHERE 1=0').returns(authorRow),
                )
                .toList();
          } on OrmException {
            /* caught decoding error must still roll back */
          }
        }),
        throwsA(isA<OrmException>()),
      );
      expect((await db.query(allAuthors)).first.name, 'Ada');
    });

    test(
      'watch reuses declared reads and observes commits but not rollbacks',
      () async {
        await expectLater(
          db.watchSql(allAuthors, reads: []).first,
          throwsA(isA<OrmException>()),
        );
        final snapshots = StreamIterator(
          db.watchSql(allAuthors, reads: [authorSchema]),
        );
        try {
          expect(await snapshots.moveNext(), true);
          expect(snapshots.current.first.name, 'Ada');
          final next = snapshots.moveNext();
          await expectLater(
            db.transaction((tx) async {
              await tx.raw(
                Sql("UPDATE authors SET name='rollback' WHERE id=1"),
                changedTables: [authorSchema],
              );
              throw StateError('rollback');
            }),
            throwsStateError,
          );
          await db.transaction(
            (tx) => tx.raw(
              Sql("UPDATE authors SET name='commit' WHERE id=1"),
              changedTables: [authorSchema],
            ),
          );
          expect(await next.timeout(const Duration(seconds: 3)), true);
          expect(snapshots.current.first.name, 'commit');
        } finally {
          await snapshots.cancel();
        }
        await db.session((session) async {
          await expectLater(
            session.watchSql(allAuthors, reads: [authorSchema]).first,
            throwsA(isA<OrmException>()),
          );
        });
      },
    );

    test(
      'value-list composition and empty lists use explicit SQL semantics',
      () async {
        SqlQuery<({AuthorId id, String name})> byIds(List<AuthorId> ids) =>
            Sql.parts([
              'SELECT id, name FROM authors WHERE',
              if (ids.isEmpty)
                'FALSE'
              else ...[
                'id IN (',
                Sql.join(ids.map((id) => Sql.value(u.id.bind(id)))),
                ')',
              ],
              'ORDER BY id',
            ]).returns(authorRow);
        expect(
          (await db.query(byIds([const AuthorId(1), const AuthorId(2)])))
              .length,
          2,
        );
        expect(await db.query(byIds([])), isEmpty);
      },
    );
    if (name == 'postgres') {
      test(
        'same-named tables across PostgreSQL schemas remain distinct',
        () async {
          await db.raw(Sql('CREATE SCHEMA IF NOT EXISTS orm_raw_auth_tests'));
          await db.raw(Sql('DROP TABLE IF EXISTS orm_raw_auth_tests.authors'));
          await db.raw(
            Sql(
              'CREATE TABLE orm_raw_auth_tests.authors(id TEXT PRIMARY KEY, public_id BIGINT NOT NULL)',
            ),
          );
          await db.raw(
            Sql("INSERT INTO orm_raw_auth_tests.authors VALUES('auth-A',1)"),
          );
          final auth = TableSchema(
            'authors',
            namespace: 'orm_raw_auth_tests',
            columns: [],
          );
          final public = TableSchema(
            'authors',
            namespace: 'orm_raw_sql_tests',
            columns: [],
          );
          final shape = (
            u.id.result(as: 'public_id'),
            ResultColumn('auth_id', Codecs.text),
          ).map((id, authId) => (id: id, authId: authId));
          final q = Sql.parts([
            'SELECT p.id AS public_id, a.id AS auth_id FROM ',
            Sql.table(public),
            ' p JOIN ',
            Sql.table(auth),
            ' a ON a.public_id=p.id',
          ]).returns(shape);
          final row = (await db.query(q)).single;
          expect((row.id.value, row.authId), (1, 'auth-A'));
        },
      );
    }
  }, tags: name);
}

final class _AuthorFields extends Fields {
  _AuthorFields(super.table);
  late final id = column(idColumn);
  late final name = column(nameColumn);
}

final class AuthorId {
  final int value;
  const AuthorId(this.value);
  static int encodes = 0;
  static int decodes = 0;
  static const codec = Codec<AuthorId>.integer(_decode, _encode);
  static AuthorId _decode(Object? raw) {
    decodes++;
    return AuthorId(Codecs.integer.decode(raw));
  }

  static int _encode(AuthorId id) {
    encodes++;
    return id.value;
  }

  @override
  String toString() => 'AuthorId($value)';
}
