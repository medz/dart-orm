// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/orm.dart';

import "schema.dart" as models;

final _linesId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _linesPrice = Column<int>(
  "price",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _linesQuantity = Column<int>(
  "quantity",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _linesLabel = Column<String>(
  "label",
  Codecs.text,
  nullable: false,
  generated: false,
);
final _linesNote = Column<String?>(
  "note",
  Codecs.text.nullable(),
  nullable: true,
  generated: false,
);
final _linesTotal = Column<int>(
  "total",
  Codecs.integer,
  nullable: false,
  generated: false,
  computed: ComputedColumn.forDialects(
    sqlite: "price * quantity",
    postgres: "price * quantity",
    storage: ComputedStorage.stored,
  ),
);
final _linesLabelSize = Column<int>(
  "label_size",
  Codecs.integer,
  nullable: false,
  generated: false,
  computed: ComputedColumn.forDialects(
    sqlite: "length(label)",
    postgres: "char_length(label)",
    storage: ComputedStorage.virtual,
  ),
);
final _linesNormalizedNote = Column<String?>(
  "normalized_note",
  Codecs.text.nullable(),
  nullable: true,
  generated: false,
  computed: ComputedColumn.forDialects(
    sqlite: "upper(note)",
    postgres: "upper(note)",
    storage: ComputedStorage.stored,
  ),
);
final linesSchema = TableSchema(
  "lines",
  columns: [
    _linesId,
    _linesPrice,
    _linesQuantity,
    _linesLabel,
    _linesNote,
    _linesTotal,
    _linesLabelSize,
    _linesNormalizedNote,
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
    ),
  ],
  foreignKeys: [],
);

final class LinesFields extends Fields {
  LinesFields(super.table);
  late final id = column(_linesId);
  late final price = column(_linesPrice);
  late final quantity = column(_linesQuantity);
  late final label = column(_linesLabel);
  late final note = column(_linesNote);
  late final total = readColumn(_linesTotal);
  late final labelSize = readColumn(_linesLabelSize);
  late final normalizedNote = readColumn(_linesNormalizedNote);

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Band, BandsFields> get band =>
      Relation(bandsTable, parent: [total], child: (row) => [row.id]);
}

final linesTable = Table<models.Line, LinesFields>(
  linesSchema,
  LinesFields.new,
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
        (left, right) => (
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

final class LinesTableSet extends TableSet<models.Line, LinesFields> {
  LinesTableSet(Database<Backend> db) : super(db, linesTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Line> create({
    Change<int> id = const Change.keep(),
    required int price,
    required int quantity,
    required String label,
    String? note,
  }) => createRow(
    (row) => [
      ...row.id.change(id),
      row.price.set(price),
      row.quantity.set(quantity),
      row.label.set(label),
      row.note.set(note),
    ],
  );
  Query<models.Line, LinesFields> byId(int id) => where((row) => row.id.eq(id));
}

extension LinesUpdates on Query<models.Line, LinesFields> {
  Future<int> patch({
    Change<int> price = const Change.keep(),
    Change<int> quantity = const Change.keep(),
    Change<String> label = const Change.keep(),
    Change<String?> note = const Change.keep(),
  }) => update(
    (row) => [
      ...row.price.change(price),
      ...row.quantity.change(quantity),
      ...row.label.change(label),
      ...row.note.change(note),
    ],
  ).execute();
}

final _bandsId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _bandsName = Column<String>(
  "name",
  Codecs.text,
  nullable: false,
  generated: false,
);
final bandsSchema = TableSchema(
  "bands",
  columns: [_bandsId, _bandsName],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class BandsFields extends Fields {
  BandsFields(super.table);
  late final id = column(_bandsId);
  late final name = column(_bandsName);

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Line, LinesFields> get lines =>
      Relation(linesTable, parent: [id], child: (row) => [row.total]);
}

final bandsTable = Table<models.Band, BandsFields>(
  bandsSchema,
  BandsFields.new,
  (row) => (row.id, row.name).map((id, name) => (id: id, name: name)),
);

final class BandsTableSet extends TableSet<models.Band, BandsFields> {
  BandsTableSet(Database<Backend> db) : super(db, bandsTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Band> create({required int id, required String name}) =>
      createRow((row) => [row.id.set(id), row.name.set(name)]);
  Query<models.Band, BandsFields> byId(int id) => where((row) => row.id.eq(id));
}

extension BandsUpdates on Query<models.Band, BandsFields> {
  Future<int> patch({
    Change<int> id = const Change.keep(),
    Change<String> name = const Change.keep(),
  }) =>
      update((row) => [...row.id.change(id), ...row.name.change(name)])
          .execute();
}

final appSchema = <TableSchema>[linesSchema, bandsSchema];

extension AppTables<B extends Backend> on Database<B> {
  LinesTableSet get lines => LinesTableSet(this);
  BandsTableSet get bands => BandsTableSet(this);
}
