import 'package:orm/schema.dart';

typedef Note = ({
  @Id.generated() int id,
  @ColumnName('body') String text,
  @Default.sql('false') bool done,
  DateTime createdAt,
});
typedef Comment = ({@Id.generated() int id, int noteId, String text});

final notes = entity<Note>(table: 'notes');
final comments = entity<Comment>(table: 'comments');
final note = comments
    .key((c) => c.noteId)
    .references(
      notes.key((n) => n.id),
      inverse: 'comments',
      onDelete: .cascade,
    );
