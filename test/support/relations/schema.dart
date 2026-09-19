import 'package:orm/schema.dart';

typedef Account = ({
  int tenant,
  int id,
  String? label,
  String? note,
  int? managerId,
  @ColumnName('_ORM_PRESENT') String? marker,
});

typedef Event = ({
  @Id() int id,
  int? tenant,
  int? owner,
  int? reviewer,
  String title,
  int score,
});

final accounts = entity<Account>();
final events = entity<Event>();
final accountKey = accounts.primaryKey((a) => (a.tenant, a.id));
final manager = accounts
    .key((a) => (a.tenant, a.managerId))
    .references(accounts.key((a) => (a.tenant, a.id)), inverse: 'reports');
final author = events
    .key((e) => (e.tenant, e.owner))
    .references(accounts.key((a) => (a.tenant, a.id)), inverse: 'events');
final reviewerAccount = events
    .key((e) => (e.tenant, e.reviewer))
    .references(accounts.key((a) => (a.tenant, a.id)), inverse: 'reviews');
