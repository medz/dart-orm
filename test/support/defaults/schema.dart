import 'package:orm/schema.dart';

import 'types.dart' as d;

final Model ticket = model("tickets", (
  id: custom(d.TicketId.codec, clientDefault: d.nextId),
  name: text(clientDefault: d.nameFactory),
  label: text().nullable(clientDefault: d.empty<String>),
  state: text(defaultSql: "'server'", clientDefault: d.Defaults.state),
  createdAt: dateTime(clientDefault: DateTime.now),
), primaryKey: (r) => r.id);

final Model sequenceRow = model("sequences", (
  id: integer(clientDefault: d.clientIdentity).identity(),
));
