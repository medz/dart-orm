// GENERATED CODE - DO NOT MODIFY BY HAND.
// Regenerate with dart run bin/orm.dart generate.
import 'dart:typed_data';

import 'package:orm/database.dart';
import 'package:orm/migration.dart' show freezeSnapshot;
import 'package:orm/query.dart';
import 'package:orm/schema.dart';

import "models.dart"
    as models
    show
        User,
        Post,
        Product,
        Order,
        OrderLine,
        UserCard,
        UserProfile,
        PostCard,
        ProductCard;

const _absent = Object();
bool _provided(Object? value) => !identical(value, _absent);
num _number(Object? value) => value as num;

Database _openDatabase(Driver driver, {DatabaseObserver? onEvent}) {
  freezeSnapshot(
    SchemaSnapshot(
      engine: driver.engine,
      tables: const [
        _usersDefinition,
        _postsDefinition,
        _productsDefinition,
        _ordersDefinition,
        _orderLinesDefinition,
      ],
    ),
  );
  return openDatabase(driver, observer: onEvent);
}

/// Owns the supplied driver. Close it after completing all database work.
///
/// Validates every model against the driver's engine before taking ownership.
/// If construction fails, the caller retains the driver; no SQL is executed.
final class AppDatabase {
  AppDatabase(Driver driver, {DatabaseObserver? onEvent})
    : _database = _openDatabase(driver, onEvent: onEvent);
  final Database _database;

  /// The owned runtime for migrations and raw database operations.
  ///
  /// This shares the supplied driver and lifecycle with the generated client.
  /// Close the generated client after all work; do not wrap its driver again.
  Database get database => _database;

  /// Raw execution and generated tables in the database's root scope.
  late final AppSession session = AppSession._(_database.session);

  /// Typed access to users.
  UserTable get users => session.users;

  /// Typed access to posts.
  PostTable get posts => session.posts;

  /// Typed access to products.
  ProductTable get products => session.products;

  /// Typed access to orders.
  OrderTable get orders => session.orders;

  /// Typed access to order_lines.
  OrderLineTable get orderLines => session.orderLines;

  /// Commits successful work and rolls back callback or SQL failures.
  ///
  /// A caught SQL failure still rolls back. The callback scope expires on return.
  Future<T> transaction<T>(
    Future<T> Function(AppSession session) action, {
    Isolation isolation = Isolation.serializable,
    bool readOnly = false,
  }) => _database.transaction(
    (session) => action(AppSession._(session)),
    isolation: isolation,
    readOnly: readOnly,
  );

  /// Waits for active work and releases the owned driver.
  Future<void> close() => _database.close();
}

/// Generated tables share one explicit raw execution scope.
final class AppSession implements Session {
  AppSession._(this._session);
  final Session _session;

  /// Typed access to users in this scope.
  late final UserTable users = UserTable._(
    TableQuery<models.User>(_session, _usersDefinition, _decodeUser),
  );

  /// Typed access to posts in this scope.
  late final PostTable posts = PostTable._(
    TableQuery<models.Post>(_session, _postsDefinition, _decodePost),
  );

  /// Typed access to products in this scope.
  late final ProductTable products = ProductTable._(
    TableQuery<models.Product>(_session, _productsDefinition, _decodeProduct),
  );

  /// Typed access to orders in this scope.
  late final OrderTable orders = OrderTable._(
    TableQuery<models.Order>(_session, _ordersDefinition, _decodeOrder),
  );

  /// Typed access to order_lines in this scope.
  late final OrderLineTable orderLines = OrderLineTable._(
    TableQuery<models.OrderLine>(
      _session,
      _orderLinesDefinition,
      _decodeOrderLine,
    ),
  );
  @override
  Engine get engine => _session.engine;
  @override
  String get schema => _session.schema;
  @override
  Capabilities get capabilities => _session.capabilities;
  @override
  bool get inTransaction => _session.inTransaction;
  @override
  Future<QueryResult> run(String sql, {List<Object?> parameters = const []}) =>
      _session.run(sql, parameters: parameters);
}

const _usersDefinition = TableDefinition("users", [
  ColumnDefinition(
    name: "id",
    field: "id",
    type: ScalarType.integer,
    nullable: false,
    primaryKey: true,
    identity: true,
    unique: false,
  ),
  ColumnDefinition(
    name: "username",
    field: "username",
    type: ScalarType.text,
    nullable: false,
    primaryKey: false,
    identity: false,
    unique: true,
  ),
  ColumnDefinition(
    name: "age",
    field: "age",
    type: ScalarType.integer,
    nullable: false,
    primaryKey: false,
    identity: false,
    unique: false,
  ),
  ColumnDefinition(
    name: "nickname",
    field: "nickname",
    type: ScalarType.text,
    nullable: true,
    primaryKey: false,
    identity: false,
    unique: false,
  ),
  ColumnDefinition(
    name: "active",
    field: "active",
    type: ScalarType.boolean,
    nullable: false,
    primaryKey: false,
    identity: false,
    unique: false,
    defaultValue: true,
  ),
  ColumnDefinition(
    name: "score",
    field: "score",
    type: ScalarType.real,
    nullable: false,
    primaryKey: false,
    identity: false,
    unique: false,
    defaultValue: 0.0,
  ),
  ColumnDefinition(
    name: "joined_at",
    field: "joinedAt",
    type: ScalarType.dateTime,
    nullable: true,
    primaryKey: false,
    identity: false,
    unique: false,
  ),
  ColumnDefinition(
    name: "avatar",
    field: "avatar",
    type: ScalarType.bytes,
    nullable: true,
    primaryKey: false,
    identity: false,
    unique: false,
  ),
]);
models.User _decodeUser(List<Object?> row) => models.User(
  id: decodeValue<int>(row[0]),
  username: decodeValue<String>(row[1]),
  age: decodeValue<int>(row[2]),
  nickname: row[3] == null ? null : decodeValue<String>(row[3]),
  active: decodeValue<bool>(row[4]),
  score: decodeValue<double>(row[5]),
  joinedAt: row[6] == null ? null : decodeValue<DateTime>(row[6]),
  avatar: row[7] == null ? null : decodeValue<Uint8List>(row[7]),
);

/// An immutable query over the users table.
final class UserTable {
  UserTable._(this._query);
  final TableQuery<models.User> _query;

  /// Creates one row. Omitted fields use database defaults; null is retained.
  ///
  /// Requires an unfiltered, unordered query without pagination. SQL errors
  /// propagate and roll back an enclosing explicit transaction.
  UserCreate get create => _UserCreate(_query);

