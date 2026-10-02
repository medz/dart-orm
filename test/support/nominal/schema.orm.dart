// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/orm.dart' as orm_model show ModelTable, ModelQuery;
import 'package:orm/values.dart';

import "schema.dart" as models;
export "schema.dart" show Email, Account, Note;

final class _OrmWriteAbsent {
  const _OrmWriteAbsent();
}

const _writeAbsent = _OrmWriteAbsent();
WriteValue<T, F> _writeLiteral<T, F extends Fields>(Object? value) =>
    identical(value, _writeAbsent) ? const .keep() : .set(value as T);

final _accountId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _accountEmail = Column<models.Email>(
  "email",
  models.emailCodec,
  nullable: false,
  generated: false,
);
final _accountLabel = Column<String?>(
  "display_name",
  Codecs.text.nullable(),
  nullable: true,
  generated: false,
);
final _accountEnabled = Column<bool>(
  "enabled",
  Codecs.boolean,
  nullable: false,
  generated: false,
  defaultSql: "false",
);
final _accountMarker = Column<String>(
  "marker",
  Codecs.text,
  nullable: false,
  generated: false,
  clientDefault: models.defaultMarker,
);
final _accountA = Column<int>(
  "a",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _accountB = Column<int>(
  "b",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _accountC = Column<int>(
  "c",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _accountTotal = Column<int>(
  "total",
  Codecs.integer,
  nullable: false,
  generated: false,
  computed: ComputedColumn.forDialects(
    sqlite: "a + b",
    postgres: "a + b",
    mysql: "a + b",
    mariadb: "a + b",
    storage: ComputedStorage.stored,
  ),
);
final accountSchema = TableSchema(
  "nominal_accounts",
  columns: [
    _accountId,
    _accountEmail,
    _accountLabel,
    _accountEnabled,
    _accountMarker,
    _accountA,
    _accountB,
    _accountC,
    _accountTotal,
  ],
  primaryKey: ["id"],
  uniqueKeys: [
    ["email"],
  ],
  indexes: [],
  foreignKeys: [],
);

final class AccountFields extends Fields {
  AccountFields(super.table);
  late final id = column(_accountId);
  late final email = column(_accountEmail);
  late final label = column(_accountLabel);
  late final enabled = column(_accountEnabled);
  late final marker = column(_accountMarker);
  late final a = column(_accountA);
  late final b = column(_accountB);
  late final c = column(_accountC);
  late final total = readColumn(_accountTotal);

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Note, NoteFields> get notes =>
      Relation(noteTable, parent: [id], child: (row) => [row.accountId]);
}

final accountTable = Table<models.Account, AccountFields>(
  accountSchema,
  AccountFields.new,
  (row) =>
      (
        (row.id, row.email, row.label, row.enabled, row.marker).map(
          (id, email, label, enabled, marker) => (
            id: id,
            email: email,
            label: label,
            enabled: enabled,
            marker: marker,
          ),
        ),
        (
          row.a,
          row.b,
          row.c,
          row.total,
        ).map((a, b, c, total) => (a: a, b: b, c: c, total: total)),
      ).map(
        (left, right) => models.Account(
          id: left.id,
          email: left.email,
          label: left.label,
          enabled: left.enabled,
          marker: left.marker,
          a: right.a,
          b: right.b,
          c: right.c,
          total: right.total,
        ),
      ),
);

/// Immutable input data; composition belongs to [accountPatch], not field names.
final class AccountPatch {
  final WriteValue<models.Email, AccountFields> email;
  final WriteValue<String?, AccountFields> label;
  final WriteValue<bool, AccountFields> enabled;
  final WriteValue<String, AccountFields> marker;
  final WriteValue<int, AccountFields> a;
  final WriteValue<int, AccountFields> b;
  final WriteValue<int, AccountFields> c;
  AccountPatch._({
    required this.email,
    required this.label,
    required this.enabled,
    required this.marker,
    required this.a,
    required this.b,
    required this.c,
  });

  List<Assignment> _assignments(AccountFields fields) => [
    ...fields.email.write(email, fields),
    ...fields.label.write(label, fields),
    ...fields.enabled.write(enabled, fields),
    ...fields.marker.write(marker, fields),
    ...fields.a.write(a, fields),
    ...fields.b.write(b, fields),
    ...fields.c.write(c, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class AccountPatchFactory {
  AccountPatch call({
    models.Email email,
    String? label,
    bool enabled,
    String marker,
    int a,
    int b,
    int c,
  });
  AccountPatch values({
    WriteValue<models.Email, AccountFields> email = const .keep(),
    WriteValue<String?, AccountFields> label = const .keep(),
    WriteValue<bool, AccountFields> enabled = const .keep(),
    WriteValue<String, AccountFields> marker = const .keep(),
    WriteValue<int, AccountFields> a = const .keep(),
    WriteValue<int, AccountFields> b = const .keep(),
    WriteValue<int, AccountFields> c = const .keep(),
  });
  AccountPatch overlay(Iterable<AccountPatch> layers);
  bool isEmpty(AccountPatch input);
}

const AccountPatchFactory accountPatch = _AccountPatchFactory();

final class _AccountPatchFactory implements AccountPatchFactory {
  const _AccountPatchFactory();
  @override
  AccountPatch call({
    Object? email = _writeAbsent,
    Object? label = _writeAbsent,
    Object? enabled = _writeAbsent,
    Object? marker = _writeAbsent,
    Object? a = _writeAbsent,
    Object? b = _writeAbsent,
    Object? c = _writeAbsent,
  }) => AccountPatch._(
    email: _writeLiteral<models.Email, AccountFields>(email),
    label: _writeLiteral<String?, AccountFields>(label),
    enabled: _writeLiteral<bool, AccountFields>(enabled),
    marker: _writeLiteral<String, AccountFields>(marker),
    a: _writeLiteral<int, AccountFields>(a),
    b: _writeLiteral<int, AccountFields>(b),
    c: _writeLiteral<int, AccountFields>(c),
  );
  @override
  AccountPatch values({
    WriteValue<models.Email, AccountFields> email = const .keep(),
    WriteValue<String?, AccountFields> label = const .keep(),
    WriteValue<bool, AccountFields> enabled = const .keep(),
    WriteValue<String, AccountFields> marker = const .keep(),
    WriteValue<int, AccountFields> a = const .keep(),
    WriteValue<int, AccountFields> b = const .keep(),
    WriteValue<int, AccountFields> c = const .keep(),
  }) => AccountPatch._(
    email: email,
    label: label,
    enabled: enabled,
    marker: marker,
    a: a,
    b: b,
    c: c,
  );
  @override
  AccountPatch overlay(Iterable<AccountPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = AccountPatch._(
        email: WriteValue.overlay(earlier.email, later.email),
        label: WriteValue.overlay(earlier.label, later.label),
        enabled: WriteValue.overlay(earlier.enabled, later.enabled),
        marker: WriteValue.overlay(earlier.marker, later.marker),
        a: WriteValue.overlay(earlier.a, later.a),
        b: WriteValue.overlay(earlier.b, later.b),
        c: WriteValue.overlay(earlier.c, later.c),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(AccountPatch input) =>
      input.email.isMissing &&
      input.label.isMissing &&
      input.enabled.isMissing &&
      input.marker.isMissing &&
      input.a.isMissing &&
      input.b.isMissing &&
      input.c.isMissing;
}

/// Immutable input data; composition belongs to [accountInsert], not field names.
final class AccountInsert {
  final WriteValue<int, AccountFields> id;
  final WriteValue<models.Email, AccountFields> email;
  final WriteValue<String?, AccountFields> label;
  final WriteValue<bool, AccountFields> enabled;
  final WriteValue<String, AccountFields> marker;
  final WriteValue<int, AccountFields> a;
  final WriteValue<int, AccountFields> b;
  final WriteValue<int, AccountFields> c;
  AccountInsert._({
    required this.id,
    required this.email,
    required this.label,
    required this.enabled,
    required this.marker,
    required this.a,
    required this.b,
    required this.c,
  }) {
    if (email.isMissing) {
      throw ArgumentError.value(email, 'email', 'Must be supplied.');
    }
    if (a.isMissing) {
      throw ArgumentError.value(a, 'a', 'Must be supplied.');
    }
    if (b.isMissing) {
      throw ArgumentError.value(b, 'b', 'Must be supplied.');
    }
    if (c.isMissing) {
      throw ArgumentError.value(c, 'c', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(AccountFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.email.write(email, fields),
    ...fields.label.write(label, fields),
    ...fields.enabled.write(enabled, fields),
    ...fields.marker.write(marker, fields),
    ...fields.a.write(a, fields),
    ...fields.b.write(b, fields),
    ...fields.c.write(c, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class AccountInsertFactory {
  AccountInsert call({
    int id,
    required models.Email email,
    String? label,
    bool enabled,
    String marker,
    required int a,
    required int b,
    required int c,
  });
  AccountInsert values({
    WriteValue<int, AccountFields> id = const .keep(),
    required WriteValue<models.Email, AccountFields> email,
    WriteValue<String?, AccountFields> label = const .keep(),
    WriteValue<bool, AccountFields> enabled = const .keep(),
    WriteValue<String, AccountFields> marker = const .keep(),
    required WriteValue<int, AccountFields> a,
    required WriteValue<int, AccountFields> b,
    required WriteValue<int, AccountFields> c,
  });
  AccountInsert overlay(AccountInsert earlier, Iterable<AccountPatch> layers);
}

const AccountInsertFactory accountInsert = _AccountInsertFactory();

final class _AccountInsertFactory implements AccountInsertFactory {
  const _AccountInsertFactory();
  @override
  AccountInsert call({
    Object? id = _writeAbsent,
    required models.Email email,
    Object? label = _writeAbsent,
    Object? enabled = _writeAbsent,
    Object? marker = _writeAbsent,
    required int a,
    required int b,
    required int c,
  }) => AccountInsert._(
    id: _writeLiteral<int, AccountFields>(id),
    email: .set(email),
    label: _writeLiteral<String?, AccountFields>(label),
    enabled: _writeLiteral<bool, AccountFields>(enabled),
    marker: _writeLiteral<String, AccountFields>(marker),
    a: .set(a),
    b: .set(b),
    c: .set(c),
  );
  @override
  AccountInsert values({
    WriteValue<int, AccountFields> id = const .keep(),
    required WriteValue<models.Email, AccountFields> email,
    WriteValue<String?, AccountFields> label = const .keep(),
    WriteValue<bool, AccountFields> enabled = const .keep(),
    WriteValue<String, AccountFields> marker = const .keep(),
    required WriteValue<int, AccountFields> a,
    required WriteValue<int, AccountFields> b,
    required WriteValue<int, AccountFields> c,
  }) => AccountInsert._(
    id: id,
    email: email,
    label: label,
    enabled: enabled,
    marker: marker,
    a: a,
    b: b,
    c: c,
  );
  @override
  AccountInsert overlay(AccountInsert earlier, Iterable<AccountPatch> layers) {
    for (final later in layers) {
      earlier = AccountInsert._(
        id: earlier.id,
        email: WriteValue.overlay(earlier.email, later.email),
        label: WriteValue.overlay(earlier.label, later.label),
        enabled: WriteValue.overlay(earlier.enabled, later.enabled),
        marker: WriteValue.overlay(earlier.marker, later.marker),
        a: WriteValue.overlay(earlier.a, later.a),
        b: WriteValue.overlay(earlier.b, later.b),
        c: WriteValue.overlay(earlier.c, later.c),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Account from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class AccountCreator {
  Future<models.Account> call({
    int id,
    required models.Email email,
    String? label,
    bool enabled,
    String marker,
    required int a,
    required int b,
    required int c,
  });
}

final class _AccountCreator implements AccountCreator {
  final AccountTableSet _table;
  const _AccountCreator(this._table);
  @override
  Future<models.Account> call({
    Object? id = _writeAbsent,
    required models.Email email,
    Object? label = _writeAbsent,
    Object? enabled = _writeAbsent,
    Object? marker = _writeAbsent,
    required int a,
    required int b,
    required int c,
  }) async => _table.plan
      .insert(
        AccountInsert._(
          id: _writeLiteral<int, AccountFields>(id),
          email: .set(email),
          label: _writeLiteral<String?, AccountFields>(label),
          enabled: _writeLiteral<bool, AccountFields>(enabled),
          marker: _writeLiteral<String, AccountFields>(marker),
          a: .set(a),
          b: .set(b),
          c: .set(c),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class AccountPatcher {
  Future<int> call({
    models.Email email,
    String? label,
    bool enabled,
    String marker,
    int a,
    int b,
    int c,
  });
}

final class _AccountPatcher implements AccountPatcher {
  final orm_model.ModelQuery<models.Account, AccountFields, AccountPatch>
  _query;
  const _AccountPatcher(this._query);
  @override
  Future<int> call({
    Object? email = _writeAbsent,
    Object? label = _writeAbsent,
    Object? enabled = _writeAbsent,
    Object? marker = _writeAbsent,
    Object? a = _writeAbsent,
    Object? b = _writeAbsent,
    Object? c = _writeAbsent,
  }) => _query.update(
    AccountPatch._(
      email: _writeLiteral<models.Email, AccountFields>(email),
      label: _writeLiteral<String?, AccountFields>(label),
      enabled: _writeLiteral<bool, AccountFields>(enabled),
      marker: _writeLiteral<String, AccountFields>(marker),
      a: _writeLiteral<int, AccountFields>(a),
      b: _writeLiteral<int, AccountFields>(b),
      c: _writeLiteral<int, AccountFields>(c),
    ),
  );
}

/// Named literal updates on a complete models.Account query.
extension AccountWrites
    on orm_model.ModelQuery<models.Account, AccountFields, AccountPatch> {
  /// Executes one update; omitted fields remain unchanged.
  AccountPatcher get patch => _AccountPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class AccountTableSet
    extends
        orm_model.ModelTable<
          models.Account,
          AccountFields,
          AccountInsert,
          AccountPatch
        > {
  AccountTableSet(QueryContext db)
    : super(
        db,
        accountTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final AccountCreator create = _AccountCreator(this);

  orm_model.ModelQuery<models.Account, AccountFields, AccountPatch> byId(
    int id,
  ) => where((row) => row.id.eq(.value(id)));
}

final _noteId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _noteAccountId = Column<int>(
  "account_id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _noteBody = Column<String>(
  "body",
  Codecs.text,
  nullable: false,
  generated: false,
);
final noteSchema = TableSchema(
  "nominal_notes",
  columns: [_noteId, _noteAccountId, _noteBody],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [
    ForeignKey(["account_id"], "nominal_accounts", ["id"], onDelete: "CASCADE"),
  ],
);

final class NoteFields extends Fields {
  NoteFields(super.table);
  late final id = column(_noteId);
  late final accountId = column(_noteAccountId);
  late final body = column(_noteBody);
  Relation<models.Account, AccountFields> get account =>
      Relation(accountTable, parent: [accountId], child: (row) => [row.id]);
}

final noteTable = Table<models.Note, NoteFields>(
  noteSchema,
  NoteFields.new,
  (row) => (
    row.id,
    row.accountId,
    row.body,
  ).map((v0, v1, v2) => models.Note(id: v0, accountId: v1, body: v2)),
);

/// Immutable input data; composition belongs to [notePatch], not field names.
final class NotePatch {
  final WriteValue<int, NoteFields> accountId;
  final WriteValue<String, NoteFields> body;
  NotePatch._({required this.accountId, required this.body});

  List<Assignment> _assignments(NoteFields fields) => [
    ...fields.accountId.write(accountId, fields),
    ...fields.body.write(body, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class NotePatchFactory {
  NotePatch call({int accountId, String body});
  NotePatch values({
    WriteValue<int, NoteFields> accountId = const .keep(),
    WriteValue<String, NoteFields> body = const .keep(),
  });
  NotePatch overlay(Iterable<NotePatch> layers);
  bool isEmpty(NotePatch input);
}

const NotePatchFactory notePatch = _NotePatchFactory();

final class _NotePatchFactory implements NotePatchFactory {
  const _NotePatchFactory();
  @override
  NotePatch call({
    Object? accountId = _writeAbsent,
    Object? body = _writeAbsent,
  }) => NotePatch._(
    accountId: _writeLiteral<int, NoteFields>(accountId),
    body: _writeLiteral<String, NoteFields>(body),
  );
  @override
  NotePatch values({
    WriteValue<int, NoteFields> accountId = const .keep(),
    WriteValue<String, NoteFields> body = const .keep(),
  }) => NotePatch._(accountId: accountId, body: body);
  @override
  NotePatch overlay(Iterable<NotePatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = NotePatch._(
        accountId: WriteValue.overlay(earlier.accountId, later.accountId),
        body: WriteValue.overlay(earlier.body, later.body),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(NotePatch input) =>
      input.accountId.isMissing && input.body.isMissing;
}

/// Immutable input data; composition belongs to [noteInsert], not field names.
final class NoteInsert {
  final WriteValue<int, NoteFields> id;
  final WriteValue<int, NoteFields> accountId;
  final WriteValue<String, NoteFields> body;
  NoteInsert._({
    required this.id,
    required this.accountId,
    required this.body,
  }) {
    if (accountId.isMissing) {
      throw ArgumentError.value(accountId, 'accountId', 'Must be supplied.');
    }
    if (body.isMissing) {
      throw ArgumentError.value(body, 'body', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(NoteFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.accountId.write(accountId, fields),
    ...fields.body.write(body, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class NoteInsertFactory {
  NoteInsert call({int id, required int accountId, required String body});
  NoteInsert values({
    WriteValue<int, NoteFields> id = const .keep(),
    required WriteValue<int, NoteFields> accountId,
    required WriteValue<String, NoteFields> body,
  });
  NoteInsert overlay(NoteInsert earlier, Iterable<NotePatch> layers);
}

const NoteInsertFactory noteInsert = _NoteInsertFactory();

final class _NoteInsertFactory implements NoteInsertFactory {
  const _NoteInsertFactory();
  @override
  NoteInsert call({
    Object? id = _writeAbsent,
    required int accountId,
    required String body,
  }) => NoteInsert._(
    id: _writeLiteral<int, NoteFields>(id),
    accountId: .set(accountId),
    body: .set(body),
  );
  @override
  NoteInsert values({
    WriteValue<int, NoteFields> id = const .keep(),
    required WriteValue<int, NoteFields> accountId,
    required WriteValue<String, NoteFields> body,
  }) => NoteInsert._(id: id, accountId: accountId, body: body);
  @override
  NoteInsert overlay(NoteInsert earlier, Iterable<NotePatch> layers) {
    for (final later in layers) {
      earlier = NoteInsert._(
        id: earlier.id,
        accountId: WriteValue.overlay(earlier.accountId, later.accountId),
        body: WriteValue.overlay(earlier.body, later.body),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Note from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class NoteCreator {
  Future<models.Note> call({
    int id,
    required int accountId,
    required String body,
  });
}

final class _NoteCreator implements NoteCreator {
  final NoteTableSet _table;
  const _NoteCreator(this._table);
  @override
  Future<models.Note> call({
    Object? id = _writeAbsent,
    required int accountId,
    required String body,
  }) async => _table.plan
      .insert(
        NoteInsert._(
          id: _writeLiteral<int, NoteFields>(id),
          accountId: .set(accountId),
          body: .set(body),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class NotePatcher {
  Future<int> call({int accountId, String body});
}

final class _NotePatcher implements NotePatcher {
  final orm_model.ModelQuery<models.Note, NoteFields, NotePatch> _query;
  const _NotePatcher(this._query);
  @override
  Future<int> call({
    Object? accountId = _writeAbsent,
    Object? body = _writeAbsent,
  }) => _query.update(
    NotePatch._(
      accountId: _writeLiteral<int, NoteFields>(accountId),
      body: _writeLiteral<String, NoteFields>(body),
    ),
  );
}

/// Named literal updates on a complete models.Note query.
extension NoteWrites
    on orm_model.ModelQuery<models.Note, NoteFields, NotePatch> {
  /// Executes one update; omitted fields remain unchanged.
  NotePatcher get patch => _NotePatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class NoteTableSet
    extends
        orm_model.ModelTable<models.Note, NoteFields, NoteInsert, NotePatch> {
  NoteTableSet(QueryContext db)
    : super(
        db,
        noteTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final NoteCreator create = _NoteCreator(this);

  orm_model.ModelQuery<models.Note, NoteFields, NotePatch> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

final appSchema = List<TableSchema>.unmodifiable([accountSchema, noteSchema]);

extension AppTables on QueryContext {
  AccountTableSet get account => AccountTableSet(this);
  NoteTableSet get note => NoteTableSet(this);
}
