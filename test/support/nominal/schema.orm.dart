// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';

import "schema.dart" as models;
export "schema.dart" show Email;

/// A complete immutable row from "nominal_accounts".
final class Account({
  required final int id,
  required final models.Email email,
  required final String? label,
  required final bool enabled,
  required final String marker,
  required final int a,
  required final int b,
  required final int c,
  required final int total,
});
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
  Relation<Note, NoteFields> get notes =>
      Relation(noteTable, parent: [id], child: (row) => [row.accountId]);
}

final accountTable = Table<Account, AccountFields>(
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
        (left, right) => Account(
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

final class AccountTableSet extends TableSet<Account, AccountFields> {
  AccountTableSet(QueryContext db) : super(db, accountTable) {
    db.registerSchema(appSchema);
  }
  Future<Account> create({
    Change<int> id = const Change.keep(),
    required models.Email email,
    String? label,
    Change<bool> enabled = const Change.keep(),
    Change<String> marker = const Change.keep(),
    required int a,
    required int b,
    required int c,
  }) => createRow(
    (row) => [
      ...row.id.change(id),
      row.email.set(email),
      row.label.set(label),
      ...row.enabled.change(enabled),
      ...row.marker.change(marker),
      row.a.set(a),
      row.b.set(b),
      row.c.set(c),
    ],
  );
  Query<Account, AccountFields> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

extension AccountUpdates on Query<Account, AccountFields> {
  Future<int> patch({
    Change<models.Email> email = const Change.keep(),
    Change<String?> label = const Change.keep(),
    Change<bool> enabled = const Change.keep(),
    Change<String> marker = const Change.keep(),
    Change<int> a = const Change.keep(),
    Change<int> b = const Change.keep(),
    Change<int> c = const Change.keep(),
  }) => update(
    (row) => [
      ...row.email.change(email),
      ...row.label.change(label),
      ...row.enabled.change(enabled),
      ...row.marker.change(marker),
      ...row.a.change(a),
      ...row.b.change(b),
      ...row.c.change(c),
    ],
  ).execute();
}

/// A complete immutable row from "nominal_notes".
final class Note({
  required final int id,
  required final int accountId,
  required final String body,
});
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
  Relation<Account, AccountFields> get account =>
      Relation(accountTable, parent: [accountId], child: (row) => [row.id]);
}

final noteTable = Table<Note, NoteFields>(
  noteSchema,
  NoteFields.new,
  (row) => (
    row.id,
    row.accountId,
    row.body,
  ).map((v0, v1, v2) => Note(id: v0, accountId: v1, body: v2)),
);

final class NoteTableSet extends TableSet<Note, NoteFields> {
  NoteTableSet(QueryContext db) : super(db, noteTable) {
    db.registerSchema(appSchema);
  }
  Future<Note> create({
    Change<int> id = const Change.keep(),
    required int accountId,
    required String body,
  }) => createRow(
    (row) => [
      ...row.id.change(id),
      row.accountId.set(accountId),
      row.body.set(body),
    ],
  );
  Query<Note, NoteFields> byId(int id) => where((row) => row.id.eq(.value(id)));
}

extension NoteUpdates on Query<Note, NoteFields> {
  Future<int> patch({
    Change<int> accountId = const Change.keep(),
    Change<String> body = const Change.keep(),
  }) => update(
    (row) => [...row.accountId.change(accountId), ...row.body.change(body)],
  ).execute();
}

final appSchema = List<TableSchema>.unmodifiable([accountSchema, noteSchema]);

extension AppTables on QueryContext {
  AccountTableSet get account => AccountTableSet(this);
  NoteTableSet get note => NoteTableSet(this);
}
