// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/orm.dart';

import "schema.dart" as models;

final _samplesId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
  integerBits: 32,
);
final _samplesSmall = Column<int>(
  "small",
  Codecs.integer,
  nullable: false,
  generated: false,
  integerBits: 16,
);
final _samplesMedium = Column<int>(
  "medium",
  Codecs.integer,
  nullable: false,
  generated: false,
  integerBits: 32,
);
final _samplesLarge = Column<int>(
  "large",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _samplesOptional = Column<int?>(
  "optional",
  Codecs.integer.nullable(),
  nullable: true,
  generated: false,
  integerBits: 16,
);
final samplesSchema = TableSchema(
  "samples",
  columns: [
    _samplesId,
    _samplesSmall,
    _samplesMedium,
    _samplesLarge,
    _samplesOptional,
  ],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class SamplesFields extends Fields {
  SamplesFields(super.table);
  late final id = column(_samplesId);
  late final small = column(_samplesSmall);
  late final medium = column(_samplesMedium);
  late final large = column(_samplesLarge);
  late final optional = column(_samplesOptional);
  Relation<models.Owner, OwnersFields> get owners =>
      Relation(ownersTable, parent: [id], child: (row) => [row.sampleId]);
}

final samplesTable = Table<models.Sample, SamplesFields>(
  samplesSchema,
  SamplesFields.new,
  (row) => (row.id, row.small, row.medium, row.large, row.optional).map(
    (id, small, medium, large, optional) => (
      id: id,
      small: small,
      medium: medium,
      large: large,
      optional: optional,
    ),
  ),
);

final class SamplesTableSet extends TableSet<models.Sample, SamplesFields> {
  SamplesTableSet(Database<Backend> db) : super(db, samplesTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Sample> create({
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
  Query<models.Sample, SamplesFields> byId(int id) =>
      where((row) => row.id.eq(id));
}

extension SamplesUpdates on Query<models.Sample, SamplesFields> {
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

final _ownersId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _ownersSampleId = Column<int>(
  "sample_id",
  Codecs.integer,
  nullable: false,
  generated: false,
  integerBits: 32,
);
final ownersSchema = TableSchema(
  "owners",
  columns: [_ownersId, _ownersSampleId],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [
    ForeignKey(["sample_id"], "samples", ["id"], onDelete: "RESTRICT"),
  ],
);

final class OwnersFields extends Fields {
  OwnersFields(super.table);
  late final id = column(_ownersId);
  late final sampleId = column(_ownersSampleId);
  Relation<models.Sample, SamplesFields> get sample =>
      Relation(samplesTable, parent: [sampleId], child: (row) => [row.id]);
}

final ownersTable = Table<models.Owner, OwnersFields>(
  ownersSchema,
  OwnersFields.new,
  (row) => (
    row.id,
    row.sampleId,
  ).map((id, sampleId) => (id: id, sampleId: sampleId)),
);

final class OwnersTableSet extends TableSet<models.Owner, OwnersFields> {
  OwnersTableSet(Database<Backend> db) : super(db, ownersTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Owner> create({required int id, required int sampleId}) =>
      createRow((row) => [row.id.set(id), row.sampleId.set(sampleId)]);
  Query<models.Owner, OwnersFields> byId(int id) =>
      where((row) => row.id.eq(id));
}

extension OwnersUpdates on Query<models.Owner, OwnersFields> {
  Future<int> patch({
    Change<int> id = const Change.keep(),
    Change<int> sampleId = const Change.keep(),
  }) =>
      update((row) => [...row.id.change(id), ...row.sampleId.change(sampleId)])
          .execute();
}

final appSchema = <TableSchema>[samplesSchema, ownersSchema];

extension AppTables<B extends Backend> on Database<B> {
  SamplesTableSet get samples => SamplesTableSet(this);
  OwnersTableSet get owners => OwnersTableSet(this);
}