  /// Creates one row, or returns null on a conflict with the selected unique field.
  ///
  /// The conflict value must be supplied and non-null. Other constraint errors
  /// propagate. Query filters, ordering and pagination are rejected.
  UserCreateIfAbsent get createIfAbsent => _UserCreateIfAbsent(_query);

  /// Updates supplied fields by primary key and the current where scope.
  ///
  /// Omitted fields are unchanged. Returns null when the key and where scope do
  /// not match. Empty updates, ordering and pagination fail before SQL.
  UserUpdate get update => _UserUpdate(_query);

  /// Fetches a row by its primary key.
  Future<models.User?> get(int id) => _query.get(id);

  /// Deletes a row by primary key and returns its affected row count.
  Future<int> delete(int id) => _query.deleteById(id);

  /// Fetches all matching full model rows.
  Future<List<models.User>> all() => _query.all();

  /// Counts rows in this scope, including limit and offset, in one SELECT.
  /// Count the unpaged filter scope to get a total before pagination.
  Future<int> count() => _query.count();

  /// Reads bounded batches within an active transaction scope.
  Stream<models.User> stream({int fetchSize = 500}) =>
      _query.stream(fetchSize: fetchSize);

  /// Adds field predicates joined by AND.
  UserTable where({
    Filter<int>? id,
    Filter<String>? username,
    Filter<int>? age,
    Filter<String?>? nickname,
    Filter<bool>? active,
    Filter<double>? score,
    Filter<DateTime?>? joinedAt,
    Filter<Uint8List?>? avatar,
  }) => UserTable._(
    _query.whereFields({
      "id": ?id,
      "username": ?username,
      "age": ?age,
      "nickname": ?nickname,
      "active": ?active,
      "score": ?score,
      "joinedAt": ?joinedAt,
      "avatar": ?avatar,
    }),
  );

  /// Adds field predicates joined by OR, combined with earlier filters by AND.
  /// An empty group fails before SQL. Field types and nullability are retained.
  UserTable whereAny({
    Filter<int>? id,
    Filter<String>? username,
    Filter<int>? age,
    Filter<String?>? nickname,
    Filter<bool>? active,
    Filter<double>? score,
    Filter<DateTime?>? joinedAt,
    Filter<Uint8List?>? avatar,
  }) => UserTable._(
    _query.whereAnyFields({
      "id": ?id,
      "username": ?username,
      "age": ?age,
      "nickname": ?nickname,
      "active": ?active,
      "score": ?score,
      "joinedAt": ?joinedAt,
      "avatar": ?avatar,
    }),
  );

  /// Adds one ordering field. Chain calls for multiple ordering fields.
  UserTable orderBy({
    Direction? id,
    Direction? username,
    Direction? age,
    Direction? nickname,
    Direction? active,
    Direction? score,
    Direction? joinedAt,
    Direction? avatar,
  }) => UserTable._(
    _query.orderByFields({
      "id": ?id,
      "username": ?username,
      "age": ?age,
      "nickname": ?nickname,
      "active": ?active,
      "score": ?score,
      "joinedAt": ?joinedAt,
      "avatar": ?avatar,
    }),
  );

  /// Limits result rows; negative limits fail before SQL execution.
  UserTable limit(int count) => UserTable._(_query.limit(count));

  /// Skips result rows; negative offsets fail before SQL execution.
  UserTable offset(int count) => UserTable._(_query.offset(count));

  /// Executes a statically registered selection; unknown types fail before SQL.
  Future<List<T>> select<T>() {
    if (T == models.User) {
      return _query.all().then((rows) => rows.cast<T>());
    }

    if (T == models.UserCard) {
      return _query
          .selectRows<models.UserCard>(
            ["id", "username"],
            (row) => (
              id: decodeValue<int>(row[0]),
              username: decodeValue<String>(row[1]),
            ),
          )
          .then((rows) => rows.cast<T>());
    }

    if (T == models.UserProfile) {
      return _query
          .selectRows<models.UserProfile>(
            ["active", "id", "nickname"],
            (row) => (
              active: decodeValue<bool>(row[0]),
              id: decodeValue<int>(row[1]),
              nickname: row[2] == null ? null : decodeValue<String>(row[2]),
            ),
          )
          .then((rows) => rows.cast<T>());
    }

    throw ArgumentError(
      'Unregistered selection type $T for '
      "users.",
    );
  }

  /// Atomically increment supplied fields by key, retaining the where scope.
  UserIncrement get increment => _UserIncrement(_query);

  /// Atomically decrement supplied fields by key, retaining the where scope.
  UserDecrement get decrement => _UserDecrement(_query);
}

/// Typed creation arguments for users.
abstract interface class UserCreate {
  /// Returns the single inserted row; SQL failures propagate.
  Future<models.User> call({
    required String username,
    required int age,
    String? nickname,
    bool active,
    double score,
    DateTime? joinedAt,
    Uint8List? avatar,
  });
}

final class _UserCreate implements UserCreate {
  _UserCreate(this._query);
  final TableQuery<models.User> _query;
  @override
  Future<models.User> call({
    Object? username = _absent,
    Object? age = _absent,
    Object? nickname = _absent,
    Object? active = _absent,
    Object? score = _absent,
    Object? joinedAt = _absent,
    Object? avatar = _absent,
  }) => _query.insert({
    if (_provided(username)) "username": username,
    if (_provided(age)) "age": age,
    if (_provided(nickname)) "nickname": nickname,
    if (_provided(active)) "active": active,
    if (_provided(score)) "score": score,
    if (_provided(joinedAt)) "joinedAt": joinedAt,
    if (_provided(avatar)) "avatar": avatar,
  });
}

/// Typed partial update arguments for users.
abstract interface class UserUpdate {
  /// Returns the updated row, or null when key and where scope do not match.
  Future<models.User?> call(
    int key, {
    String username,
    int age,
    String? nickname,
    bool active,
    double score,
    DateTime? joinedAt,
    Uint8List? avatar,
  });
}

final class _UserUpdate implements UserUpdate {
  _UserUpdate(this._query);
  final TableQuery<models.User> _query;
  @override
  Future<models.User?> call(
    int key, {
    Object? username = _absent,
    Object? age = _absent,
    Object? nickname = _absent,
    Object? active = _absent,
    Object? score = _absent,
    Object? joinedAt = _absent,
    Object? avatar = _absent,
  }) => _query.updateById(key, {
    if (_provided(username)) "username": username,
    if (_provided(age)) "age": age,
    if (_provided(nickname)) "nickname": nickname,
    if (_provided(active)) "active": active,
    if (_provided(score)) "score": score,
    if (_provided(joinedAt)) "joinedAt": joinedAt,
    if (_provided(avatar)) "avatar": avatar,
  });
}

