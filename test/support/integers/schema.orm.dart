// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';

/// A complete immutable row from "samples".
final class Sample({
  required final int id,
  required final int small,
  required final int medium,
  required final int large,
  required final int? optional,
});
final _sampleId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
  integerBits: 32,
);
final _sampleSmall = Column<int>(
  "small",
  Codecs.integer,
  nullable: false,
  generated: false,
  integerBits: 16,
);
final _sampleMedium = Column<int>(
  "medium",
  Codecs.integer,
  nullable: false,
  generated: false,
  integerBits: 32,
);
final _sampleLarge = Column<int>(
  "large",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _sampleOptional = Column<int?>(
  "optional",
  Codecs.integer.nullable(),
  nullable: true,
  generated: false,
  integerBits: 16,
);
final sampleSchema = TableSchema(
  "samples",
  columns: [
    _sampleId,
    _sampleSmall,
    _sampleMedium,
    _sampleLarge,
    _sampleOptional,
  ],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class SampleFields extends Fields {
  SampleFields(super.table);
  late final id = column(_sampleId);
  late final small = column(_sampleSmall);
  late final medium = column(_sampleMedium);
  late final large = column(_sampleLarge);
  late final optional = column(_sampleOptional);
  Relation<Owner, OwnerFields> get owners =>
      Relation(ownerTable, parent: [id], child: (row) => [row.sampleId]);
}

final sampleTable = Table<Sample, SampleFields>(
  sampleSchema,
  SampleFields.new,
  (row) => (row.id, row.small, row.medium, row.large, row.optional).map(
    (v0, v1, v2, v3, v4) =>
        Sample(id: v0, small: v1, medium: v2, large: v3, optional: v4),
  ),
);

final class SampleTableSet extends TableSet<Sample, SampleFields> {
  SampleTableSet(QueryContext db) : super(db, sampleTable) {
    db.registerSchema(appSchema);
  }
  Future<Sample> create({
    Change<int> id = const Change.keep(),
    required int small,
    required int medium,
    required int large,
    int? optional,
  }) => createRow(
    (row) => [
      ...row.id.change(id),
      row.small.set(small),
      row.medium.set(medium),
      row.large.set(large),
      row.optional.set(optional),
    ],
  );
  Query<Sample, SampleFields> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

extension SampleUpdates on Query<Sample, SampleFields> {
  Future<int> patch({
    Change<int> small = const Change.keep(),
    Change<int> medium = const Change.keep(),
    Change<int> large = const Change.keep(),
    Change<int?> optional = const Change.keep(),
  }) => update(
    (row) => [
      ...row.small.change(small),
      ...row.medium.change(medium),
      ...row.large.change(large),
      ...row.optional.change(optional),
    ],
  ).execute();
}

/// A complete immutable row from "owners".
final class Owner({required final int id, required final int sampleId});
final _ownerId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _ownerSampleId = Column<int>(
  "sample_id",
  Codecs.integer,
  nullable: false,
  generated: false,
  integerBits: 32,
);
final ownerSchema = TableSchema(
  "owners",
  columns: [_ownerId, _ownerSampleId],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [
    ForeignKey(["sample_id"], "samples", ["id"], onDelete: "RESTRICT"),
  ],
);

final class OwnerFields extends Fields {
  OwnerFields(super.table);
  late final id = column(_ownerId);
  late final sampleId = column(_ownerSampleId);
  Relation<Sample, SampleFields> get sample =>
      Relation(sampleTable, parent: [sampleId], child: (row) => [row.id]);
}

final ownerTable = Table<Owner, OwnerFields>(
  ownerSchema,
  OwnerFields.new,
  (row) => (row.id, row.sampleId).map((v0, v1) => Owner(id: v0, sampleId: v1)),
);

final class OwnerTableSet extends TableSet<Owner, OwnerFields> {
  OwnerTableSet(QueryContext db) : super(db, ownerTable) {
    db.registerSchema(appSchema);
  }
  Future<Owner> create({required int id, required int sampleId}) =>
      createRow((row) => [row.id.set(id), row.sampleId.set(sampleId)]);
  Query<Owner, OwnerFields> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

extension OwnerUpdates on Query<Owner, OwnerFields> {
  Future<int> patch({
    Change<int> id = const Change.keep(),
    Change<int> sampleId = const Change.keep(),
  }) =>
      update((row) => [...row.id.change(id), ...row.sampleId.change(sampleId)])
          .execute();
}

final appSchema = List<TableSchema>.unmodifiable([sampleSchema, ownerSchema]);

extension AppTables on QueryContext {
  SampleTableSet get sample => SampleTableSet(this);
  OwnerTableSet get owner => OwnerTableSet(this);
}
