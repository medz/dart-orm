// @dart = 3.13
// Standalone Dart 3.13 language/type experiment for the accompanying report.
// Synthetic rows only. This is not an ORM, SQL compiler, or database test.
// Run: dart --enable-asserts research/type_feasibility.dart

// Dart 3.13.3 proof of type inference and deterministic selection/decode separation.
// No database, SQL compiler, query planner, or ORM is implemented here.
typedef Row = Map<String, Object?>;
typedef Read = T Function<T>(Expr<T> expression);

abstract interface class Selection<T> {
  List<String> get plan;
  T decode(Row row);
}

final class Expr<T> implements Selection<T> {
  const Expr(this.name, this.codec);
  final String name;
  final T Function(Object?) codec;
  @override
  List<String> get plan => [name];
  @override
  T decode(Row row) => codec(row[name]);
}

final class Mapped<T> implements Selection<T> {
  const Mapped(this.plan, this.mapper);
  @override
  final List<String> plan;
  final T Function(Row) mapper;
  @override
  T decode(Row row) => mapper(row);
}

extension PairProjection<A, B> on (Selection<A>, Selection<B>) {
  Selection<R> map<R>(R Function(A, B) mapper) => Mapped([
    ...$1.plan,
    ...$2.plan,
  ], (row) => mapper($1.decode(row), $2.decode(row)));
}

extension TripleProjection<A, B, C>
    on (Selection<A>, Selection<B>, Selection<C>) {
  Selection<R> map<R>(R Function(A, B, C) mapper) => Mapped([
    ...$1.plan,
    ...$2.plan,
    ...$3.plan,
  ], (row) => mapper($1.decode(row), $2.decode(row), $3.decode(row)));
}

Selection<T?> optional<T>(String presence, Selection<T> item) => Mapped([
  presence,
  ...item.plan,
], (row) => row[presence] == null ? null : item.decode(row));

Selection<List<T>> many<T>(String key, Selection<T> item) => Mapped(
  ['$key[${item.plan.join(',')}]'],
  (row) => switch (row[key]) {
    final List<Row> rows => rows.map(item.decode).toList(),
    _ => throw FormatException('Expected nested rows at $key'),
  },
);

int integer(Object? value) => switch (value) {
  final int result => result,
  _ => throw const FormatException('Expected integer'),
};
String string(Object? value) => switch (value) {
  final String result => result,
  _ => throw const FormatException('Expected text'),
};

final class Users {
  final id = const Expr('user.id', integer);
  final email = const Expr('user.email', string);
}

final class Posts {
  final id = const Expr('post.id', integer);
  final title = const Expr('post.title', string);
}

final class Card {
  const Card(this.id, this.email);
  final int id;
  final String email;
}

Selection<R> select<R>(Selection<R> Function(Users) build) => build(Users());

R rowReader<R>(Users u, Row row, R Function(Users, Read) mapper) {
  T read<T>(Expr<T> expression) => expression.decode(row);
  return mapper(u, read);
}

void verifySelections() {
  final u = Users();
  final p = Posts();
  var mapperCalls = 0;
  final named = select(
    (u) => (u.id, u.email).map((id, email) {
      mapperCalls++;
      return (identifier: id, contact: email);
    }),
  );
  assert(mapperCalls == 0); // Plan collection never executes a row callback.
  final Selection<({int identifier, String contact})> checkedNamed = named;
  final row = <String, Object?>{'user.id': 1, 'user.email': 'a@example.com'};
  final decoded = checkedNamed.decode(row);
  assert(mapperCalls == 1 && decoded.identifier == 1);
  assert(named.plan.join(',') == 'user.id,user.email');

  final Selection<int> scalar = select((u) => u.id);
  assert(scalar.decode(row) == 1);
  final Selection<Card> dto = select((u) => (u.id, u.email).map(Card.new));
  assert(dto.decode(row).email == 'a@example.com');

  final author = optional('user.id', (u.id, u.email).map(Card.new));
  final Selection<Card?> checkedAuthor = author;
  assert(checkedAuthor.decode({'user.id': null, 'user.email': null}) == null);
  assert(checkedAuthor.decode(row)?.id == 1);

  final titles = many('posts', p.title);
  final authors = many('friends', (u.id, u.email).map(Card.new));
  final graph = (
    u.id,
    titles,
    authors,
  ).map((id, titles, friends) => (id: id, titles: titles, friends: friends));
  final Selection<({int id, List<String> titles, List<Card> friends})>
  checkedGraph = graph;
  final decodedGraph = checkedGraph.decode({
    ...row,
    'posts': <Row>[
      {'post.title': 'Hello'},
    ],
    'friends': <Row>[
      {'user.id': 2, 'user.email': 'b@example.com'},
    ],
  });
  assert(decodedGraph.titles.single == 'Hello');
  assert(decodedGraph.friends.single.id == 2);

  // Reader callback independently proves named Record inference, only for decode.
  final readRecord = rowReader(
    u,
    row,
    (u, read) => (account: read(u.id), address: read(u.email)),
  );
  final ({int account, String address}) checkedReadRecord = readRecord;
  assert(checkedReadRecord.account == 1);

  // Counterexample: placeholder discovery misses conditionally accessed columns.
  final selected = <String>[];
  T fakeRead<T>(Expr<T> expression) {
    selected.add(expression.name);
    return expression.codec(switch (expression.name) {
      'user.id' => 0,
      'user.email' => '',
      _ => throw StateError('No valid dummy value'),
    });
  }

  String conditional(Read read) => read(u.id) > 0 ? read(u.email) : 'hidden';
  conditional(fakeRead);
  assert(!selected.contains('user.email'));
  assert(rowReader(u, row, (_, read) => conditional(read)) == 'a@example.com');
  print(
    'PASS: arbitrary named record, single scalar, DTO constructor tear-off,',
  );
  print('optional whole object, heterogeneous nested relation selections,');
  print('generic reader callback inference, and dummy-reader counterexample.');
  print('Record plan: ${named.plan}');
  print('Nested plan (structural labels, not SQL): ${graph.plan}');
  print('Dummy reader discovered only: $selected');
}