/// Single-column unique constraints that can prevent creation of users.
final class UserUnique {
  const UserUnique._(this._field);
  final String _field;

  /// Conflict target: username.
  static const username = UserUnique._("username");
}

/// Typed creation arguments with an explicit unique conflict target.
abstract interface class UserCreateIfAbsent {
  /// Returns the inserted row, or null for a conflict with the selected target.
  /// The target value must be supplied and non-null; other SQL failures propagate.
  Future<models.User?> call(
    UserUnique target, {
    required String username,
    required int age,
    String? nickname,
    bool active,
    double score,
    DateTime? joinedAt,
    Uint8List? avatar,
  });
}

final class _UserCreateIfAbsent implements UserCreateIfAbsent {
  _UserCreateIfAbsent(this._query);
  final TableQuery<models.User> _query;
  @override
  Future<models.User?> call(
    UserUnique target, {
    Object? username = _absent,
    Object? age = _absent,
    Object? nickname = _absent,
    Object? active = _absent,
    Object? score = _absent,
    Object? joinedAt = _absent,
    Object? avatar = _absent,
  }) => _query.insertIfAbsent({
    if (_provided(username)) "username": username,
    if (_provided(age)) "age": age,
    if (_provided(nickname)) "nickname": nickname,
    if (_provided(active)) "active": active,
    if (_provided(score)) "score": score,
    if (_provided(joinedAt)) "joinedAt": joinedAt,
    if (_provided(avatar)) "avatar": avatar,
  }, conflictField: target._field);
}

/// Typed atomic arithmetic arguments for users.
abstract interface class UserIncrement {
  /// Returns the changed row, or null when the key, filters or integer bounds
  /// do not match. Integer arithmetic stays within signed 64-bit bounds.
  /// SQLite REAL bounds also return null; PostgreSQL REAL overflow is a SQL error.
  Future<models.User?> call(int key, {int age, double score});
}

final class _UserIncrement implements UserIncrement {
  _UserIncrement(this._query);
  final TableQuery<models.User> _query;
  @override
  Future<models.User?> call(
    int key, {
    Object? age = _absent,
    Object? score = _absent,
  }) => _query.incrementById(key, {
    if (_provided(age)) "age": _number(age),
    if (_provided(score)) "score": _number(score),
  });
}

/// Typed atomic arithmetic arguments for users.
abstract interface class UserDecrement {
  /// Returns the changed row, or null when the key, filters or integer bounds
  /// do not match. Integer arithmetic stays within signed 64-bit bounds.
  /// SQLite REAL bounds also return null; PostgreSQL REAL overflow is a SQL error.
  Future<models.User?> call(int key, {int age, double score});
}

final class _UserDecrement implements UserDecrement {
  _UserDecrement(this._query);
  final TableQuery<models.User> _query;
  @override
  Future<models.User?> call(
    int key, {
    Object? age = _absent,
    Object? score = _absent,
  }) => _query.decrementById(key, {
    if (_provided(age)) "age": _number(age),
    if (_provided(score)) "score": _number(score),
  });
}

const _postsDefinition = TableDefinition("posts", [
  ColumnDefinition(
    name: "id",
    field: "id",
    type: ScalarType.integer,
    nullable: false,
    primaryKey: true,
    identity: true,
    unique: false,
  ),
  ColumnDefinition(
    name: "author_id",
    field: "authorId",
    type: ScalarType.integer,
    nullable: false,
    primaryKey: false,
    identity: false,
    unique: false,
    references: ForeignKey("users", "id", onDelete: "cascade"),
  ),
  ColumnDefinition(
    name: "title",
    field: "title",
    type: ScalarType.text,
    nullable: false,
    primaryKey: false,
    identity: false,
    unique: false,
  ),
  ColumnDefinition(
    name: "body",
    field: "body",
    type: ScalarType.text,
    nullable: true,
    primaryKey: false,
    identity: false,
    unique: false,
  ),
]);
models.Post _decodePost(List<Object?> row) => models.Post(
  id: decodeValue<int>(row[0]),
  authorId: decodeValue<int>(row[1]),
  title: decodeValue<String>(row[2]),
  body: row[3] == null ? null : decodeValue<String>(row[3]),
);

/// An immutable query over the posts table.
final class PostTable {
  PostTable._(this._query);
  final TableQuery<models.Post> _query;

  /// Creates one row. Omitted fields use database defaults; null is retained.
  ///
  /// Requires an unfiltered, unordered query without pagination. SQL errors
  /// propagate and roll back an enclosing explicit transaction.
  PostCreate get create => _PostCreate(_query);

  /// Updates supplied fields by primary key and the current where scope.
  ///
  /// Omitted fields are unchanged. Returns null when the key and where scope do
  /// not match. Empty updates, ordering and pagination fail before SQL.
  PostUpdate get update => _PostUpdate(_query);

  /// Fetches a row by its primary key.
  Future<models.Post?> get(int id) => _query.get(id);

  /// Deletes a row by primary key and returns its affected row count.
  Future<int> delete(int id) => _query.deleteById(id);

  /// Fetches all matching full model rows.
  Future<List<models.Post>> all() => _query.all();

  /// Counts rows in this scope, including limit and offset, in one SELECT.
  /// Count the unpaged filter scope to get a total before pagination.
  Future<int> count() => _query.count();

  /// Reads bounded batches within an active transaction scope.
  Stream<models.Post> stream({int fetchSize = 500}) =>
      _query.stream(fetchSize: fetchSize);

  /// Adds field predicates joined by AND.
  PostTable where({
    Filter<int>? id,
    Filter<int>? authorId,
    Filter<String>? title,
    Filter<String?>? body,
  }) => PostTable._(
    _query.whereFields({
      "id": ?id,
      "authorId": ?authorId,
      "title": ?title,
      "body": ?body,
    }),
  );

  /// Adds field predicates joined by OR, combined with earlier filters by AND.
  /// An empty group fails before SQL. Field types and nullability are retained.
  PostTable whereAny({
    Filter<int>? id,
    Filter<int>? authorId,
    Filter<String>? title,
    Filter<String?>? body,
  }) => PostTable._(
    _query.whereAnyFields({
      "id": ?id,
      "authorId": ?authorId,
      "title": ?title,
      "body": ?body,
    }),
  );

