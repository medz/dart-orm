/// Controlled authoring inputs, not additional supported ORM frontends.
const authoringSources = {
  'record':
      '''
import 'package:orm/schema.dart';
typedef User = ({@Id.generated() int id, int tenantId, @ColumnName('email') String email, String? nickname});
typedef Post = ({@Id.generated() int id, int tenantId, int authorId, String title, @Default.sql('false') bool published, DateTime createdAt});
typedef Profile = ({int tenantId, int userId, String? bio});
typedef Follow = ({int tenantId, int followerId, int followedId, DateTime createdAt});
$_constraints
''',
  'primary':
      '''
import 'package:orm/schema.dart';
final class User(@Id.generated() final int id, final int tenantId, @ColumnName('email') final String email, final String? nickname);
final class Post(@Id.generated() final int id, final int tenantId, final int authorId, final String title, @Default.sql('false') final bool published, final DateTime createdAt);
final class Profile(final int tenantId, final int userId, final String? bio);
final class Follow(final int tenantId, final int followerId, final int followedId, final DateTime createdAt);
$_constraints
''',
  'table':
      '''
import 'package:orm/schema.dart';
import 'package:orm/orm.dart';
final class User extends Fields {
  User(super.table);
  @Id.generated() late final id = column(Column('id', Codecs.integer));
  late final tenantId = column(Column('tenant_id', Codecs.integer));
  late final email = column(Column('email', Codecs.text));
  late final nickname = column(Column('nickname', Codecs.text.nullable(), nullable: true));
}
final class Post extends Fields {
  Post(super.table);
  @Id.generated() late final id = column(Column('id', Codecs.integer));
  late final tenantId = column(Column('tenant_id', Codecs.integer));
  late final authorId = column(Column('author_id', Codecs.integer));
  late final title = column(Column('title', Codecs.text));
  @Default.sql('false') late final published = column(Column('published', Codecs.boolean));
  late final createdAt = column(Column('created_at', Codecs.dateTime));
}
final class Profile extends Fields {
  Profile(super.table);
  late final tenantId = column(Column('tenant_id', Codecs.integer));
  late final userId = column(Column('user_id', Codecs.integer));
  late final bio = column(Column('bio', Codecs.text.nullable(), nullable: true));
}
final class Follow extends Fields {
  Follow(super.table);
  late final tenantId = column(Column('tenant_id', Codecs.integer));
  late final followerId = column(Column('follower_id', Codecs.integer));
  late final followedId = column(Column('followed_id', Codecs.integer));
  late final createdAt = column(Column('created_at', Codecs.dateTime));
}
$_constraints
''',
};

const _constraints = '''
final users = entity<User>(table: 'users');
final posts = entity<Post>(table: 'posts');
final profiles = entity<Profile>(table: 'profiles');
final follows = entity<Follow>(table: 'follows');
final userIdentity = users.unique((u) => (u.tenantId, u.id));
final userEmail = users.unique((u) => (u.tenantId, u.email));
final profileIdentity = profiles.primaryKey((p) => (p.tenantId, p.userId));
final followIdentity = follows.primaryKey((f) => (f.tenantId, f.followerId, f.followedId));
final author = posts.key((p) => (p.tenantId, p.authorId)).references(users.key((u) => (u.tenantId, u.id)), inverse: 'posts');
final profileOwner = profiles.key((p) => (p.tenantId, p.userId)).references(users.key((u) => (u.tenantId, u.id)), inverse: 'profile', onDelete: .cascade);
final follower = follows.key((f) => (f.tenantId, f.followerId)).references(users.key((u) => (u.tenantId, u.id)), inverse: 'following', onDelete: .cascade);
final followed = follows.key((f) => (f.tenantId, f.followedId)).references(users.key((u) => (u.tenantId, u.id)), inverse: 'followers', onDelete: .cascade);
final authorTimeline = posts.index((p) => (p.tenantId, p.authorId, p.createdAt, p.id));
final distinctUsers = follows.check('follower_id <> followed_id');
''';

const authoringConsumer = '''
import 'package:orm/orm.dart';
import 'schema.orm.dart';

Future<void> consume(Database<Backend> db) async {
  final user = await db.users.create(tenantId: 1, email: 'a@example.com');
  final String email = user.email;
  await db.users.byId(user.id).patch(nickname: .set('A'));
  final cards = await db.users.select((u) => (
    u.email,
    u.posts.take(3).select((p) => p.title).many(),
    u.profile.select((p) => p.bio).one(),
    u.following.select((f) => f.followed.select((u) => u.email).required()).many(),
  ).map((email, posts, bio, following) => (email: email, posts: posts, bio: bio, following: following))).get();
  final List<({String email, List<String> posts, String? bio, List<String> following})> typed = cards;
  print((email, typed));
}
''';
