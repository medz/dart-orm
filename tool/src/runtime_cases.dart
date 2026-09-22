import 'package:orm/orm.dart';

import '../../example/schema.orm.dart';

typedef UserCard = ({int id, String email});
typedef PostCard = ({int id, String title});
typedef UserPosts = ({int id, String email, List<PostCard> posts});
typedef ScoreCount = ({int score, int users});

const runtimeCases = ['full_rows', 'two_columns', 'three_posts', 'aggregate'];
const firstUser = 10001;
const userCount = 100;
final _nullableText = Codecs.text.nullable();

Query<Object?, Fields> runtimeQuery(Database<Backend> db, String name) {
  final users = db.user.where((u) => u.id.gte(.value(firstUser)));
  return switch (name) {
    'full_rows' => users.orderBy((u) => [u.id.asc()]),
    'two_columns' =>
      users
          .orderBy((u) => [u.id.asc()])
          .select(
            (u) => (u.id, u.email).map((id, email) => (id: id, email: email)),
          ),
    'three_posts' =>
      users
          .orderBy((u) => [u.id.asc()])
          .select(
            (u) => (
              u.id,
              u.email,
              u.posts
                  .orderBy((p) => [p.id.desc()])
                  .take(3)
                  .select(
                    (p) => (
                      p.id,
                      p.title,
                    ).map((id, title) => (id: id, title: title)),
                  )
                  .many(),
            ).map((id, email, posts) => (id: id, email: email, posts: posts)),
          ),
    'aggregate' =>
      users
          .groupBy((u) => [u.score])
          .orderBy((u) => [u.score.asc()])
          .select(
            (u) => (
              u.score,
              u.id.count(),
            ).map((score, users) => (score: score, users: users)),
          ),
    _ => throw ArgumentError.value(name, 'case'),
  };
}

/// Precompiled SQL captured once from the corresponding ORM query. Both paths
/// share the same Driver; this baseline measures the query layer above it.
final class RuntimeCase {
  final String name;
  final Database<Backend> db;
  final Query<Object?, Fields> query;
  final List<SqlCommand> commands;
  final List<int> keyParameters;
  RuntimeCase._(
    this.name,
    this.db,
    this.query,
    this.commands,
    this.keyParameters,
  );

  static Future<RuntimeCase> prepare(Database<Backend> db, String name) async {
    final capture = CaptureDriver(db.driver);
    final expected = await runtimeQuery(Database(capture), name).get();
    final query = runtimeQuery(db, name);
    final commands = capture.commands;
    final keys = name == 'three_posts'
        ? [
            for (final (i, p) in commands.last.parameters.indexed)
              if (p is int && p >= firstUser && p < firstUser + userCount) i,
          ]
        : <int>[];
    if (commands.length != (name == 'three_posts' ? 2 : 1) ||
        name == 'three_posts' && keys.length != userCount) {
      throw StateError('Unexpected SQL/key shape for $name.');
    }
    final result = RuntimeCase._(name, db, query, commands, keys);
    final actual = await result.raw();
    if (canonicalRows(expected).toString() !=
        canonicalRows(actual).toString()) {
      throw StateError('Raw and ORM results differ for $name.');
    }
    // Independently check the seeded business shape, not just mutual agreement.
    if (expected.length != (name == 'aggregate' ? 10 : userCount)) {
      throw StateError('Unexpected root count for $name.');
    }
    if (name == 'three_posts') {
      for (final row in expected.cast<UserPosts>()) {
        final last = (row.id - firstUser + 1) * 10;
        if (row.posts.map((p) => p.id).join(',') !=
            '$last,${last - 1},${last - 2}') {
          throw StateError('Incorrect per-parent ordering/limit.');
        }
      }
    }
    if (name == 'aggregate' &&
        expected.cast<ScoreCount>().any((r) => r.users != 10)) {
      throw StateError('Incorrect grouped counts.');
    }
    return result;
  }

  Future<List<Object?>> run(String lane) => lane == 'orm' ? query.get() : raw();