  /// Adds one ordering field. Chain calls for multiple ordering fields.
  PostTable orderBy({
    Direction? id,
    Direction? authorId,
    Direction? title,
    Direction? body,
  }) => PostTable._(
    _query.orderByFields({
      "id": ?id,
      "authorId": ?authorId,
      "title": ?title,
      "body": ?body,
    }),
  );

  /// Limits result rows; negative limits fail before SQL execution.
  PostTable limit(int count) => PostTable._(_query.limit(count));

  /// Skips result rows; negative offsets fail before SQL execution.
  PostTable offset(int count) => PostTable._(_query.offset(count));

  /// Executes a statically registered selection; unknown types fail before SQL.
  Future<List<T>> select<T>() {
    if (T == models.Post) {
      return _query.all().then((rows) => rows.cast<T>());
    }

    if (T == models.PostCard) {
      return _query
          .selectRows<models.PostCard>(
            ["authorId", "id", "title"],
            (row) => (
              authorId: decodeValue<int>(row[0]),
              id: decodeValue<int>(row[1]),
              title: decodeValue<String>(row[2]),
            ),
          )
          .then((rows) => rows.cast<T>());
    }

    throw ArgumentError(
      'Unregistered selection type $T for '
      "posts.",
    );
  }
}

/// Typed creation arguments for posts.
abstract interface class PostCreate {
  /// Returns the single inserted row; SQL failures propagate.
  Future<models.Post> call({
    required int authorId,
    required String title,
    String? body,
  });
}

final class _PostCreate implements PostCreate {
  _PostCreate(this._query);
  final TableQuery<models.Post> _query;
  @override
  Future<models.Post> call({
    Object? authorId = _absent,
    Object? title = _absent,
    Object? body = _absent,
  }) => _query.insert({
    if (_provided(authorId)) "authorId": authorId,
    if (_provided(title)) "title": title,
    if (_provided(body)) "body": body,
  });
}

/// Typed partial update arguments for posts.
abstract interface class PostUpdate {
  /// Returns the updated row, or null when key and where scope do not match.
  Future<models.Post?> call(
    int key, {
    int authorId,
    String title,
    String? body,
  });
}

final class _PostUpdate implements PostUpdate {
  _PostUpdate(this._query);
  final TableQuery<models.Post> _query;
  @override
  Future<models.Post?> call(
    int key, {
    Object? authorId = _absent,
    Object? title = _absent,
    Object? body = _absent,
  }) => _query.updateById(key, {
    if (_provided(authorId)) "authorId": authorId,
    if (_provided(title)) "title": title,
    if (_provided(body)) "body": body,
  });
}

const _productsDefinition = TableDefinition("products", [
  ColumnDefinition(
    name: "id",
    field: "id",
    type: ScalarType.integer,
    nullable: false,
    primaryKey: true,
    identity: true,
    unique: false,
  ),
  ColumnDefinition(
    name: "sku",
    field: "sku",
    type: ScalarType.text,
    nullable: false,
    primaryKey: false,
    identity: false,
    unique: true,
  ),
  ColumnDefinition(
    name: "name",
    field: "name",
    type: ScalarType.text,
    nullable: false,
    primaryKey: false,
    identity: false,
    unique: false,
  ),
  ColumnDefinition(
    name: "price_cents",
    field: "priceCents",
    type: ScalarType.integer,
    nullable: false,
    primaryKey: false,
    identity: false,
    unique: false,
  ),
  ColumnDefinition(
    name: "stock",
    field: "stock",
    type: ScalarType.integer,
    nullable: false,
    primaryKey: false,
    identity: false,
    unique: false,
    defaultValue: 0,
  ),
]);
models.Product _decodeProduct(List<Object?> row) => models.Product(
  id: decodeValue<int>(row[0]),
  sku: decodeValue<String>(row[1]),
  name: decodeValue<String>(row[2]),
  priceCents: decodeValue<int>(row[3]),
  stock: decodeValue<int>(row[4]),
);

/// An immutable query over the products table.
final class ProductTable {
  ProductTable._(this._query);
  final TableQuery<models.Product> _query;

  /// Creates one row. Omitted fields use database defaults; null is retained.
  ///
  /// Requires an unfiltered, unordered query without pagination. SQL errors
  /// propagate and roll back an enclosing explicit transaction.
  ProductCreate get create => _ProductCreate(_query);

  /// Creates one row, or returns null on a conflict with the selected unique field.
  ///
  /// The conflict value must be supplied and non-null. Other constraint errors
  /// propagate. Query filters, ordering and pagination are rejected.
  ProductCreateIfAbsent get createIfAbsent => _ProductCreateIfAbsent(_query);

  /// Updates supplied fields by primary key and the current where scope.
  ///
  /// Omitted fields are unchanged. Returns null when the key and where scope do
  /// not match. Empty updates, ordering and pagination fail before SQL.
  ProductUpdate get update => _ProductUpdate(_query);

  /// Fetches a row by its primary key.
  Future<models.Product?> get(int id) => _query.get(id);

  /// Deletes a row by primary key and returns its affected row count.
  Future<int> delete(int id) => _query.deleteById(id);

  /// Fetches all matching full model rows.
  Future<List<models.Product>> all() => _query.all();

  /// Counts rows in this scope, including limit and offset, in one SELECT.
  /// Count the unpaged filter scope to get a total before pagination.
  Future<int> count() => _query.count();

  /// Reads bounded batches within an active transaction scope.
  Stream<models.Product> stream({int fetchSize = 500}) =>
      _query.stream(fetchSize: fetchSize);

  /// Adds field predicates joined by AND.
  ProductTable where({
    Filter<int>? id,
    Filter<String>? sku,
    Filter<String>? name,
    Filter<int>? priceCents,
    Filter<int>? stock,
  }) => ProductTable._(
    _query.whereFields({
      "id": ?id,
      "sku": ?sku,
      "name": ?name,
      "priceCents": ?priceCents,
      "stock": ?stock,
    }),
  );

  /// Adds field predicates joined by OR, combined with earlier filters by AND.
  /// An empty group fails before SQL. Field types and nullability are retained.
  ProductTable whereAny({
    Filter<int>? id,
    Filter<String>? sku,
    Filter<String>? name,
    Filter<int>? priceCents,
    Filter<int>? stock,
  }) => ProductTable._(
    _query.whereAnyFields({
      "id": ?id,
      "sku": ?sku,
      "name": ?name,
      "priceCents": ?priceCents,
      "stock": ?stock,
    }),
  );

  /// Adds one ordering field. Chain calls for multiple ordering fields.
  ProductTable orderBy({
    Direction? id,
    Direction? sku,
    Direction? name,
    Direction? priceCents,
    Direction? stock,
  }) => ProductTable._(
    _query.orderByFields({
      "id": ?id,
      "sku": ?sku,
      "name": ?name,
      "priceCents": ?priceCents,
      "stock": ?stock,
    }),
  );

