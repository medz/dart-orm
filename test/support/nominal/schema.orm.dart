// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';

import "schema.dart" as models;
export "schema.dart" show Account, Note;

final _accountsId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _accountsEmail = Column<models.Email>(
  "email",
  models.emailCodec,
  nullable: false,
  generated: false,
);
final _accountsLabel = Column<String?>(
  "display_name",
  Codecs.text.nullable(),
  nullable: true,
  generated: false,
);
final _accountsEnabled = Column<bool>(
  "enabled",
  Codecs.boolean,
  nullable: false,
  generated: false,
  defaultSql: "false",
);
final _accountsMarker = Column<String>(
  "marker",
  Codecs.text,
  nullable: false,
  generated: false,
  clientDefault: models.defaultMarker,
);
final _accountsA = Column<int>(
  "a",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _accountsB = Column<int>(
  "b",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _accountsC = Column<int>(
  "c",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _accountsTotal = Column<int>(
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
final accountsSchema = TableSchema(
  "nominal_accounts",
  columns: [
    _accountsId,
    _accountsEmail,
    _accountsLabel,
    _accountsEnabled,
    _accountsMarker,
    _accountsA,
    _accountsB,
    _accountsC,
    _accountsTotal,
  ],
  primaryKey: ["id"],
  uniqueKeys: [
    ["email"],
  ],
  indexes: [],
  foreignKeys: [],
);

final class AccountsFields extends Fields {
  AccountsFields(super.table);
  late final id = column(_accountsId);
  late final email = column(_accountsEmail);
  late final label = column(_accountsLabel);
  late final enabled = column(_accountsEnabled);
  late final marker = column(_accountsMarker);
  late final a = column(_accountsA);
  late final b = column(_accountsB);
  late final c = column(_accountsC);
  late final total = readColumn(_accountsTotal);
  Relation<models.Note, NotesFields> get notes =>
      Relation(notesTable, parent: [id], child: (row) => [row.accountId]);
}

final accountsTable = Table<models.Account, AccountsFields>(
  accountsSchema,
  AccountsFields.new,
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
          left.id,
          left.email,
          left.label,
          left.enabled,
          left.marker,
          right.a,
          right.b,
          right.c,
          right.total,
        ),
      ),
);

final class AccountsTableSet extends TableSet<models.Account, AccountsFields> {
  AccountsTableSet(QueryContext db) : super(db, accountsTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Account> create({
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
  Query<models.Account, AccountsFields> byId(int id) =>
      where((row) => row.id.eq(id));
}

extension AccountsUpdates on Query<models.Account, AccountsFields> {
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

final _notesId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _notesAccountId = Column<int>(
  "account_id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _notesBody = Column<String>(
  "body",
  Codecs.text,
  nullable: false,
  generated: false,
);
final notesSchema = TableSchema(
  "nominal_notes",
  columns: [_notesId, _notesAccountId, _notesBody],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [
    ForeignKey(["account_id"], "nominal_accounts", ["id"], onDelete: "CASCADE"),
  ],
);

final class NotesFields extends Fields {
  NotesFields(super.table);
  late final id = column(_notesId);
  late final accountId = column(_notesAccountId);
  late final body = column(_notesBody);
  Relation<models.Account, AccountsFields> get account =>
      Relation(accountsTable, parent: [accountId], child: (row) => [row.id]);
}

final notesTable = Table<models.Note, NotesFields>(
  notesSchema,
  NotesFields.new,
  (row) => (
    row.id,
    row.accountId,
    row.body,
  ).map((v0, v1, v2) => models.Note(id: v0, accountId: v1, body: v2)),
);

final class NotesTableSet extends TableSet<models.Note, NotesFields> {
  NotesTableSet(QueryContext db) : super(db, notesTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Note> create({
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
  Query<models.Note, NotesFields> byId(int id) => where((row) => row.id.eq(id));
}

extension NotesUpdates on Query<models.Note, NotesFields> {
  Future<int> patch({
    Change<int> accountId = const Change.keep(),
    Change<String> body = const Change.keep(),
  }) => update(
    (row) => [...row.accountId.change(accountId), ...row.body.change(body)],
  ).execute();
}

final appSchema = List<TableSchema>.unmodifiable([accountsSchema, notesSchema]);

extension AppTables on QueryContext {
  AccountsTableSet get accounts => AccountsTableSet(this);
  NotesTableSet get notes => NotesTableSet(this);
}
