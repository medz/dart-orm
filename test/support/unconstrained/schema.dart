import 'package:orm/schema.dart';

typedef Account = ({
  int tenant,
  int id,
  @ColumnName('display_label') String? label,
  int? managerId,
});
typedef Entry = ({
  @Id() int id,
  int? tenant,
  int? owner,
  @ColumnName('lookup_label') String? label,
});
typedef Reading = ({@Id() int id, double value});

final accounts = entity<Account>();
final entries = entity<Entry>();
final readings = entity<Reading>();
final accountKey = accounts.primaryKey((a) => (a.tenant, a.id));
final ownerAccount = entries
    .key((e) => (e.tenant, e.owner))
    .relatesTo(accounts.key((a) => (a.tenant, a.id)), inverse: 'entries');
final matchingAccounts = entries
    .key((e) => (e.tenant, e.label))
    .relatesTo(accounts.key((a) => (a.tenant, a.label)), inverse: 'matches');
final manager = accounts
    .key((a) => (a.tenant, a.managerId))
    .relatesTo(accounts.key((a) => (a.tenant, a.id)), inverse: 'reports');
final peers = readings
    .key((r) => r.value)
    .relatesTo(readings.key((r) => r.value));