  /// Limits result rows; negative limits fail before SQL execution.
  ProductTable limit(int count) => ProductTable._(_query.limit(count));

  /// Skips result rows; negative offsets fail before SQL execution.
  ProductTable offset(int count) => ProductTable._(_query.offset(count));

  /// Executes a statically registered selection; unknown types fail before SQL.
  Future<List<T>> select<T>() {
    if (T == models.Product) {
      return _query.all().then((rows) => rows.cast<T>());
    }

    if (T == models.ProductCard) {
      return _query
          .selectRows<models.ProductCard>(
            ["id", "name", "priceCents"],
            (row) => (
              id: decodeValue<int>(row[0]),
              name: decodeValue<String>(row[1]),
              priceCents: decodeValue<int>(row[2]),
            ),
          )
          .then((rows) => rows.cast<T>());
    }

    throw ArgumentError(
      'Unregistered selection type $T for '
      "products.",
    );
  }

  /// Atomically increment supplied fields by key, retaining the where scope.
  ProductIncrement get increment => _ProductIncrement(_query);

  /// Atomically decrement supplied fields by key, retaining the where scope.
  ProductDecrement get decrement => _ProductDecrement(_query);
}

/// Typed creation arguments for products.
abstract interface class ProductCreate {
  /// Returns the single inserted row; SQL failures propagate.
  Future<models.Product> call({
    required String sku,
    required String name,
    required int priceCents,
    int stock,
  });
}

final class _ProductCreate implements ProductCreate {
  _ProductCreate(this._query);
  final TableQuery<models.Product> _query;
  @override
  Future<models.Product> call({
    Object? sku = _absent,
    Object? name = _absent,
    Object? priceCents = _absent,
    Object? stock = _absent,
  }) => _query.insert({
    if (_provided(sku)) "sku": sku,
    if (_provided(name)) "name": name,
    if (_provided(priceCents)) "priceCents": priceCents,
    if (_provided(stock)) "stock": stock,
  });
}

/// Typed partial update arguments for products.
abstract interface class ProductUpdate {
  /// Returns the updated row, or null when key and where scope do not match.
  Future<models.Product?> call(
    int key, {
    String sku,
    String name,
    int priceCents,
    int stock,
  });
}

final class _ProductUpdate implements ProductUpdate {
  _ProductUpdate(this._query);
  final TableQuery<models.Product> _query;
  @override
  Future<models.Product?> call(
    int key, {
    Object? sku = _absent,
    Object? name = _absent,
    Object? priceCents = _absent,
    Object? stock = _absent,
  }) => _query.updateById(key, {
    if (_provided(sku)) "sku": sku,
    if (_provided(name)) "name": name,
    if (_provided(priceCents)) "priceCents": priceCents,
    if (_provided(stock)) "stock": stock,
  });
}

/// Single-column unique constraints that can prevent creation of products.
final class ProductUnique {
  const ProductUnique._(this._field);
  final String _field;

  /// Conflict target: sku.
  static const sku = ProductUnique._("sku");
}

/// Typed creation arguments with an explicit unique conflict target.
abstract interface class ProductCreateIfAbsent {
  /// Returns the inserted row, or null for a conflict with the selected target.
  /// The target value must be supplied and non-null; other SQL failures propagate.
  Future<models.Product?> call(
    ProductUnique target, {
    required String sku,
    required String name,
    required int priceCents,
    int stock,
  });
}

final class _ProductCreateIfAbsent implements ProductCreateIfAbsent {
  _ProductCreateIfAbsent(this._query);
  final TableQuery<models.Product> _query;
  @override
  Future<models.Product?> call(
    ProductUnique target, {
    Object? sku = _absent,
    Object? name = _absent,
    Object? priceCents = _absent,
    Object? stock = _absent,
  }) => _query.insertIfAbsent({
    if (_provided(sku)) "sku": sku,
    if (_provided(name)) "name": name,
    if (_provided(priceCents)) "priceCents": priceCents,
    if (_provided(stock)) "stock": stock,
  }, conflictField: target._field);
}

/// Typed atomic arithmetic arguments for products.
abstract interface class ProductIncrement {
  /// Returns the changed row, or null when the key, filters or integer bounds
  /// do not match. Integer arithmetic stays within signed 64-bit bounds.
  /// SQLite REAL bounds also return null; PostgreSQL REAL overflow is a SQL error.
  Future<models.Product?> call(int key, {int priceCents, int stock});
}

final class _ProductIncrement implements ProductIncrement {
  _ProductIncrement(this._query);
  final TableQuery<models.Product> _query;
  @override
  Future<models.Product?> call(
    int key, {
    Object? priceCents = _absent,
    Object? stock = _absent,
  }) => _query.incrementById(key, {
    if (_provided(priceCents)) "priceCents": _number(priceCents),
    if (_provided(stock)) "stock": _number(stock),
  });
}

/// Typed atomic arithmetic arguments for products.
abstract interface class ProductDecrement {
  /// Returns the changed row, or null when the key, filters or integer bounds
  /// do not match. Integer arithmetic stays within signed 64-bit bounds.
  /// SQLite REAL bounds also return null; PostgreSQL REAL overflow is a SQL error.
  Future<models.Product?> call(int key, {int priceCents, int stock});
}

final class _ProductDecrement implements ProductDecrement {
  _ProductDecrement(this._query);
  final TableQuery<models.Product> _query;
  @override
  Future<models.Product?> call(
    int key, {
    Object? priceCents = _absent,
    Object? stock = _absent,
  }) => _query.decrementById(key, {
    if (_provided(priceCents)) "priceCents": _number(priceCents),
    if (_provided(stock)) "stock": _number(stock),
  });
}

