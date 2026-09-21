import 'package:orm/schema.dart';

final Model note = model('notes', (
  id: identity(),
  text: text(name: 'body'),
  done: boolean(defaultValue: false),
  createdAt: dateTime(),
), relations: (n) => (comments: referencedBy(() => comment)));

final comment = model(
  'comments',
  (id: identity(), noteId: integer(), text: text()),
  relations: (c) =>
      (note: references(c.noteId, () => note, onDelete: .cascade)),
);
