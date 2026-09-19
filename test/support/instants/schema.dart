import 'package:orm/schema.dart';

typedef Event = ({
  @Id.generated() int id,
  DateTime at,
  @Default.sql('CURRENT_TIMESTAMP') DateTime created,
  DateTime? optional,
});
typedef Moment = ({@Id() DateTime at, @Default.sql("'pending'") String label});
typedef Link = ({@Id.generated() int id, DateTime at});
final events = entity<Event>();
final moments = entity<Moment>();
final links = entity<Link>();
final moment = links
    .key((l) => l.at)
    .references(moments.key((m) => m.at), inverse: 'links');