const _ordersDefinition = TableDefinition("orders", [
  ColumnDefinition(
    name: "id",
    field: "id",
    type: ScalarType.integer,
    nullable: false,
    primaryKey: true,
    identity: true,
    unique: false,
  ),
  ColumnDefinition(
    name: "user_id",
    field: "userId",
    type: ScalarType.integer,
    nullable: false,
    primaryKey: false,
    identity: false,
    unique: false,
    references: ForeignKey("users", "id", onDelete: "restrict"),
  ),
  ColumnDefinition(
    name: "request_key",
    field: "requestKey",
    type: ScalarType.text,
    nullable: false,
    primaryKey: false,
    identity: false,
    unique: true,
  ),
  ColumnDefinition(
    name: "request_signature",
    field: "requestSignature",
    type: ScalarType.text,
    nullable: false,
    primaryKey: false,
    identity: false,
    unique: false,
  ),
  ColumnDefinition(
    name: "total_cents",
    field: "totalCents",
    type: ScalarType.integer,
    nullable: false,
    primaryKey: false,
    identity: false,
    unique: false,
    defaultValue: 0,
  ),
  ColumnDefinition(
    name: "status",
    field: "status",
    type: ScalarType.text,
    nullable: false,
    primaryKey: false,
    identity: false,
    unique: false,
    defaultValue: "building",
  ),
  ColumnDefinition(
    name: "created_at",
    field: "createdAt",
    type: ScalarType.dateTime,
    nullable: false,
    primaryKey: false,
    identity: false,
    unique: false,
  ),
]);
models.Order _decodeOrder(List<Object?> row) => models.Order(
  id: decodeValue<int>(row[0]),
  userId: decodeValue<int>(row[1]),
  requestKey: decodeValue<String>(row[2]),
  requestSignature: decodeValue<String>(row[3]),
  totalCents: decodeValue<int>(row[4]),
  status: decodeValue<String>(row[5]),
  createdAt: decodeValue<DateTime>(row[6]),
);

/// An immutable query over the orders table.
final class OrderTable {
  OrderTable._(this._query);
  final TableQuery<models.Order> _query;

  /// Creates one row. Omitted fields use database defaults; null is retained.
  ///
  /// Requires an unfiltered, unordered query without pagination. SQL errors
  /// propagate and roll back an enclosing explicit transaction.
  OrderCreate get create => _OrderCreate(_query);

  /// Creates one row, or returns null on a conflict with the selected unique field.
  ///
  /// The conflict value must be supplied and non-null. Other constraint errors
  /// propagate. Query filters, ordering and pagination are rejected.
  OrderCreateIfAbsent get createIfAbsent => _OrderCreateIfAbsent(_query);

  /// Updates supplied fields by primary key and the current where scope.
  ///
  /// Omitted fields are unchanged. Returns null when the key and where scope do
  /// not match. Empty updates, ordering and pagination fail before SQL.
  OrderUpdate get update => _OrderUpdate(_query);

  /// Fetches a row by its primary key.
  Future<models.Order?> get(int id) => _query.get(id);

  /// Deletes a row by primary key and returns its affected row count.
  Future<int> delete(int id) => _query.deleteById(id);

  /// Fetches all matching full model rows.
  Future<List<models.Order>> all() => _query.all();

  /// Counts rows in this scope, including limit and offset, in one SELECT.
  /// Count the unpaged filter scope to get a total before pagination.
  Future<int> count() => _query.count();

  /// Reads bounded batches within an active transaction scope.
  Stream<models.Order> stream({int fetchSize = 500}) =>
      _query.stream(fetchSize: fetchSize);

  /// Adds field predicates joined by AND.
  OrderTable where({
    Filter<int>? id,
    Filter<int>? userId,
    Filter<String>? requestKey,
    Filter<String>? requestSignature,
    Filter<int>? totalCents,
    Filter<String>? status,
    Filter<DateTime>? createdAt,
  }) => OrderTable._(
    _query.whereFields({
      "id": ?id,
      "userId": ?userId,
      "requestKey": ?requestKey,
      "requestSignature": ?requestSignature,
      "totalCents": ?totalCents,
      "status": ?status,
      "createdAt": ?createdAt,
    }),
  );

  /// Adds field predicates joined by OR, combined with earlier filters by AND.
  /// An empty group fails before SQL. Field types and nullability are retained.
  OrderTable whereAny({
    Filter<int>? id,
    Filter<int>? userId,
    Filter<String>? requestKey,
    Filter<String>? requestSignature,
    Filter<int>? totalCents,
    Filter<String>? status,
    Filter<DateTime>? createdAt,
  }) => OrderTable._(
    _query.whereAnyFields({
      "id": ?id,
      "userId": ?userId,
      "requestKey": ?requestKey,
      "requestSignature": ?requestSignature,
      "totalCents": ?totalCents,
      "status": ?status,
      "createdAt": ?createdAt,
    }),
  );

  /// Adds one ordering field. Chain calls for multiple ordering fields.
  OrderTable orderBy({
    Direction? id,
    Direction? userId,
    Direction? requestKey,
    Direction? requestSignature,
    Direction? totalCents,
    Direction? status,
    Direction? createdAt,
  }) => OrderTable._(
    _query.orderByFields({
      "id": ?id,
      "userId": ?userId,
      "requestKey": ?requestKey,
      "requestSignature": ?requestSignature,
      "totalCents": ?totalCents,
      "status": ?status,
      "createdAt": ?createdAt,
    }),
  );

  /// Limits result rows; negative limits fail before SQL execution.
  OrderTable limit(int count) => OrderTable._(_query.limit(count));

  /// Skips result rows; negative offsets fail before SQL execution.
  OrderTable offset(int count) => OrderTable._(_query.offset(count));

  /// Executes a statically registered selection; unknown types fail before SQL.
  Future<List<T>> select<T>() {
    if (T == models.Order) {
      return _query.all().then((rows) => rows.cast<T>());
    }

    throw ArgumentError(
      'Unregistered selection type $T for '
      "orders.",
    );
  }

  /// Atomically increment supplied fields by key, retaining the where scope.
  OrderIncrement get increment => _OrderIncrement(_query);

  /// Atomically decrement supplied fields by key, retaining the where scope.
  OrderDecrement get decrement => _OrderDecrement(_query);
}

/// Typed creation arguments for orders.
abstract interface class OrderCreate {
  /// Returns the single inserted row; SQL failures propagate.
  Future<models.Order> call({
    required int userId,
    required String requestKey,
    required String requestSignature,
    int totalCents,
    String status,
    required DateTime createdAt,
  });
}

final class _OrderCreate implements OrderCreate {
  _OrderCreate(this._query);
  final TableQuery<models.Order> _query;
  @override
  Future<models.Order> call({
    Object? userId = _absent,
    Object? requestKey = _absent,
    Object? requestSignature = _absent,
    Object? totalCents = _absent,
    Object? status = _absent,
    Object? createdAt = _absent,
  }) => _query.insert({
    if (_provided(userId)) "userId": userId,
    if (_provided(requestKey)) "requestKey": requestKey,
    if (_provided(requestSignature)) "requestSignature": requestSignature,
    if (_provided(totalCents)) "totalCents": totalCents,
    if (_provided(status)) "status": status,
    if (_provided(createdAt)) "createdAt": createdAt,
  });
}

