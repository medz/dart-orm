import 'package:orm/orm.dart';

int idCalls = 0,
    nameCalls = 0,
    stateCalls = 0,
    nullCalls = 0,
    identityCalls = 0;
bool failName = false;
void reset() {
  idCalls = nameCalls = stateCalls = nullCalls = identityCalls = 0;
  failName = false;
}

extension type const TicketId(int value) {
  static const codec = Codec<TicketId>('integer', decode, encode);
  static TicketId decode(Object? raw) => TicketId(Codecs.integer.decode(raw));
  static Object? encode(TicketId id) => id.value;
}

TicketId nextId() => TicketId(++idCalls);
int clientIdentity() => 1000 + ++identityCalls;
String nextName() {
  nameCalls++;
  if (failName) throw StateError('factory failure');
  return 'ticket-$nameCalls';
}

const nameFactory = nextName;

final class Defaults {
  static String state([String prefix = 'client']) => '$prefix-${++stateCalls}';
}

T? empty<T>() {
  nullCalls++;
  return null;
}
