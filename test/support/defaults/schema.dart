import 'package:orm/schema.dart';

import 'types.dart' as d;

@Model(table: "tickets")
final class Ticket({
  @Id(generated: false)
  @Column(name: "id", codec: d.TicketId.codec)
  @ClientDefault(d.nextId)
  required final d.TicketId id,
  @Column(name: "name")
  @ClientDefault(d.nameFactory)
  required final String name,
  @Column(name: "label")
  @ClientDefault(d.empty<String>)
  required final String? label,
  @Column(name: "state")
  @DatabaseDefault.sql("'server'")
  @ClientDefault(d.Defaults.state)
  required final String state,
  @Column(name: "created_at")
  @ClientDefault(DateTime.now)
  required final DateTime createdAt,
});

@Model(table: "sequences")
final class SequenceRow({
  @Id(generated: true)
  @Column(name: "id")
  @ClientDefault(d.clientIdentity)
  required final int id,
});
