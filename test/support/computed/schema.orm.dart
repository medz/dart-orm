// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';

/// A complete immutable row from "lines".
final class Line({
  required final int id,
  required final int price,
  required final int quantity,
  required final String label,
  required final String? note,
  required final int total,
  required final int labelSize,
  required final String? normalizedNote,
});
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
  Relation<Band, BandFields> get band =>
      Relation(bandTable, parent: [total], child: (row) => [row.id]);
}

final lineTable = Table<Line, LineFields>(
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
        (left, right) => Line(
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

final class LineTableSet extends TableSet<Line, LineFields> {
  LineTableSet(QueryContext db) : super(db, lineTable) {
    db.registerSchema(appSchema);
  }
  Future<Line> create({
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
  Query<Line, LineFields> byId(int id) => where((row) => row.id.eq(.value(id)));
}

extension LineUpdates on Query<Line, LineFields> {
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

/// A complete immutable row from "bands".
final class Band({required final int id, required final String name});
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
  Relation<Line, LineFields> get lines =>
      Relation(lineTable, parent: [id], child: (row) => [row.total]);
}

final bandTable = Table<Band, BandFields>(
  bandSchema,
  BandFields.new,
  (row) => (row.id, row.name).map((v0, v1) => Band(id: v0, name: v1)),
);

final class BandTableSet extends TableSet<Band, BandFields> {
  BandTableSet(QueryContext db) : super(db, bandTable) {
    db.registerSchema(appSchema);
  }
  Future<Band> create({required int id, required String name}) =>
      createRow((row) => [row.id.set(id), row.name.set(name)]);
  Query<Band, BandFields> byId(int id) => where((row) => row.id.eq(.value(id)));
}

extension BandUpdates on Query<Band, BandFields> {
  Future<int> patch({
    Change<int> id = const Change.keep(),
    Change<String> name = const Change.keep(),
  }) =>
      update((row) => [...row.id.change(id), ...row.name.change(name)])
          .execute();
}

final appSchema = List<TableSchema>.unmodifiable([lineSchema, bandSchema]);

extension AppTables on QueryContext {
  LineTableSet get line => LineTableSet(this);
  BandTableSet get band => BandTableSet(this);
}
