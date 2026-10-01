import 'package:orm/schema.dart';

int markerCalls = 0;
int instantCalls = 0;

String nextMarker() => 'marker-${++markerCalls}';

DateTime nextInstant() {
  instantCalls++;
  return DateTime.now().toUtc();
}

@Model()
final class User({
  @Id(generated: true) required final int id,
  @Unique() required final String email,
  @Column(name: 'display_name') final String name = 'Anonymous',
  final String? nickname = 'guest',
  @DatabaseDefault(true) final bool active = false,
  @ClientDefault(nextMarker)
  @DatabaseDefault('server-marker')
  final String marker = 'constructor-marker',
  final int score = 7,
  @Ignore() final String localLabel = 'local-only',
}) {
  String greeting() => 'Hello, $name';
}

@Model(table: 'posts')
@Index(['authorId', 'createdAt'], name: 'posts_author_created')
final class Post({
  @Id(generated: true) required final int id,
  @Relation(
    target: User,
    name: 'author',
    key: 'id',
    inverse: 'posts',
    onDelete: .cascade,
  )
  required final int authorId,
  required final String title,
  @ClientDefault(nextInstant) required final DateTime createdAt,
  @DatabaseDefault.sql("'draft'") final String status = 'constructor-status',
}) {
  String summary() => '$title ($status)';
}
