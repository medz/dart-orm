import 'dart:typed_data';

import 'package:orm/schema.dart';

typedef User = ({
  @Id.generated() int id,
  @Unique() String email,
  @ClientDefault(defaultNickname) String? nickname,
  @Computed.sql('length(email)') int emailSize,
  @Computed.sql('upper(nickname)', storage: ComputedStorage.virtual)
  String? upperNickname,
});
typedef Post = ({@Id.generated() int id, int authorId, String title});
typedef Reading = ({@Id() int id, double value});
typedef Value = ({
  @Id.generated() int id,
  BigInt wide,
  Uint8List bytes,
  Decimal amount,
  LocalDate day,
  LocalTime time,
  LocalDateTime stamp,
  DateTime instant,
});
final users = entity<User>();
final validEmail = users.check('length(email) > 0');
final posts = entity<Post>();
final values = entity<Value>();
final readings = entity<Reading>();
final peers = readings
    .key((r) => r.value)
    .relatesTo(readings.key((r) => r.value));
final sameReading = readings
    .key((r) => (r.value, r.id))
    .relatesTo(readings.key((r) => (r.value, r.id)));
final author = posts
    .key((p) => p.authorId)
    .references(users.key((u) => u.id), inverse: 'posts', onDelete: .cascade);

int nicknameCalls = 0;
String? defaultNickname() {
  nicknameCalls++;
  return 'guest';
}
