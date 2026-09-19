import 'package:orm/schema.dart';

import 'types.dart' as d;

typedef Ticket = ({
  @Id() @UseCodec(d.TicketId.codec) @ClientDefault(d.nextId) d.TicketId id,
  @ClientDefault(d.nameFactory) String name,
  @ClientDefault(d.empty<String>) String? label,
  @Default.sql("'server'") @ClientDefault(d.Defaults.state) String state,
  @ClientDefault(DateTime.now) DateTime createdAt,
});

final tickets = entity<Ticket>();

typedef SequenceRow = ({
  @Id.generated() @ClientDefault(d.clientIdentity) int id,
});
final sequences = entity<SequenceRow>();
