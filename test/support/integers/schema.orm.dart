// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/orm.dart' as orm_model show ModelTable, ModelQuery;
import 'package:orm/values.dart';

import "schema.dart" as models;
export "schema.dart" show Sample, Owner;

final class _OrmWriteAbsent {
  const _OrmWriteAbsent();
}

const _writeAbsent = _OrmWriteAbsent();
WriteValue<T, F> _writeLiteral<T, F extends Fields>(Object? value) =>
    identical(value, _writeAbsent) ? const .keep() : .set(value as T);

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
  Relation<models.Sample, SampleFields> get sample =>
      Relation(sampleTable, parent: [sampleId], child: (row) => [row.id]);
}

final ownerTable = Table<models.Owner, OwnerFields>(
  ownerSchema,
  OwnerFields.new,
  (row) => (
    row.id,
    row.sampleId,
  ).map((v0, v1) => models.Owner(id: v0, sampleId: v1)),
);

/// Immutable input data; composition belongs to [ownerPatch], not field names.
final class OwnerPatch {
  final WriteValue<int, OwnerFields> id;
  final WriteValue<int, OwnerFields> sampleId;
  OwnerPatch._({required this.id, required this.sampleId});

  List<Assignment> _assignments(OwnerFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.sampleId.write(sampleId, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class OwnerPatchFactory {
  OwnerPatch call({int id, int sampleId});
  OwnerPatch values({
    WriteValue<int, OwnerFields> id = const .keep(),
    WriteValue<int, OwnerFields> sampleId = const .keep(),
  });
  OwnerPatch overlay(Iterable<OwnerPatch> layers);
  bool isEmpty(OwnerPatch input);
}

const OwnerPatchFactory ownerPatch = _OwnerPatchFactory();

final class _OwnerPatchFactory implements OwnerPatchFactory {
  const _OwnerPatchFactory();
  @override
  OwnerPatch call({
    Object? id = _writeAbsent,
    Object? sampleId = _writeAbsent,
  }) => OwnerPatch._(
    id: _writeLiteral<int, OwnerFields>(id),
    sampleId: _writeLiteral<int, OwnerFields>(sampleId),
  );
  @override
  OwnerPatch values({
    WriteValue<int, OwnerFields> id = const .keep(),
    WriteValue<int, OwnerFields> sampleId = const .keep(),
  }) => OwnerPatch._(id: id, sampleId: sampleId);
  @override
  OwnerPatch overlay(Iterable<OwnerPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = OwnerPatch._(
        id: WriteValue.overlay(earlier.id, later.id),
        sampleId: WriteValue.overlay(earlier.sampleId, later.sampleId),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(OwnerPatch input) =>
      input.id.isMissing && input.sampleId.isMissing;
}

/// Immutable input data; composition belongs to [ownerInsert], not field names.
final class OwnerInsert {
  final WriteValue<int, OwnerFields> id;
  final WriteValue<int, OwnerFields> sampleId;
  OwnerInsert._({required this.id, required this.sampleId}) {
    if (id.isMissing) {
      throw ArgumentError.value(id, 'id', 'Must be supplied.');
    }
    if (sampleId.isMissing) {
      throw ArgumentError.value(sampleId, 'sampleId', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(OwnerFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.sampleId.write(sampleId, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class OwnerInsertFactory {
  OwnerInsert call({required int id, required int sampleId});
  OwnerInsert values({
    required WriteValue<int, OwnerFields> id,
    required WriteValue<int, OwnerFields> sampleId,
  });
  OwnerInsert overlay(OwnerInsert earlier, Iterable<OwnerPatch> layers);
}

const OwnerInsertFactory ownerInsert = _OwnerInsertFactory();

final class _OwnerInsertFactory implements OwnerInsertFactory {
  const _OwnerInsertFactory();
  @override
  OwnerInsert call({required int id, required int sampleId}) =>
      OwnerInsert._(id: .set(id), sampleId: .set(sampleId));
  @override
  OwnerInsert values({
    required WriteValue<int, OwnerFields> id,
    required WriteValue<int, OwnerFields> sampleId,
  }) => OwnerInsert._(id: id, sampleId: sampleId);
  @override
  OwnerInsert overlay(OwnerInsert earlier, Iterable<OwnerPatch> layers) {
    for (final later in layers) {
      earlier = OwnerInsert._(
        id: WriteValue.overlay(earlier.id, later.id),
        sampleId: WriteValue.overlay(earlier.sampleId, later.sampleId),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Owner from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class OwnerCreator {
  Future<models.Owner> call({required int id, required int sampleId});
}

final class _OwnerCreator implements OwnerCreator {
  final OwnerTableSet _table;
  const _OwnerCreator(this._table);
  @override
  Future<models.Owner> call({required int id, required int sampleId}) async =>
      _table.plan
          .insert(OwnerInsert._(id: .set(id), sampleId: .set(sampleId)))
          .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class OwnerPatcher {
  Future<int> call({int id, int sampleId});
}

final class _OwnerPatcher implements OwnerPatcher {
  final orm_model.ModelQuery<models.Owner, OwnerFields, OwnerPatch> _query;
  const _OwnerPatcher(this._query);
  @override
  Future<int> call({
    Object? id = _writeAbsent,
    Object? sampleId = _writeAbsent,
  }) => _query.update(
    OwnerPatch._(
      id: _writeLiteral<int, OwnerFields>(id),
      sampleId: _writeLiteral<int, OwnerFields>(sampleId),
    ),
  );
}

/// Named literal updates on a complete models.Owner query.
extension OwnerWrites
    on orm_model.ModelQuery<models.Owner, OwnerFields, OwnerPatch> {
  /// Executes one update; omitted fields remain unchanged.
  OwnerPatcher get patch => _OwnerPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class OwnerTableSet
    extends
        orm_model.ModelTable<
          models.Owner,
          OwnerFields,
          OwnerInsert,
          OwnerPatch
        > {
  OwnerTableSet(QueryContext db)
    : super(
        db,
        ownerTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final OwnerCreator create = _OwnerCreator(this);

  orm_model.ModelQuery<models.Owner, OwnerFields, OwnerPatch> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

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

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Owner, OwnerFields> get owners =>
      Relation(ownerTable, parent: [id], child: (row) => [row.sampleId]);
}

final sampleTable = Table<models.Sample, SampleFields>(
  sampleSchema,
  SampleFields.new,
  (row) => (row.id, row.small, row.medium, row.large, row.optional).map(
    (v0, v1, v2, v3, v4) =>
        models.Sample(id: v0, small: v1, medium: v2, large: v3, optional: v4),
  ),
);

/// Immutable input data; composition belongs to [samplePatch], not field names.
final class SamplePatch {
  final WriteValue<int, SampleFields> small;
  final WriteValue<int, SampleFields> medium;
  final WriteValue<int, SampleFields> large;
  final WriteValue<int?, SampleFields> optional;
  SamplePatch._({
    required this.small,
    required this.medium,
    required this.large,
    required this.optional,
  });

  List<Assignment> _assignments(SampleFields fields) => [
    ...fields.small.write(small, fields),
    ...fields.medium.write(medium, fields),
    ...fields.large.write(large, fields),
    ...fields.optional.write(optional, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class SamplePatchFactory {
  SamplePatch call({int small, int medium, int large, int? optional});
  SamplePatch values({
    WriteValue<int, SampleFields> small = const .keep(),
    WriteValue<int, SampleFields> medium = const .keep(),
    WriteValue<int, SampleFields> large = const .keep(),
    WriteValue<int?, SampleFields> optional = const .keep(),
  });
  SamplePatch overlay(Iterable<SamplePatch> layers);
  bool isEmpty(SamplePatch input);
}

const SamplePatchFactory samplePatch = _SamplePatchFactory();

final class _SamplePatchFactory implements SamplePatchFactory {
  const _SamplePatchFactory();
  @override
  SamplePatch call({
    Object? small = _writeAbsent,
    Object? medium = _writeAbsent,
    Object? large = _writeAbsent,
    Object? optional = _writeAbsent,
  }) => SamplePatch._(
    small: _writeLiteral<int, SampleFields>(small),
    medium: _writeLiteral<int, SampleFields>(medium),
    large: _writeLiteral<int, SampleFields>(large),
    optional: _writeLiteral<int?, SampleFields>(optional),
  );
  @override
  SamplePatch values({
    WriteValue<int, SampleFields> small = const .keep(),
    WriteValue<int, SampleFields> medium = const .keep(),
    WriteValue<int, SampleFields> large = const .keep(),
    WriteValue<int?, SampleFields> optional = const .keep(),
  }) => SamplePatch._(
    small: small,
    medium: medium,
    large: large,
    optional: optional,
  );
  @override
  SamplePatch overlay(Iterable<SamplePatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = SamplePatch._(
        small: WriteValue.overlay(earlier.small, later.small),
        medium: WriteValue.overlay(earlier.medium, later.medium),
        large: WriteValue.overlay(earlier.large, later.large),
        optional: WriteValue.overlay(earlier.optional, later.optional),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(SamplePatch input) =>
      input.small.isMissing &&
      input.medium.isMissing &&
      input.large.isMissing &&
      input.optional.isMissing;
}

/// Immutable input data; composition belongs to [sampleInsert], not field names.
final class SampleInsert {
  final WriteValue<int, SampleFields> id;
  final WriteValue<int, SampleFields> small;
  final WriteValue<int, SampleFields> medium;
  final WriteValue<int, SampleFields> large;
  final WriteValue<int?, SampleFields> optional;
  SampleInsert._({
    required this.id,
    required this.small,
    required this.medium,
    required this.large,
    required this.optional,
  }) {
    if (small.isMissing) {
      throw ArgumentError.value(small, 'small', 'Must be supplied.');
    }
    if (medium.isMissing) {
      throw ArgumentError.value(medium, 'medium', 'Must be supplied.');
    }
    if (large.isMissing) {
      throw ArgumentError.value(large, 'large', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(SampleFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.small.write(small, fields),
    ...fields.medium.write(medium, fields),
    ...fields.large.write(large, fields),
    ...fields.optional.write(optional, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class SampleInsertFactory {
  SampleInsert call({
    int id,
    required int small,
    required int medium,
    required int large,
    int? optional,
  });
  SampleInsert values({
    WriteValue<int, SampleFields> id = const .keep(),
    required WriteValue<int, SampleFields> small,
    required WriteValue<int, SampleFields> medium,
    required WriteValue<int, SampleFields> large,
    WriteValue<int?, SampleFields> optional = const .keep(),
  });
  SampleInsert overlay(SampleInsert earlier, Iterable<SamplePatch> layers);
}

const SampleInsertFactory sampleInsert = _SampleInsertFactory();

final class _SampleInsertFactory implements SampleInsertFactory {
  const _SampleInsertFactory();
  @override
  SampleInsert call({
    Object? id = _writeAbsent,
    required int small,
    required int medium,
    required int large,
    Object? optional = _writeAbsent,
  }) => SampleInsert._(
    id: _writeLiteral<int, SampleFields>(id),
    small: .set(small),
    medium: .set(medium),
    large: .set(large),
    optional: _writeLiteral<int?, SampleFields>(optional),
  );
  @override
  SampleInsert values({
    WriteValue<int, SampleFields> id = const .keep(),
    required WriteValue<int, SampleFields> small,
    required WriteValue<int, SampleFields> medium,
    required WriteValue<int, SampleFields> large,
    WriteValue<int?, SampleFields> optional = const .keep(),
  }) => SampleInsert._(
    id: id,
    small: small,
    medium: medium,
    large: large,
    optional: optional,
  );
  @override
  SampleInsert overlay(SampleInsert earlier, Iterable<SamplePatch> layers) {
    for (final later in layers) {
      earlier = SampleInsert._(
        id: earlier.id,
        small: WriteValue.overlay(earlier.small, later.small),
        medium: WriteValue.overlay(earlier.medium, later.medium),
        large: WriteValue.overlay(earlier.large, later.large),
        optional: WriteValue.overlay(earlier.optional, later.optional),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Sample from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class SampleCreator {
  Future<models.Sample> call({
    int id,
    required int small,
    required int medium,
    required int large,
    int? optional,
  });
}

final class _SampleCreator implements SampleCreator {
  final SampleTableSet _table;
  const _SampleCreator(this._table);
  @override
  Future<models.Sample> call({
    Object? id = _writeAbsent,
    required int small,
    required int medium,
    required int large,
    Object? optional = _writeAbsent,
  }) async => _table.plan
      .insert(
        SampleInsert._(
          id: _writeLiteral<int, SampleFields>(id),
          small: .set(small),
          medium: .set(medium),
          large: .set(large),
          optional: _writeLiteral<int?, SampleFields>(optional),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class SamplePatcher {
  Future<int> call({int small, int medium, int large, int? optional});
}

final class _SamplePatcher implements SamplePatcher {
  final orm_model.ModelQuery<models.Sample, SampleFields, SamplePatch> _query;
  const _SamplePatcher(this._query);
  @override
  Future<int> call({
    Object? small = _writeAbsent,
    Object? medium = _writeAbsent,
    Object? large = _writeAbsent,
    Object? optional = _writeAbsent,
  }) => _query.update(
    SamplePatch._(
      small: _writeLiteral<int, SampleFields>(small),
      medium: _writeLiteral<int, SampleFields>(medium),
      large: _writeLiteral<int, SampleFields>(large),
      optional: _writeLiteral<int?, SampleFields>(optional),
    ),
  );
}

/// Named literal updates on a complete models.Sample query.
extension SampleWrites
    on orm_model.ModelQuery<models.Sample, SampleFields, SamplePatch> {
  /// Executes one update; omitted fields remain unchanged.
  SamplePatcher get patch => _SamplePatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class SampleTableSet
    extends
        orm_model.ModelTable<
          models.Sample,
          SampleFields,
          SampleInsert,
          SamplePatch
        > {
  SampleTableSet(QueryContext db)
    : super(
        db,
        sampleTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final SampleCreator create = _SampleCreator(this);

  orm_model.ModelQuery<models.Sample, SampleFields, SamplePatch> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

final appSchema = List<TableSchema>.unmodifiable([ownerSchema, sampleSchema]);

extension AppTables on QueryContext {
  OwnerTableSet get owner => OwnerTableSet(this);
  SampleTableSet get sample => SampleTableSet(this);
}
