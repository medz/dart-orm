import 'package:orm/schema.dart';

@Model(table: "notes")
final class Note({
  @Id(generated: true) @Column(name: "id") required final int id,
  @Column(name: "body") required final String body,
  @Column(name: "created_at") required final DateTime createdAt,
});