// Language feasibility only. No database driver is implemented here.
sealed class Backend {}

final class Pg extends Backend {}

final class Sqlite extends Backend {}

enum TlsMode { verifyFull, disable }

enum Journal { wal, rollback }

final class PgOptions({
  required final Uri url,
  final TlsMode tls = .verifyFull,
  final int maxConnections = 8,
});

final class SqliteOptions.file(
  final String path, {
  final Journal journal = .wal,
});

abstract interface class Driver<B extends Backend> {
  String get description;
}

final class PgDriver(final PgOptions options) implements Driver<Pg> {
  @override
  String get description => 'postgres';
}

final class SqliteDriver(final SqliteOptions options)
    implements Driver<Sqlite> {
  @override
  String get description => 'sqlite';
}

final class AppDatabase<B extends Backend> {
  AppDatabase._(this.driver);
  final Driver<B> driver;

  static Future<AppDatabase<T>> open<T extends Backend>(
    Driver<T> driver,
  ) async {
    return AppDatabase<T>._(driver);
  }
}

extension PgFeatures on AppDatabase<Pg> {
  String get advisoryLockFeature => 'pg_advisory_xact_lock';
}

Future<void> verifyDrivers() async {
  final pg = await AppDatabase.open(
    PgDriver(.new(url: Uri.parse('postgresql://localhost/example'))),
  );
  final sqlite = await AppDatabase.open(
    SqliteDriver(.file('/tmp/example.sqlite')),
  );
  AppDatabase<Pg> typedPg = pg;
  AppDatabase<Sqlite> typedSqlite = sqlite;
  assert(typedPg.advisoryLockFeature == 'pg_advisory_xact_lock');
  assert(typedSqlite.driver.description == 'sqlite');
  print('PASS: typed driver options and backend-specific extension');
}

// Schema and patch language probes. No schema extraction is implemented.
final class Id {
  const Id.generated();
}

final class Unique {
  const Unique();
}

typedef User = ({
  @Id.generated() int id,
  @Unique() String email,
  String? nickname,
});
typedef OtherRow = ({int id, String email, String? nickname});

sealed class Change<T> {
  const Change();
  const factory Change.keep() = Keep<T>;
  const factory Change.set(T value) = SetValue<T>;
}

final class Keep<T> extends Change<T> {
  const Keep();
}

final class SetValue<T> extends Change<T> {
  const SetValue(this.value);
  final T value;
}

String describeChange(Change<String?> change) => switch (change) {
  Keep() => 'keep',
  SetValue(:final value) => 'set:$value',
};

final class Entity<M> {
  const Entity(this.name);
  final String name;
  EntityKey<M, K> key<K>(K Function(M) selector) => EntityKey(this, selector);
}

final class EntityKey<M, K> {
  const EntityKey(this.entity, this.selector);
  final Entity<M> entity;
  final K Function(M) selector;
  String references<N>(EntityKey<N, K> target) =>
      '${entity.name}->${target.entity.name}';
}

void verifyDeclarations() {
  final OtherRow other = (id: 1, email: 'a@example.com', nickname: null);
  final User sameShape = other; // Aliases do not create entity identity.
  final users = Entity<User>('users');
  final others = Entity<OtherRow>('others');
  assert(!identical(users, others));
  assert(sameShape.email == 'a@example.com');
  assert(describeChange(.keep()) == 'keep');
  assert(describeChange(.set(null)) == 'set:null');
  assert(describeChange(.set('seven')) == 'set:seven');
  final link = users
      .key((u) => (u.id, u.email))
      .references(others.key((u) => (u.id, u.email)));
  assert(link == 'users->others');
  print(
    'PASS: record metadata, structural identity, typed keys and tri-state patch',
  );
}

Future<void> main() async {
  verifySelections();
  verifyDeclarations();
  await verifyDrivers();
}
