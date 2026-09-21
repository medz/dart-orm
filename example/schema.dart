import 'package:orm/schema.dart';

final Model user = model('users', (
  id: identity(),
  email: text(unique: true),
  nickname: text().nullable(),
  score: integer(defaultValue: 0),
), relations: (u) => (posts: referencedBy(() => post)));

final post = model(
  'posts',
  (id: identity(), authorId: integer(), title: text(), createdAt: dateTime()),
  indexes: (p) => [
    index((p.authorId, p.createdAt, p.id), name: 'author_timeline'),
  ],
  relations: (p) =>
      (author: references(p.authorId, () => user, onDelete: .cascade)),
);
