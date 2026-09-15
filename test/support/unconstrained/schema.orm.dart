// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/orm.dart';

import "schema.dart" as models;

final _accountsTenant = Column<int>(
  "tenant",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _accountsId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _accountsLabel = Column<String?>(
  "display_label",
  Codecs.text.nullable(),
  nullable: true,
  generated: false,
);
final _accountsManagerId = Column<int?>(
  "manager_id",
  Codecs.integer.nullable(),
  nullable: true,
  generated: false,
);
final accountsSchema = TableSchema(
  "accounts",
  columns: [_accountsTenant, _accountsId, _accountsLabel, _accountsManagerId],
  primaryKey: ["tenant", "id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class AccountsFields extends Fields {
  AccountsFields(super.table);
  late final tenant = column(_accountsTenant);
  late final id = column(_accountsId);
  late final label = column(_accountsLabel);
  late final managerId = column(_accountsManagerId);

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Entry, EntriesFields> get entries => Relation(
    entriesTable,
    parent: [tenant, id],
    child: (row) => [row.tenant, row.owner],
  );

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Entry, EntriesFields> get matches => Relation(
    entriesTable,
    parent: [tenant, label],
    child: (row) => [row.tenant, row.label],
  );

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Account, AccountsFields> get manager => Relation(
    accountsTable,
    parent: [tenant, managerId],
    child: (row) => [row.tenant, row.id],
  );

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Account, AccountsFields> get reports => Relation(
    accountsTable,
    parent: [tenant, id],
    child: (row) => [row.tenant, row.managerId],
  );
}

final accountsTable = Table<models.Account, AccountsFields>(
  accountsSchema,
  AccountsFields.new,
  (row) => (row.tenant, row.id, row.label, row.managerId).map(
    (tenant, id, label, managerId) =>
        (tenant: tenant, id: id, label: label, managerId: managerId),
  ),
);

final class AccountsTableSet extends TableSet<models.Account, AccountsFields> {
  AccountsTableSet(Database<Backend> db) : super(db, accountsTable) {
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
  Query<models.Account, AccountsFields> byId({
    required int tenant,
    required int id,
  }) => where((row) => row.tenant.eq(tenant).and(row.id.eq(id)));
}

extension AccountsUpdates on Query<models.Account, AccountsFields> {
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

final _entriesId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _entriesTenant = Column<int?>(
  "tenant",
  Codecs.integer.nullable(),
  nullable: true,
  generated: false,
);
final _entriesOwner = Column<int?>(
  "owner",
  Codecs.integer.nullable(),
  nullable: true,
  generated: false,
);
final _entriesLabel = Column<String?>(
  "lookup_label",
  Codecs.text.nullable(),
  nullable: true,
  generated: false,
);
final entriesSchema = TableSchema(
  "entries",
  columns: [_entriesId, _entriesTenant, _entriesOwner, _entriesLabel],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class EntriesFields extends Fields {
  EntriesFields(super.table);
  late final id = column(_entriesId);
  late final tenant = column(_entriesTenant);
  late final owner = column(_entriesOwner);
  late final label = column(_entriesLabel);

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Account, AccountsFields> get ownerAccount => Relation(
    accountsTable,
    parent: [tenant, owner],
    child: (row) => [row.tenant, row.id],
  );

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Account, AccountsFields> get matchingAccounts => Relation(
    accountsTable,
    parent: [tenant, label],
    child: (row) => [row.tenant, row.label],
  );
}

final entriesTable = Table<models.Entry, EntriesFields>(
  entriesSchema,
  EntriesFields.new,
  (row) => (row.id, row.tenant, row.owner, row.label).map(
    (id, tenant, owner, label) =>
        (id: id, tenant: tenant, owner: owner, label: label),
  ),
);

final class EntriesTableSet extends TableSet<models.Entry, EntriesFields> {
  EntriesTableSet(Database<Backend> db) : super(db, entriesTable) {
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
  Query<models.Entry, EntriesFields> byId(int id) =>
      where((row) => row.id.eq(id));
}

extension EntriesUpdates on Query<models.Entry, EntriesFields> {
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

final _readingsId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _readingsValue = Column<double>(
  "value",
  Codecs.real,
  nullable: false,
  generated: false,
);
final readingsSchema = TableSchema(
  "readings",
  columns: [_readingsId, _readingsValue],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class ReadingsFields extends Fields {
  ReadingsFields(super.table);
  late final id = column(_readingsId);
  late final value = column(_readingsValue);

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Reading, ReadingsFields> get peers =>
      Relation(readingsTable, parent: [value], child: (row) => [row.value]);
}

final readingsTable = Table<models.Reading, ReadingsFields>(
  readingsSchema,
  ReadingsFields.new,
  (row) => (row.id, row.value).map((id, value) => (id: id, value: value)),
);

final class ReadingsTableSet extends TableSet<models.Reading, ReadingsFields> {
  ReadingsTableSet(Database<Backend> db) : super(db, readingsTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Reading> create({required int id, required double value}) =>
      createRow((row) => [row.id.set(id), row.value.set(value)]);
  Query<models.Reading, ReadingsFields> byId(int id) =>
      where((row) => row.id.eq(id));
}

extension ReadingsUpdates on Query<models.Reading, ReadingsFields> {
  Future<int> patch({
    Change<int> id = const Change.keep(),
    Change<double> value = const Change.keep(),
  }) =>
      update((row) => [...row.id.change(id), ...row.value.change(value)])
          .execute();
}

final appSchema = <TableSchema>[accountsSchema, entriesSchema, readingsSchema];

extension AppTables<B extends Backend> on Database<B> {
  AccountsTableSet get accounts => AccountsTableSet(this);
  EntriesTableSet get entries => EntriesTableSet(this);
  ReadingsTableSet get readings => ReadingsTableSet(this);
}