  Future<List<Object?>> raw({Driver<Backend>? driver}) =>
      (driver ?? db.driver).run((connection) async {
        final rows = (await connection.execute(commands.first)).rows;
        switch (name) {
          case 'full_rows':
            return [
              for (final row in rows)
                (
                  id: Codecs.integer.decode(row[0]),
                  email: Codecs.text.decode(row[1]),
                  nickname: _nullableText.decode(row[2]),
                  score: Codecs.integer.decode(row[3]),
                ),
            ];
          case 'two_columns':
            return [
              for (final row in rows)
                (
                  id: Codecs.integer.decode(row[0]),
                  email: Codecs.text.decode(row[1]),
                ),
            ];
          case 'aggregate':
            return [
              for (final row in rows)
                (
                  score: Codecs.integer.decode(row[0]),
                  users: Codecs.integer.decode(row[1]),
                ),
            ];
          case 'three_posts':
            final keys = [
              for (final row in rows) Codecs.integer.decode(row[0]),
            ];
            if (keys.length != keyParameters.length) {
              throw StateError('Fixture keys changed.');
            }
            final parameters = commands.last.parameters.toList();
            for (final (i, key) in keys.indexed) {
              parameters[keyParameters[i]] = Codecs.integer.encode(key);
            }
            final children = (await connection.execute(
              SqlCommand(commands.last.sql, parameters),
            )).rows;
            final grouped = <int, List<PostCard>>{};
            for (final row in children) {
              final parent = Codecs.integer.decode(row[2]);
              (grouped[parent] ??= []).add((
                id: Codecs.integer.decode(row[0]),
                title: Codecs.text.decode(row[1]),
              ));
            }
            return [
              for (final row in rows)
                (
                  id: Codecs.integer.decode(row[0]),
                  email: Codecs.text.decode(row[1]),
                  posts: List<PostCard>.unmodifiable(
                    grouped[Codecs.integer.decode(row[0])] ?? const [],
                  ),
                ),
            ];
          default:
            throw StateError(name);
        }
      });
}

List<Object?> canonicalRows(List<Object?> rows) => [
  for (final row in rows)
    switch (row) {
      User() => [row.id, row.email, row.nickname, row.score],
      UserCard() => [row.id, row.email],
      UserPosts() => [
        row.id,
        row.email,
        [
          for (final p in row.posts) [p.id, p.title],
        ],
      ],
      ScoreCount() => [row.score, row.users],
      _ => throw StateError('Unknown result shape: $row'),
    },
];

/// Used only for SQL/volume verification, never in the latency timing path.
final class CaptureDriver(
  final Driver<Backend> inner, {
  final bool retainResults = true,
}) implements Driver<Backend> {
  final commands = <SqlCommand>[];
  final results = <SqlResult>[];
  final acquireMicros = <int>[];
  final sqlMicros = <int>[];
  @override
  Capabilities get capabilities => inner.capabilities;
  @override
  Future<R> run<R>(Future<R> Function(SqlConnection) action) {
    final clock = Stopwatch()..start();
    return inner.run((connection) {
      acquireMicros.add(clock.elapsedMicroseconds);
      return action(_CaptureConnection(connection, this));
    });
  }

  @override
  Future<void> close() async {} // Borrowed exclusively for the benchmark.
}

final class _CaptureConnection(
  final SqlConnection inner,
  final CaptureDriver owner,
) implements SqlConnection {
  @override
  bool? get transactionActive => inner.transactionActive;
  @override
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    if (owner.retainResults) owner.commands.add(command);
    final clock = Stopwatch()..start();
    final result = await inner.execute(command, options: options);
    owner.sqlMicros.add(clock.elapsedMicroseconds);
    if (owner.retainResults) owner.results.add(result);
    return result;
  }

  @override
  Future<SqlCursor> openCursor(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) => inner.openCursor(command, options: options);
  @override
  Future<void> invalidate() => inner.invalidate();
}
