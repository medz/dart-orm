import 'package:orm/schema.dart';

@Model(table: "lines")
@Index(["total"], name: "by_total", unique: false)
@Check(
  "price >= 0 AND quantity >= 0",
  name: "nonnegative",
  postgres: "price >= 0 AND quantity >= 0",
  mysql: "price >= 0 AND quantity >= 0",
  mariadb: "price >= 0 AND quantity >= 0",
)
@Relation(
  target: Band,
  name: "band",
  fields: ["total"],
  keys: ["id"],
  constraint: false,
)
final class Line({
  @Id(generated: true) @Column(name: "id") required final int id,
  @Column(name: "price") required final int price,
  @Column(name: "quantity") required final int quantity,
  @Column(name: "label") required final String label,
  @Column(name: "note") required final String? note,
  @Column(name: "total")
  @Computed(
    "price * quantity",
    postgres: "price * quantity",
    mysql: "price * quantity",
    mariadb: "price * quantity",
    storage: .stored,
  )
  required final int total,
  @Column(name: "label_size")
  @Computed(
    "length(label)",
    postgres: "char_length(label)",
    mysql: "length(label)",
    mariadb: "length(label)",
    storage: .virtual,
  )
  required final int labelSize,
  @Column(name: "normalized_note")
  @Computed(
    "upper(note)",
    postgres: "upper(note)",
    mysql: "upper(note)",
    mariadb: "upper(note)",
    storage: .stored,
  )
  required final String? normalizedNote,
});

@Model(table: "bands")
@Relation(
  target: Line,
  name: "lines",
  fields: ["id"],
  keys: ["total"],
  constraint: false,
)
final class Band({
  @Id(generated: false) @Column(name: "id") required final int id,
  @Column(name: "name") required final String name,
});
