// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/orm.dart' as orm_model show ModelTable, ModelQuery;
import 'package:orm/values.dart';
import 'package:orm/sql.dart' as orm show allOf;

import "schema.dart" as models;
export "schema.dart" show Account, Entry, Reading;

final class _OrmWriteAbsent {
  const _OrmWriteAbsent();
}

const _writeAbsent = _OrmWriteAbsent();
WriteValue<T, F> _writeLiteral<T, F extends Fields>(Object? value) =>
    identical(value, _writeAbsent) ? const .keep() : .set(value as T);

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

/// Immutable input data; composition belongs to [accountPatch], not field names.
final class AccountPatch {
  final WriteValue<int, AccountFields> tenant;
  final WriteValue<int, AccountFields> id;
  final WriteValue<String?, AccountFields> label;
  final WriteValue<int?, AccountFields> managerId;
  AccountPatch._({
    required this.tenant,
    required this.id,
    required this.label,
    required this.managerId,
  });

  List<Assignment> _assignments(AccountFields fields) => [
    ...fields.tenant.write(tenant, fields),
    ...fields.id.write(id, fields),
    ...fields.label.write(label, fields),
    ...fields.managerId.write(managerId, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class AccountPatchFactory {
  AccountPatch call({int tenant, int id, String? label, int? managerId});
  AccountPatch values({
    WriteValue<int, AccountFields> tenant = const .keep(),
    WriteValue<int, AccountFields> id = const .keep(),
    WriteValue<String?, AccountFields> label = const .keep(),
    WriteValue<int?, AccountFields> managerId = const .keep(),
  });
  AccountPatch overlay(Iterable<AccountPatch> layers);
  bool isEmpty(AccountPatch input);
}

const AccountPatchFactory accountPatch = _AccountPatchFactory();

final class _AccountPatchFactory implements AccountPatchFactory {
  const _AccountPatchFactory();
  @override
  AccountPatch call({
    Object? tenant = _writeAbsent,
    Object? id = _writeAbsent,
    Object? label = _writeAbsent,
    Object? managerId = _writeAbsent,
  }) => AccountPatch._(
    tenant: _writeLiteral<int, AccountFields>(tenant),
    id: _writeLiteral<int, AccountFields>(id),
    label: _writeLiteral<String?, AccountFields>(label),
    managerId: _writeLiteral<int?, AccountFields>(managerId),
  );
  @override
  AccountPatch values({
    WriteValue<int, AccountFields> tenant = const .keep(),
    WriteValue<int, AccountFields> id = const .keep(),
    WriteValue<String?, AccountFields> label = const .keep(),
    WriteValue<int?, AccountFields> managerId = const .keep(),
  }) => AccountPatch._(
    tenant: tenant,
    id: id,
    label: label,
    managerId: managerId,
  );
  @override
  AccountPatch overlay(Iterable<AccountPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = AccountPatch._(
        tenant: WriteValue.overlay(earlier.tenant, later.tenant),
        id: WriteValue.overlay(earlier.id, later.id),
        label: WriteValue.overlay(earlier.label, later.label),
        managerId: WriteValue.overlay(earlier.managerId, later.managerId),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(AccountPatch input) =>
      input.tenant.isMissing &&
      input.id.isMissing &&
      input.label.isMissing &&
      input.managerId.isMissing;
}

/// Immutable input data; composition belongs to [accountInsert], not field names.
final class AccountInsert {
  final WriteValue<int, AccountFields> tenant;
  final WriteValue<int, AccountFields> id;
  final WriteValue<String?, AccountFields> label;
  final WriteValue<int?, AccountFields> managerId;
  AccountInsert._({
    required this.tenant,
    required this.id,
    required this.label,
    required this.managerId,
  }) {
    if (tenant.isMissing) {
      throw ArgumentError.value(tenant, 'tenant', 'Must be supplied.');
    }
    if (id.isMissing) {
      throw ArgumentError.value(id, 'id', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(AccountFields fields) => [
    ...fields.tenant.write(tenant, fields),
    ...fields.id.write(id, fields),
    ...fields.label.write(label, fields),
    ...fields.managerId.write(managerId, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class AccountInsertFactory {
  AccountInsert call({
    required int tenant,
    required int id,
    String? label,
    int? managerId,
  });
  AccountInsert values({
    required WriteValue<int, AccountFields> tenant,
    required WriteValue<int, AccountFields> id,
    WriteValue<String?, AccountFields> label = const .keep(),
    WriteValue<int?, AccountFields> managerId = const .keep(),
  });
  AccountInsert overlay(AccountInsert earlier, Iterable<AccountPatch> layers);
}

const AccountInsertFactory accountInsert = _AccountInsertFactory();

final class _AccountInsertFactory implements AccountInsertFactory {
  const _AccountInsertFactory();
  @override
  AccountInsert call({
    required int tenant,
    required int id,
    Object? label = _writeAbsent,
    Object? managerId = _writeAbsent,
  }) => AccountInsert._(
    tenant: .set(tenant),
    id: .set(id),
    label: _writeLiteral<String?, AccountFields>(label),
    managerId: _writeLiteral<int?, AccountFields>(managerId),
  );
  @override
  AccountInsert values({
    required WriteValue<int, AccountFields> tenant,
    required WriteValue<int, AccountFields> id,
    WriteValue<String?, AccountFields> label = const .keep(),
    WriteValue<int?, AccountFields> managerId = const .keep(),
  }) => AccountInsert._(
    tenant: tenant,
    id: id,
    label: label,
    managerId: managerId,
  );
  @override
  AccountInsert overlay(AccountInsert earlier, Iterable<AccountPatch> layers) {
    for (final later in layers) {
      earlier = AccountInsert._(
        tenant: WriteValue.overlay(earlier.tenant, later.tenant),
        id: WriteValue.overlay(earlier.id, later.id),
        label: WriteValue.overlay(earlier.label, later.label),
        managerId: WriteValue.overlay(earlier.managerId, later.managerId),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Account from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class AccountCreator {
  Future<models.Account> call({
    required int tenant,
    required int id,
    String? label,
    int? managerId,
  });
}

final class _AccountCreator implements AccountCreator {
  final AccountTableSet _table;
  const _AccountCreator(this._table);
  @override
  Future<models.Account> call({
    required int tenant,
    required int id,
    Object? label = _writeAbsent,
    Object? managerId = _writeAbsent,
  }) async => _table.plan
      .insert(
        AccountInsert._(
          tenant: .set(tenant),
          id: .set(id),
          label: _writeLiteral<String?, AccountFields>(label),
          managerId: _writeLiteral<int?, AccountFields>(managerId),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class AccountPatcher {
  Future<int> call({int tenant, int id, String? label, int? managerId});
}

final class _AccountPatcher implements AccountPatcher {
  final orm_model.ModelQuery<models.Account, AccountFields, AccountPatch>
  _query;
  const _AccountPatcher(this._query);
  @override
  Future<int> call({
    Object? tenant = _writeAbsent,
    Object? id = _writeAbsent,
    Object? label = _writeAbsent,
    Object? managerId = _writeAbsent,
  }) => _query.update(
    AccountPatch._(
      tenant: _writeLiteral<int, AccountFields>(tenant),
      id: _writeLiteral<int, AccountFields>(id),
      label: _writeLiteral<String?, AccountFields>(label),
      managerId: _writeLiteral<int?, AccountFields>(managerId),
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

  orm_model.ModelQuery<models.Account, AccountFields, AccountPatch> byId({
    required int tenant,
    required int id,
  }) => where(
    (row) => orm.allOf([row.tenant.eq(.value(tenant)), row.id.eq(.value(id))]),
  );
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

/// Immutable input data; composition belongs to [entryPatch], not field names.
final class EntryPatch {
  final WriteValue<int, EntryFields> id;
  final WriteValue<int?, EntryFields> tenant;
  final WriteValue<int?, EntryFields> owner;
  final WriteValue<String?, EntryFields> label;
  EntryPatch._({
    required this.id,
    required this.tenant,
    required this.owner,
    required this.label,
  });

  List<Assignment> _assignments(EntryFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.tenant.write(tenant, fields),
    ...fields.owner.write(owner, fields),
    ...fields.label.write(label, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class EntryPatchFactory {
  EntryPatch call({int id, int? tenant, int? owner, String? label});
  EntryPatch values({
    WriteValue<int, EntryFields> id = const .keep(),
    WriteValue<int?, EntryFields> tenant = const .keep(),
    WriteValue<int?, EntryFields> owner = const .keep(),
    WriteValue<String?, EntryFields> label = const .keep(),
  });
  EntryPatch overlay(Iterable<EntryPatch> layers);
  bool isEmpty(EntryPatch input);
}

const EntryPatchFactory entryPatch = _EntryPatchFactory();

final class _EntryPatchFactory implements EntryPatchFactory {
  const _EntryPatchFactory();
  @override
  EntryPatch call({
    Object? id = _writeAbsent,
    Object? tenant = _writeAbsent,
    Object? owner = _writeAbsent,
    Object? label = _writeAbsent,
  }) => EntryPatch._(
    id: _writeLiteral<int, EntryFields>(id),
    tenant: _writeLiteral<int?, EntryFields>(tenant),
    owner: _writeLiteral<int?, EntryFields>(owner),
    label: _writeLiteral<String?, EntryFields>(label),
  );
  @override
  EntryPatch values({
    WriteValue<int, EntryFields> id = const .keep(),
    WriteValue<int?, EntryFields> tenant = const .keep(),
    WriteValue<int?, EntryFields> owner = const .keep(),
    WriteValue<String?, EntryFields> label = const .keep(),
  }) => EntryPatch._(id: id, tenant: tenant, owner: owner, label: label);
  @override
  EntryPatch overlay(Iterable<EntryPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = EntryPatch._(
        id: WriteValue.overlay(earlier.id, later.id),
        tenant: WriteValue.overlay(earlier.tenant, later.tenant),
        owner: WriteValue.overlay(earlier.owner, later.owner),
        label: WriteValue.overlay(earlier.label, later.label),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(EntryPatch input) =>
      input.id.isMissing &&
      input.tenant.isMissing &&
      input.owner.isMissing &&
      input.label.isMissing;
}

/// Immutable input data; composition belongs to [entryInsert], not field names.
final class EntryInsert {
  final WriteValue<int, EntryFields> id;
  final WriteValue<int?, EntryFields> tenant;
  final WriteValue<int?, EntryFields> owner;
  final WriteValue<String?, EntryFields> label;
  EntryInsert._({
    required this.id,
    required this.tenant,
    required this.owner,
    required this.label,
  }) {
    if (id.isMissing) {
      throw ArgumentError.value(id, 'id', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(EntryFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.tenant.write(tenant, fields),
    ...fields.owner.write(owner, fields),
    ...fields.label.write(label, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class EntryInsertFactory {
  EntryInsert call({required int id, int? tenant, int? owner, String? label});
  EntryInsert values({
    required WriteValue<int, EntryFields> id,
    WriteValue<int?, EntryFields> tenant = const .keep(),
    WriteValue<int?, EntryFields> owner = const .keep(),
    WriteValue<String?, EntryFields> label = const .keep(),
  });
  EntryInsert overlay(EntryInsert earlier, Iterable<EntryPatch> layers);
}

const EntryInsertFactory entryInsert = _EntryInsertFactory();

final class _EntryInsertFactory implements EntryInsertFactory {
  const _EntryInsertFactory();
  @override
  EntryInsert call({
    required int id,
    Object? tenant = _writeAbsent,
    Object? owner = _writeAbsent,
    Object? label = _writeAbsent,
  }) => EntryInsert._(
    id: .set(id),
    tenant: _writeLiteral<int?, EntryFields>(tenant),
    owner: _writeLiteral<int?, EntryFields>(owner),
    label: _writeLiteral<String?, EntryFields>(label),
  );
  @override
  EntryInsert values({
    required WriteValue<int, EntryFields> id,
    WriteValue<int?, EntryFields> tenant = const .keep(),
    WriteValue<int?, EntryFields> owner = const .keep(),
    WriteValue<String?, EntryFields> label = const .keep(),
  }) => EntryInsert._(id: id, tenant: tenant, owner: owner, label: label);
  @override
  EntryInsert overlay(EntryInsert earlier, Iterable<EntryPatch> layers) {
    for (final later in layers) {
      earlier = EntryInsert._(
        id: WriteValue.overlay(earlier.id, later.id),
        tenant: WriteValue.overlay(earlier.tenant, later.tenant),
        owner: WriteValue.overlay(earlier.owner, later.owner),
        label: WriteValue.overlay(earlier.label, later.label),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Entry from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class EntryCreator {
  Future<models.Entry> call({
    required int id,
    int? tenant,
    int? owner,
    String? label,
  });
}

final class _EntryCreator implements EntryCreator {
  final EntryTableSet _table;
  const _EntryCreator(this._table);
  @override
  Future<models.Entry> call({
    required int id,
    Object? tenant = _writeAbsent,
    Object? owner = _writeAbsent,
    Object? label = _writeAbsent,
  }) async => _table.plan
      .insert(
        EntryInsert._(
          id: .set(id),
          tenant: _writeLiteral<int?, EntryFields>(tenant),
          owner: _writeLiteral<int?, EntryFields>(owner),
          label: _writeLiteral<String?, EntryFields>(label),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class EntryPatcher {
  Future<int> call({int id, int? tenant, int? owner, String? label});
}

final class _EntryPatcher implements EntryPatcher {
  final orm_model.ModelQuery<models.Entry, EntryFields, EntryPatch> _query;
  const _EntryPatcher(this._query);
  @override
  Future<int> call({
    Object? id = _writeAbsent,
    Object? tenant = _writeAbsent,
    Object? owner = _writeAbsent,
    Object? label = _writeAbsent,
  }) => _query.update(
    EntryPatch._(
      id: _writeLiteral<int, EntryFields>(id),
      tenant: _writeLiteral<int?, EntryFields>(tenant),
      owner: _writeLiteral<int?, EntryFields>(owner),
      label: _writeLiteral<String?, EntryFields>(label),
    ),
  );
}

/// Named literal updates on a complete models.Entry query.
extension EntryWrites
    on orm_model.ModelQuery<models.Entry, EntryFields, EntryPatch> {
  /// Executes one update; omitted fields remain unchanged.
  EntryPatcher get patch => _EntryPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class EntryTableSet
    extends
        orm_model.ModelTable<
          models.Entry,
          EntryFields,
          EntryInsert,
          EntryPatch
        > {
  EntryTableSet(QueryContext db)
    : super(
        db,
        entryTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final EntryCreator create = _EntryCreator(this);

  orm_model.ModelQuery<models.Entry, EntryFields, EntryPatch> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
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

/// Immutable input data; composition belongs to [readingPatch], not field names.
final class ReadingPatch {
  final WriteValue<int, ReadingFields> id;
  final WriteValue<double, ReadingFields> value;
  ReadingPatch._({required this.id, required this.value});

  List<Assignment> _assignments(ReadingFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.value.write(value, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class ReadingPatchFactory {
  ReadingPatch call({int id, double value});
  ReadingPatch values({
    WriteValue<int, ReadingFields> id = const .keep(),
    WriteValue<double, ReadingFields> value = const .keep(),
  });
  ReadingPatch overlay(Iterable<ReadingPatch> layers);
  bool isEmpty(ReadingPatch input);
}

const ReadingPatchFactory readingPatch = _ReadingPatchFactory();

final class _ReadingPatchFactory implements ReadingPatchFactory {
  const _ReadingPatchFactory();
  @override
  ReadingPatch call({
    Object? id = _writeAbsent,
    Object? value = _writeAbsent,
  }) => ReadingPatch._(
    id: _writeLiteral<int, ReadingFields>(id),
    value: _writeLiteral<double, ReadingFields>(value),
  );
  @override
  ReadingPatch values({
    WriteValue<int, ReadingFields> id = const .keep(),
    WriteValue<double, ReadingFields> value = const .keep(),
  }) => ReadingPatch._(id: id, value: value);
  @override
  ReadingPatch overlay(Iterable<ReadingPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = ReadingPatch._(
        id: WriteValue.overlay(earlier.id, later.id),
        value: WriteValue.overlay(earlier.value, later.value),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(ReadingPatch input) =>
      input.id.isMissing && input.value.isMissing;
}

/// Immutable input data; composition belongs to [readingInsert], not field names.
final class ReadingInsert {
  final WriteValue<int, ReadingFields> id;
  final WriteValue<double, ReadingFields> value;
  ReadingInsert._({required this.id, required this.value}) {
    if (id.isMissing) {
      throw ArgumentError.value(id, 'id', 'Must be supplied.');
    }
    if (value.isMissing) {
      throw ArgumentError.value(value, 'value', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(ReadingFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.value.write(value, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class ReadingInsertFactory {
  ReadingInsert call({required int id, required double value});
  ReadingInsert values({
    required WriteValue<int, ReadingFields> id,
    required WriteValue<double, ReadingFields> value,
  });
  ReadingInsert overlay(ReadingInsert earlier, Iterable<ReadingPatch> layers);
}

const ReadingInsertFactory readingInsert = _ReadingInsertFactory();

final class _ReadingInsertFactory implements ReadingInsertFactory {
  const _ReadingInsertFactory();
  @override
  ReadingInsert call({required int id, required double value}) =>
      ReadingInsert._(id: .set(id), value: .set(value));
  @override
  ReadingInsert values({
    required WriteValue<int, ReadingFields> id,
    required WriteValue<double, ReadingFields> value,
  }) => ReadingInsert._(id: id, value: value);
  @override
  ReadingInsert overlay(ReadingInsert earlier, Iterable<ReadingPatch> layers) {
    for (final later in layers) {
      earlier = ReadingInsert._(
        id: WriteValue.overlay(earlier.id, later.id),
        value: WriteValue.overlay(earlier.value, later.value),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Reading from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class ReadingCreator {
  Future<models.Reading> call({required int id, required double value});
}

final class _ReadingCreator implements ReadingCreator {
  final ReadingTableSet _table;
  const _ReadingCreator(this._table);
  @override
  Future<models.Reading> call({required int id, required double value}) async =>
      _table.plan
          .insert(ReadingInsert._(id: .set(id), value: .set(value)))
          .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class ReadingPatcher {
  Future<int> call({int id, double value});
}

final class _ReadingPatcher implements ReadingPatcher {
  final orm_model.ModelQuery<models.Reading, ReadingFields, ReadingPatch>
  _query;
  const _ReadingPatcher(this._query);
  @override
  Future<int> call({Object? id = _writeAbsent, Object? value = _writeAbsent}) =>
      _query.update(
        ReadingPatch._(
          id: _writeLiteral<int, ReadingFields>(id),
          value: _writeLiteral<double, ReadingFields>(value),
        ),
      );
}

/// Named literal updates on a complete models.Reading query.
extension ReadingWrites
    on orm_model.ModelQuery<models.Reading, ReadingFields, ReadingPatch> {
  /// Executes one update; omitted fields remain unchanged.
  ReadingPatcher get patch => _ReadingPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class ReadingTableSet
    extends
        orm_model.ModelTable<
          models.Reading,
          ReadingFields,
          ReadingInsert,
          ReadingPatch
        > {
  ReadingTableSet(QueryContext db)
    : super(
        db,
        readingTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final ReadingCreator create = _ReadingCreator(this);

  orm_model.ModelQuery<models.Reading, ReadingFields, ReadingPatch> byId(
    int id,
  ) => where((row) => row.id.eq(.value(id)));
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
