import 'package:orm/schema.dart';

@Model(table: "notes")
@Relation(
  target: Comment,
  name: "comments",
  fields: ["id"],
  keys: ["noteId"],
  constraint: false,
)
final class Note({
  @Id(generated: true) @Column(name: "id") required final int id,
  @Column(name: "body") required final String text,
  @Column(name: "done") @DatabaseDefault.sql("false") required final bool done,
  @Column(name: "created_at") required final DateTime createdAt,
});

@Model(table: "comments")
@Relation(
  target: Note,
  name: "note",
  fields: ["noteId"],
  keys: ["id"],
  onDelete: .cascade,
)
final class Comment({
  @Id(generated: true) @Column(name: "id") required final int id,
  @Column(name: "note_id") required final int noteId,
  @Column(name: "text") required final String text,
});
