// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/orm.dart' as orm_model show ModelTable, ModelQuery;
import 'package:orm/values.dart';

import "schema.dart" as models;
export "schema.dart" show Line, Band;

final class _OrmWriteAbsent {
  const _OrmWriteAbsent();
}

const _writeAbsent = _OrmWriteAbsent();
WriteValue<T, F> _writeLiteral<T, F extends Fields>(Object? value) =>
    identical(value, _writeAbsent) ? const .keep() : .set(value as T);

final _bandId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _bandName = Column<String>(
  "name",
  Codecs.text,
  nullable: false,
  generated: false,
);
final bandSchema = TableSchema(
  "bands",
  columns: [_bandId, _bandName],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class BandFields extends Fields {
  BandFields(super.table);
  late final id = column(_bandId);
  late final name = column(_bandName);

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Line, LineFields> get lines =>
      Relation(lineTable, parent: [id], child: (row) => [row.total]);
}

final bandTable = Table<models.Band, BandFields>(
  bandSchema,
  BandFields.new,
  (row) => (row.id, row.name).map((v0, v1) => models.Band(id: v0, name: v1)),
);

/// Immutable input data; composition belongs to [bandPatch], not field names.
final class BandPatch {
  final WriteValue<int, BandFields> id;
  final WriteValue<String, BandFields> name;
  BandPatch._({required this.id, required this.name});

  List<Assignment> _assignments(BandFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.name.write(name, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class BandPatchFactory {
  BandPatch call({int id, String name});
  BandPatch values({
    WriteValue<int, BandFields> id = const .keep(),
    WriteValue<String, BandFields> name = const .keep(),
  });
  BandPatch overlay(Iterable<BandPatch> layers);
  bool isEmpty(BandPatch input);
}

const BandPatchFactory bandPatch = _BandPatchFactory();

final class _BandPatchFactory implements BandPatchFactory {
  const _BandPatchFactory();
  @override
  BandPatch call({Object? id = _writeAbsent, Object? name = _writeAbsent}) =>
      BandPatch._(
        id: _writeLiteral<int, BandFields>(id),
        name: _writeLiteral<String, BandFields>(name),
      );
  @override
  BandPatch values({
    WriteValue<int, BandFields> id = const .keep(),
    WriteValue<String, BandFields> name = const .keep(),
  }) => BandPatch._(id: id, name: name);
  @override
  BandPatch overlay(Iterable<BandPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = BandPatch._(
        id: WriteValue.overlay(earlier.id, later.id),
        name: WriteValue.overlay(earlier.name, later.name),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(BandPatch input) => input.id.isMissing && input.name.isMissing;
}

/// Immutable input data; composition belongs to [bandInsert], not field names.
final class BandInsert {
  final WriteValue<int, BandFields> id;
  final WriteValue<String, BandFields> name;
  BandInsert._({required this.id, required this.name}) {
    if (id.isMissing) {
      throw ArgumentError.value(id, 'id', 'Must be supplied.');
    }
    if (name.isMissing) {
      throw ArgumentError.value(name, 'name', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(BandFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.name.write(name, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class BandInsertFactory {
  BandInsert call({required int id, required String name});
  BandInsert values({
    required WriteValue<int, BandFields> id,
    required WriteValue<String, BandFields> name,
  });
  BandInsert overlay(BandInsert earlier, Iterable<BandPatch> layers);
}

const BandInsertFactory bandInsert = _BandInsertFactory();

final class _BandInsertFactory implements BandInsertFactory {
  const _BandInsertFactory();
  @override
  BandInsert call({required int id, required String name}) =>
      BandInsert._(id: .set(id), name: .set(name));
  @override
  BandInsert values({
    required WriteValue<int, BandFields> id,
    required WriteValue<String, BandFields> name,
  }) => BandInsert._(id: id, name: name);
  @override
  BandInsert overlay(BandInsert earlier, Iterable<BandPatch> layers) {
    for (final later in layers) {
      earlier = BandInsert._(
        id: WriteValue.overlay(earlier.id, later.id),
        name: WriteValue.overlay(earlier.name, later.name),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Band from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class BandCreator {
  Future<models.Band> call({required int id, required String name});
}

final class _BandCreator implements BandCreator {
  final BandTableSet _table;
  const _BandCreator(this._table);
  @override
  Future<models.Band> call({required int id, required String name}) async =>
      _table.plan.insert(BandInsert._(id: .set(id), name: .set(name))).row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class BandPatcher {
  Future<int> call({int id, String name});
}

final class _BandPatcher implements BandPatcher {
  final orm_model.ModelQuery<models.Band, BandFields, BandPatch> _query;
  const _BandPatcher(this._query);
  @override
  Future<int> call({Object? id = _writeAbsent, Object? name = _writeAbsent}) =>
      _query.update(
        BandPatch._(
          id: _writeLiteral<int, BandFields>(id),
          name: _writeLiteral<String, BandFields>(name),
        ),
      );
}

/// Named literal updates on a complete models.Band query.
extension BandWrites
    on orm_model.ModelQuery<models.Band, BandFields, BandPatch> {
  /// Executes one update; omitted fields remain unchanged.
  BandPatcher get patch => _BandPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class BandTableSet
    extends
        orm_model.ModelTable<models.Band, BandFields, BandInsert, BandPatch> {
  BandTableSet(QueryContext db)
    : super(
        db,
        bandTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final BandCreator create = _BandCreator(this);

  orm_model.ModelQuery<models.Band, BandFields, BandPatch> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

final _lineId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _linePrice = Column<int>(
  "price",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _lineQuantity = Column<int>(
  "quantity",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _lineLabel = Column<String>(
  "label",
  Codecs.text,
  nullable: false,
  generated: false,
);
final _lineNote = Column<String?>(
  "note",
  Codecs.text.nullable(),
  nullable: true,
  generated: false,
);
final _lineTotal = Column<int>(
  "total",
  Codecs.integer,
  nullable: false,
  generated: false,
  computed: ComputedColumn.forDialects(
    sqlite: "price * quantity",
    postgres: "price * quantity",
    mysql: "price * quantity",
    mariadb: "price * quantity",
    storage: ComputedStorage.stored,
  ),
);
final _lineLabelSize = Column<int>(
  "label_size",
  Codecs.integer,
  nullable: false,
  generated: false,
  computed: ComputedColumn.forDialects(
    sqlite: "length(label)",
    postgres: "char_length(label)",
    mysql: "length(label)",
    mariadb: "length(label)",
    storage: ComputedStorage.virtual,
  ),
);
final _lineNormalizedNote = Column<String?>(
  "normalized_note",
  Codecs.text.nullable(),
  nullable: true,
  generated: false,
  computed: ComputedColumn.forDialects(
    sqlite: "upper(note)",
    postgres: "upper(note)",
    mysql: "upper(note)",
    mariadb: "upper(note)",
    storage: ComputedStorage.stored,
  ),
);
final lineSchema = TableSchema(
  "lines",
  columns: [
    _lineId,
    _linePrice,
    _lineQuantity,
    _lineLabel,
    _lineNote,
    _lineTotal,
    _lineLabelSize,
    _lineNormalizedNote,
  ],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [
    IndexSchema("by_total", ["total"], unique: false),
  ],
  checks: [
    CheckSchema.forDialects(
      "nonnegative",
      sqlite: "price >= 0 AND quantity >= 0",
      postgres: "price >= 0 AND quantity >= 0",
      mysql: "price >= 0 AND quantity >= 0",
      mariadb: "price >= 0 AND quantity >= 0",
    ),
  ],
  foreignKeys: [],
);

final class LineFields extends Fields {
  LineFields(super.table);
  late final id = column(_lineId);
  late final price = column(_linePrice);
  late final quantity = column(_lineQuantity);
  late final label = column(_lineLabel);
  late final note = column(_lineNote);
  late final total = readColumn(_lineTotal);
  late final labelSize = readColumn(_lineLabelSize);
  late final normalizedNote = readColumn(_lineNormalizedNote);

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Band, BandFields> get band =>
      Relation(bandTable, parent: [total], child: (row) => [row.id]);
}

final lineTable = Table<models.Line, LineFields>(
  lineSchema,
  LineFields.new,
  (row) =>
      (
        (row.id, row.price, row.quantity, row.label, row.note).map(
          (id, price, quantity, label, note) => (
            id: id,
            price: price,
            quantity: quantity,
            label: label,
            note: note,
          ),
        ),
        (row.total, row.labelSize, row.normalizedNote).map(
          (total, labelSize, normalizedNote) => (
            total: total,
            labelSize: labelSize,
            normalizedNote: normalizedNote,
          ),
        ),
      ).map(
        (left, right) => models.Line(
          id: left.id,
          price: left.price,
          quantity: left.quantity,
          label: left.label,
          note: left.note,
          total: right.total,
          labelSize: right.labelSize,
          normalizedNote: right.normalizedNote,
        ),
      ),
);

/// Immutable input data; composition belongs to [linePatch], not field names.
final class LinePatch {
  final WriteValue<int, LineFields> price;
  final WriteValue<int, LineFields> quantity;
  final WriteValue<String, LineFields> label;
  final WriteValue<String?, LineFields> note;
  LinePatch._({
    required this.price,
    required this.quantity,
    required this.label,
    required this.note,
  });

  List<Assignment> _assignments(LineFields fields) => [
    ...fields.price.write(price, fields),
    ...fields.quantity.write(quantity, fields),
    ...fields.label.write(label, fields),
    ...fields.note.write(note, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class LinePatchFactory {
  LinePatch call({int price, int quantity, String label, String? note});
  LinePatch values({
    WriteValue<int, LineFields> price = const .keep(),
    WriteValue<int, LineFields> quantity = const .keep(),
    WriteValue<String, LineFields> label = const .keep(),
    WriteValue<String?, LineFields> note = const .keep(),
  });
  LinePatch overlay(Iterable<LinePatch> layers);
  bool isEmpty(LinePatch input);
}

const LinePatchFactory linePatch = _LinePatchFactory();

final class _LinePatchFactory implements LinePatchFactory {
  const _LinePatchFactory();
  @override
  LinePatch call({
    Object? price = _writeAbsent,
    Object? quantity = _writeAbsent,
    Object? label = _writeAbsent,
    Object? note = _writeAbsent,
  }) => LinePatch._(
    price: _writeLiteral<int, LineFields>(price),
    quantity: _writeLiteral<int, LineFields>(quantity),
    label: _writeLiteral<String, LineFields>(label),
    note: _writeLiteral<String?, LineFields>(note),
  );
  @override
  LinePatch values({
    WriteValue<int, LineFields> price = const .keep(),
    WriteValue<int, LineFields> quantity = const .keep(),
    WriteValue<String, LineFields> label = const .keep(),
    WriteValue<String?, LineFields> note = const .keep(),
  }) => LinePatch._(price: price, quantity: quantity, label: label, note: note);
  @override
  LinePatch overlay(Iterable<LinePatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = LinePatch._(
        price: WriteValue.overlay(earlier.price, later.price),
        quantity: WriteValue.overlay(earlier.quantity, later.quantity),
        label: WriteValue.overlay(earlier.label, later.label),
        note: WriteValue.overlay(earlier.note, later.note),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(LinePatch input) =>
      input.price.isMissing &&
      input.quantity.isMissing &&
      input.label.isMissing &&
      input.note.isMissing;
}

/// Immutable input data; composition belongs to [lineInsert], not field names.
final class LineInsert {
  final WriteValue<int, LineFields> id;
  final WriteValue<int, LineFields> price;
  final WriteValue<int, LineFields> quantity;
  final WriteValue<String, LineFields> label;
  final WriteValue<String?, LineFields> note;
  LineInsert._({
    required this.id,
    required this.price,
    required this.quantity,
    required this.label,
    required this.note,
  }) {
    if (price.isMissing) {
      throw ArgumentError.value(price, 'price', 'Must be supplied.');
    }
    if (quantity.isMissing) {
      throw ArgumentError.value(quantity, 'quantity', 'Must be supplied.');
    }
    if (label.isMissing) {
      throw ArgumentError.value(label, 'label', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(LineFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.price.write(price, fields),
    ...fields.quantity.write(quantity, fields),
    ...fields.label.write(label, fields),
    ...fields.note.write(note, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class LineInsertFactory {
  LineInsert call({
    int id,
    required int price,
    required int quantity,
    required String label,
    String? note,
  });
  LineInsert values({
    WriteValue<int, LineFields> id = const .keep(),
    required WriteValue<int, LineFields> price,
    required WriteValue<int, LineFields> quantity,
    required WriteValue<String, LineFields> label,
    WriteValue<String?, LineFields> note = const .keep(),
  });
  LineInsert overlay(LineInsert earlier, Iterable<LinePatch> layers);
}

const LineInsertFactory lineInsert = _LineInsertFactory();

final class _LineInsertFactory implements LineInsertFactory {
  const _LineInsertFactory();
  @override
  LineInsert call({
    Object? id = _writeAbsent,
    required int price,
    required int quantity,
    required String label,
    Object? note = _writeAbsent,
  }) => LineInsert._(
    id: _writeLiteral<int, LineFields>(id),
    price: .set(price),
    quantity: .set(quantity),
    label: .set(label),
    note: _writeLiteral<String?, LineFields>(note),
  );
  @override
  LineInsert values({
    WriteValue<int, LineFields> id = const .keep(),
    required WriteValue<int, LineFields> price,
    required WriteValue<int, LineFields> quantity,
    required WriteValue<String, LineFields> label,
    WriteValue<String?, LineFields> note = const .keep(),
  }) => LineInsert._(
    id: id,
    price: price,
    quantity: quantity,
    label: label,
    note: note,
  );
  @override
  LineInsert overlay(LineInsert earlier, Iterable<LinePatch> layers) {
    for (final later in layers) {
      earlier = LineInsert._(
        id: earlier.id,
        price: WriteValue.overlay(earlier.price, later.price),
        quantity: WriteValue.overlay(earlier.quantity, later.quantity),
        label: WriteValue.overlay(earlier.label, later.label),
        note: WriteValue.overlay(earlier.note, later.note),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Line from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class LineCreator {
  Future<models.Line> call({
    int id,
    required int price,
    required int quantity,
    required String label,
    String? note,
  });
}

final class _LineCreator implements LineCreator {
  final LineTableSet _table;
  const _LineCreator(this._table);
  @override
  Future<models.Line> call({
    Object? id = _writeAbsent,
    required int price,
    required int quantity,
    required String label,
    Object? note = _writeAbsent,
  }) async => _table.plan
      .insert(
        LineInsert._(
          id: _writeLiteral<int, LineFields>(id),
          price: .set(price),
          quantity: .set(quantity),
          label: .set(label),
          note: _writeLiteral<String?, LineFields>(note),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class LinePatcher {
  Future<int> call({int price, int quantity, String label, String? note});
}

final class _LinePatcher implements LinePatcher {
  final orm_model.ModelQuery<models.Line, LineFields, LinePatch> _query;
  const _LinePatcher(this._query);
  @override
  Future<int> call({
    Object? price = _writeAbsent,
    Object? quantity = _writeAbsent,
    Object? label = _writeAbsent,
    Object? note = _writeAbsent,
  }) => _query.update(
    LinePatch._(
      price: _writeLiteral<int, LineFields>(price),
      quantity: _writeLiteral<int, LineFields>(quantity),
      label: _writeLiteral<String, LineFields>(label),
      note: _writeLiteral<String?, LineFields>(note),
    ),
  );
}

/// Named literal updates on a complete models.Line query.
extension LineWrites
    on orm_model.ModelQuery<models.Line, LineFields, LinePatch> {
  /// Executes one update; omitted fields remain unchanged.
  LinePatcher get patch => _LinePatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class LineTableSet
    extends
        orm_model.ModelTable<models.Line, LineFields, LineInsert, LinePatch> {
  LineTableSet(QueryContext db)
    : super(
        db,
        lineTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final LineCreator create = _LineCreator(this);

  orm_model.ModelQuery<models.Line, LineFields, LinePatch> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

final appSchema = List<TableSchema>.unmodifiable([bandSchema, lineSchema]);

extension AppTables on QueryContext {
  BandTableSet get band => BandTableSet(this);
  LineTableSet get line => LineTableSet(this);
}
