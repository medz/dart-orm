// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';
import 'package:orm/sql.dart' as orm show allOf;

import "schema.dart" as models;
export "schema.dart" show Account, Entry, Reading;

final _accountTenant = Column<int>(
  "tenant",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _accountId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _accountLabel = Column<String?>(
  "display_label",
  Codecs.text.nullable(),
  nullable: true,
  generated: false,
);
final _accountManagerId = Column<int?>(
  "manager_id",
  Codecs.integer.nullable(),
  nullable: true,
  generated: false,
);
final accountSchema = TableSchema(
  "accounts",
  columns: [_accountTenant, _accountId, _accountLabel, _accountManagerId],
  primaryKey: ["tenant", "id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class AccountFields extends Fields {
  AccountFields(super.table);
  late final tenant = column(_accountTenant);
  late final id = column(_accountId);
  late final label = column(_accountLabel);
  late final managerId = column(_accountManagerId);

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Entry, EntryFields> get entries => Relation(
    entryTable,
    parent: [tenant, id],
    child: (row) => [row.tenant, row.owner],
  );

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Entry, EntryFields> get matches => Relation(
    entryTable,
    parent: [tenant, label],
    child: (row) => [row.tenant, row.label],
  );

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Account, AccountFields> get manager => Relation(
    accountTable,
    parent: [tenant, managerId],
    child: (row) => [row.tenant, row.id],
  );

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Account, AccountFields> get reports => Relation(
    accountTable,
    parent: [tenant, id],
    child: (row) => [row.tenant, row.managerId],
  );
}

final accountTable = Table<models.Account, AccountFields>(
  accountSchema,
  AccountFields.new,
  (row) => (row.tenant, row.id, row.label, row.managerId).map(
    (v0, v1, v2, v3) =>
        models.Account(tenant: v0, id: v1, label: v2, managerId: v3),
  ),
);

final class AccountTableSet extends TableSet<models.Account, AccountFields> {
  AccountTableSet(QueryContext db) : super(db, accountTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Account> create({
    required int tenant,
    required int id,
    String? label,
    int? managerId,
  }) => createRow(
    (row) => [
      row.tenant.set(tenant),
      row.id.set(id),
      row.label.set(label),
      row.managerId.set(managerId),
    ],
  );
  Query<models.Account, AccountFields> byId({
    required int tenant,
    required int id,
  }) => where(
    (row) => orm.allOf([row.tenant.eq(.value(tenant)), row.id.eq(.value(id))]),
  );
}

extension AccountUpdates on Query<models.Account, AccountFields> {
  Future<int> patch({
    Change<int> tenant = const Change.keep(),
    Change<int> id = const Change.keep(),
    Change<String?> label = const Change.keep(),
    Change<int?> managerId = const Change.keep(),
  }) => update(
    (row) => [
      ...row.tenant.change(tenant),
      ...row.id.change(id),
      ...row.label.change(label),
      ...row.managerId.change(managerId),
    ],
  ).execute();
}

final _entryId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _entryTenant = Column<int?>(
  "tenant",
  Codecs.integer.nullable(),
  nullable: true,
  generated: false,
);
final _entryOwner = Column<int?>(
  "owner",
  Codecs.integer.nullable(),
  nullable: true,
  generated: false,
);
final _entryLabel = Column<String?>(
  "lookup_label",
  Codecs.text.nullable(),
  nullable: true,
  generated: false,
);
final entrySchema = TableSchema(
  "entries",
  columns: [_entryId, _entryTenant, _entryOwner, _entryLabel],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class EntryFields extends Fields {
  EntryFields(super.table);
  late final id = column(_entryId);
  late final tenant = column(_entryTenant);
  late final owner = column(_entryOwner);
  late final label = column(_entryLabel);

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Account, AccountFields> get ownerAccount => Relation(
    accountTable,
    parent: [tenant, owner],
    child: (row) => [row.tenant, row.id],
  );

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Account, AccountFields> get matchingAccounts => Relation(
    accountTable,
    parent: [tenant, label],
    child: (row) => [row.tenant, row.label],
  );
}

final entryTable = Table<models.Entry, EntryFields>(
  entrySchema,
  EntryFields.new,
  (row) => (row.id, row.tenant, row.owner, row.label).map(
    (v0, v1, v2, v3) => models.Entry(id: v0, tenant: v1, owner: v2, label: v3),
  ),
);

final class EntryTableSet extends TableSet<models.Entry, EntryFields> {
  EntryTableSet(QueryContext db) : super(db, entryTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Entry> create({
    required int id,
    int? tenant,
    int? owner,
    String? label,
  }) => createRow(
    (row) => [
      row.id.set(id),
      row.tenant.set(tenant),
      row.owner.set(owner),
      row.label.set(label),
    ],
  );
  Query<models.Entry, EntryFields> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

extension EntryUpdates on Query<models.Entry, EntryFields> {
  Future<int> patch({
    Change<int> id = const Change.keep(),
    Change<int?> tenant = const Change.keep(),
    Change<int?> owner = const Change.keep(),
    Change<String?> label = const Change.keep(),
  }) => update(
    (row) => [
      ...row.id.change(id),
      ...row.tenant.change(tenant),
      ...row.owner.change(owner),
      ...row.label.change(label),
    ],
  ).execute();
}

final _readingId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _readingValue = Column<double>(
  "value",
  Codecs.real,
  nullable: false,
  generated: false,
);
final readingSchema = TableSchema(
  "readings",
  columns: [_readingId, _readingValue],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class ReadingFields extends Fields {
  ReadingFields(super.table);
  late final id = column(_readingId);
  late final value = column(_readingValue);

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Reading, ReadingFields> get peers =>
      Relation(readingTable, parent: [value], child: (row) => [row.value]);
}

final readingTable = Table<models.Reading, ReadingFields>(
  readingSchema,
  ReadingFields.new,
  (row) =>
      (row.id, row.value).map((v0, v1) => models.Reading(id: v0, value: v1)),
);

final class ReadingTableSet extends TableSet<models.Reading, ReadingFields> {
  ReadingTableSet(QueryContext db) : super(db, readingTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Reading> create({required int id, required double value}) =>
      createRow((row) => [row.id.set(id), row.value.set(value)]);
  Query<models.Reading, ReadingFields> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

extension ReadingUpdates on Query<models.Reading, ReadingFields> {
  Future<int> patch({
    Change<int> id = const Change.keep(),
    Change<double> value = const Change.keep(),
  }) =>
      update((row) => [...row.id.change(id), ...row.value.change(value)])
          .execute();
}

final appSchema = List<TableSchema>.unmodifiable([
  accountSchema,
  entrySchema,
  readingSchema,
]);

extension AppTables on QueryContext {
  AccountTableSet get account => AccountTableSet(this);
  EntryTableSet get entry => EntryTableSet(this);
  ReadingTableSet get reading => ReadingTableSet(this);
}