/// Typed partial update arguments for orders.
abstract interface class OrderUpdate {
  /// Returns the updated row, or null when key and where scope do not match.
  Future<models.Order?> call(
    int key, {
    int userId,
    String requestKey,
    String requestSignature,
    int totalCents,
    String status,
    DateTime createdAt,
  });
}

final class _OrderUpdate implements OrderUpdate {
  _OrderUpdate(this._query);
  final TableQuery<models.Order> _query;
  @override
  Future<models.Order?> call(
    int key, {
    Object? userId = _absent,
    Object? requestKey = _absent,
    Object? requestSignature = _absent,
    Object? totalCents = _absent,
    Object? status = _absent,
    Object? createdAt = _absent,
  }) => _query.updateById(key, {
    if (_provided(userId)) "userId": userId,
    if (_provided(requestKey)) "requestKey": requestKey,
    if (_provided(requestSignature)) "requestSignature": requestSignature,
    if (_provided(totalCents)) "totalCents": totalCents,
    if (_provided(status)) "status": status,
    if (_provided(createdAt)) "createdAt": createdAt,
  });
}

/// Single-column unique constraints that can prevent creation of orders.
final class OrderUnique {
  const OrderUnique._(this._field);
  final String _field;

  /// Conflict target: requestKey.
  static const requestKey = OrderUnique._("requestKey");
}

/// Typed creation arguments with an explicit unique conflict target.
abstract interface class OrderCreateIfAbsent {
  /// Returns the inserted row, or null for a conflict with the selected target.
  /// The target value must be supplied and non-null; other SQL failures propagate.
  Future<models.Order?> call(
    OrderUnique target, {
    required int userId,
    required String requestKey,
    required String requestSignature,
    int totalCents,
    String status,
    required DateTime createdAt,
  });
}

final class _OrderCreateIfAbsent implements OrderCreateIfAbsent {
  _OrderCreateIfAbsent(this._query);
  final TableQuery<models.Order> _query;
  @override
  Future<models.Order?> call(
    OrderUnique target, {
    Object? userId = _absent,
    Object? requestKey = _absent,
    Object? requestSignature = _absent,
    Object? totalCents = _absent,
    Object? status = _absent,
    Object? createdAt = _absent,
  }) => _query.insertIfAbsent({
    if (_provided(userId)) "userId": userId,
    if (_provided(requestKey)) "requestKey": requestKey,
    if (_provided(requestSignature)) "requestSignature": requestSignature,
    if (_provided(totalCents)) "totalCents": totalCents,
    if (_provided(status)) "status": status,
    if (_provided(createdAt)) "createdAt": createdAt,
  }, conflictField: target._field);
}

/// Typed atomic arithmetic arguments for orders.
abstract interface class OrderIncrement {
  /// Returns the changed row, or null when the key, filters or integer bounds
  /// do not match. Integer arithmetic stays within signed 64-bit bounds.
  /// SQLite REAL bounds also return null; PostgreSQL REAL overflow is a SQL error.
  Future<models.Order?> call(int key, {int totalCents});
}

final class _OrderIncrement implements OrderIncrement {
  _OrderIncrement(this._query);
  final TableQuery<models.Order> _query;
  @override
  Future<models.Order?> call(int key, {Object? totalCents = _absent}) =>
      _query.incrementById(key, {
        if (_provided(totalCents)) "totalCents": _number(totalCents),
      });
}

/// Typed atomic arithmetic arguments for orders.
abstract interface class OrderDecrement {
  /// Returns the changed row, or null when the key, filters or integer bounds
  /// do not match. Integer arithmetic stays within signed 64-bit bounds.
  /// SQLite REAL bounds also return null; PostgreSQL REAL overflow is a SQL error.
  Future<models.Order?> call(int key, {int totalCents});
}

final class _OrderDecrement implements OrderDecrement {
  _OrderDecrement(this._query);
  final TableQuery<models.Order> _query;
  @override
  Future<models.Order?> call(int key, {Object? totalCents = _absent}) =>
      _query.decrementById(key, {
        if (_provided(totalCents)) "totalCents": _number(totalCents),
      });
}

const _orderLinesDefinition = TableDefinition("order_lines", [
  ColumnDefinition(
    name: "id",
    field: "id",
    type: ScalarType.integer,
    nullable: false,
    primaryKey: true,
    identity: true,
    unique: false,
  ),
  ColumnDefinition(
    name: "order_id",
    field: "orderId",
    type: ScalarType.integer,
    nullable: false,
    primaryKey: false,
    identity: false,
    unique: false,
    references: ForeignKey("orders", "id", onDelete: "cascade"),
  ),
  ColumnDefinition(
    name: "product_id",
    field: "productId",
    type: ScalarType.integer,
    nullable: false,
    primaryKey: false,
    identity: false,
    unique: false,
    references: ForeignKey("products", "id", onDelete: "restrict"),
  ),
  ColumnDefinition(
    name: "quantity",
    field: "quantity",
    type: ScalarType.integer,
    nullable: false,
    primaryKey: false,
    identity: false,
    unique: false,
  ),
  ColumnDefinition(
    name: "unit_price_cents",
    field: "unitPriceCents",
    type: ScalarType.integer,
    nullable: false,
    primaryKey: false,
    identity: false,
    unique: false,
  ),
]);
models.OrderLine _decodeOrderLine(List<Object?> row) => models.OrderLine(
  id: decodeValue<int>(row[0]),
  orderId: decodeValue<int>(row[1]),
  productId: decodeValue<int>(row[2]),
  quantity: decodeValue<int>(row[3]),
  unitPriceCents: decodeValue<int>(row[4]),
);

/// An immutable query over the order_lines table.
final class OrderLineTable {
  OrderLineTable._(this._query);
  final TableQuery<models.OrderLine> _query;

  /// Creates one row. Omitted fields use database defaults; null is retained.
  ///
  /// Requires an unfiltered, unordered query without pagination. SQL errors
  /// propagate and roll back an enclosing explicit transaction.
  OrderLineCreate get create => _OrderLineCreate(_query);

  /// Updates supplied fields by primary key and the current where scope.
  ///
  /// Omitted fields are unchanged. Returns null when the key and where scope do
  /// not match. Empty updates, ordering and pagination fail before SQL.
  OrderLineUpdate get update => _OrderLineUpdate(_query);

  /// Fetches a row by its primary key.
  Future<models.OrderLine?> get(int id) => _query.get(id);

  /// Deletes a row by primary key and returns its affected row count.
  Future<int> delete(int id) => _query.deleteById(id);

  /// Fetches all matching full model rows.
  Future<List<models.OrderLine>> all() => _query.all();

  /// Counts rows in this scope, including limit and offset, in one SELECT.
  /// Count the unpaged filter scope to get a total before pagination.
  Future<int> count() => _query.count();

  /// Reads bounded batches within an active transaction scope.
  Stream<models.OrderLine> stream({int fetchSize = 500}) =>
      _query.stream(fetchSize: fetchSize);

  /// Adds field predicates joined by AND.
  OrderLineTable where({
    Filter<int>? id,
    Filter<int>? orderId,
    Filter<int>? productId,
    Filter<int>? quantity,
    Filter<int>? unitPriceCents,
  }) => OrderLineTable._(
    _query.whereFields({
      "id": ?id,
      "orderId": ?orderId,
      "productId": ?productId,
      "quantity": ?quantity,
      "unitPriceCents": ?unitPriceCents,
    }),
  );

  /// Adds field predicates joined by OR, combined with earlier filters by AND.
  /// An empty group fails before SQL. Field types and nullability are retained.
  OrderLineTable whereAny({
    Filter<int>? id,
    Filter<int>? orderId,
    Filter<int>? productId,
    Filter<int>? quantity,
    Filter<int>? unitPriceCents,
  }) => OrderLineTable._(
    _query.whereAnyFields({
      "id": ?id,
      "orderId": ?orderId,
      "productId": ?productId,
      "quantity": ?quantity,
      "unitPriceCents": ?unitPriceCents,
    }),
  );

  /// Adds one ordering field. Chain calls for multiple ordering fields.
  OrderLineTable orderBy({
    Direction? id,
    Direction? orderId,
    Direction? productId,
    Direction? quantity,
    Direction? unitPriceCents,
  }) => OrderLineTable._(
    _query.orderByFields({
      "id": ?id,
      "orderId": ?orderId,
      "productId": ?productId,
      "quantity": ?quantity,
      "unitPriceCents": ?unitPriceCents,
    }),
  );

  /// Limits result rows; negative limits fail before SQL execution.
  OrderLineTable limit(int count) => OrderLineTable._(_query.limit(count));

  /// Skips result rows; negative offsets fail before SQL execution.
  OrderLineTable offset(int count) => OrderLineTable._(_query.offset(count));

  /// Executes a statically registered selection; unknown types fail before SQL.
  Future<List<T>> select<T>() {
    if (T == models.OrderLine) {
      return _query.all().then((rows) => rows.cast<T>());
    }

    throw ArgumentError(
      'Unregistered selection type $T for '
      "order_lines.",
    );
  }

  /// Atomically increment supplied fields by key, retaining the where scope.
  OrderLineIncrement get increment => _OrderLineIncrement(_query);

  /// Atomically decrement supplied fields by key, retaining the where scope.
  OrderLineDecrement get decrement => _OrderLineDecrement(_query);
}

/// Typed creation arguments for order_lines.
abstract interface class OrderLineCreate {
  /// Returns the single inserted row; SQL failures propagate.
  Future<models.OrderLine> call({
    required int orderId,
    required int productId,
    required int quantity,
    required int unitPriceCents,
  });
}

final class _OrderLineCreate implements OrderLineCreate {
  _OrderLineCreate(this._query);
  final TableQuery<models.OrderLine> _query;
  @override
  Future<models.OrderLine> call({
    Object? orderId = _absent,
    Object? productId = _absent,
    Object? quantity = _absent,
    Object? unitPriceCents = _absent,
  }) => _query.insert({
    if (_provided(orderId)) "orderId": orderId,
    if (_provided(productId)) "productId": productId,
    if (_provided(quantity)) "quantity": quantity,
    if (_provided(unitPriceCents)) "unitPriceCents": unitPriceCents,
  });
}

/// Typed partial update arguments for order_lines.
abstract interface class OrderLineUpdate {
  /// Returns the updated row, or null when key and where scope do not match.
  Future<models.OrderLine?> call(
    int key, {
    int orderId,
    int productId,
    int quantity,
    int unitPriceCents,
  });
}

final class _OrderLineUpdate implements OrderLineUpdate {
  _OrderLineUpdate(this._query);
  final TableQuery<models.OrderLine> _query;
  @override
  Future<models.OrderLine?> call(
    int key, {
    Object? orderId = _absent,
    Object? productId = _absent,
    Object? quantity = _absent,
    Object? unitPriceCents = _absent,
  }) => _query.updateById(key, {
    if (_provided(orderId)) "orderId": orderId,
    if (_provided(productId)) "productId": productId,
    if (_provided(quantity)) "quantity": quantity,
    if (_provided(unitPriceCents)) "unitPriceCents": unitPriceCents,
  });
}

/// Typed atomic arithmetic arguments for order_lines.
abstract interface class OrderLineIncrement {
  /// Returns the changed row, or null when the key, filters or integer bounds
  /// do not match. Integer arithmetic stays within signed 64-bit bounds.
  /// SQLite REAL bounds also return null; PostgreSQL REAL overflow is a SQL error.
  Future<models.OrderLine?> call(int key, {int quantity, int unitPriceCents});
}

final class _OrderLineIncrement implements OrderLineIncrement {
  _OrderLineIncrement(this._query);
  final TableQuery<models.OrderLine> _query;
  @override
  Future<models.OrderLine?> call(
    int key, {
    Object? quantity = _absent,
    Object? unitPriceCents = _absent,
  }) => _query.incrementById(key, {
    if (_provided(quantity)) "quantity": _number(quantity),
    if (_provided(unitPriceCents)) "unitPriceCents": _number(unitPriceCents),
  });
}

/// Typed atomic arithmetic arguments for order_lines.
abstract interface class OrderLineDecrement {
  /// Returns the changed row, or null when the key, filters or integer bounds
  /// do not match. Integer arithmetic stays within signed 64-bit bounds.
  /// SQLite REAL bounds also return null; PostgreSQL REAL overflow is a SQL error.
  Future<models.OrderLine?> call(int key, {int quantity, int unitPriceCents});
}

final class _OrderLineDecrement implements OrderLineDecrement {
  _OrderLineDecrement(this._query);
  final TableQuery<models.OrderLine> _query;
  @override
  Future<models.OrderLine?> call(
    int key, {
    Object? quantity = _absent,
    Object? unitPriceCents = _absent,
  }) => _query.decrementById(key, {
    if (_provided(quantity)) "quantity": _number(quantity),
    if (_provided(unitPriceCents)) "unitPriceCents": _number(unitPriceCents),
  });
}
