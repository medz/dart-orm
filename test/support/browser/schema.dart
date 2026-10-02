import 'package:orm/values.dart';

import 'dart:typed_data';

import 'package:orm/schema.dart';

int nicknameCalls = 0;

String? defaultNickname() {
  nicknameCalls++;
  return 'guest';
}

@Model(table: "users")
@Unique(["email"])
@Check(
  "length(email) > 0",
  name: "valid_email",
  postgres: "length(email) > 0",
  mysql: "length(email) > 0",
  mariadb: "length(email) > 0",
)
@Relation(
  target: Post,
  name: "posts",
  fields: ["id"],
  keys: ["authorId"],
  constraint: false,
)
final class User({
  @Id(generated: true) @Column(name: "id") required final int id,
  @Column(name: "email") required final String email,
  @Column(name: "nickname")
  @ClientDefault(defaultNickname)
  required final String? nickname,
  @Column(name: "email_size")
  @Computed(
    "length(email)",
    postgres: "length(email)",
    mysql: "length(email)",
    mariadb: "length(email)",
    storage: .stored,
  )
  required final int emailSize,
  @Column(name: "upper_nickname")
  @Computed(
    "upper(nickname)",
    postgres: "upper(nickname)",
    mysql: "upper(nickname)",
    mariadb: "upper(nickname)",
    storage: .virtual,
  )
  required final String? upperNickname,
});

@Model(table: "posts")
@Relation(
  target: User,
  name: "author",
  fields: ["authorId"],
  keys: ["id"],
  onDelete: .cascade,
)
final class Post({
  @Id(generated: true) @Column(name: "id") required final int id,
  @Column(name: "author_id") required final int authorId,
  @Column(name: "title") required final String title,
});

@Model(table: "values")
final class Value({
  @Id(generated: true) @Column(name: "id") required final int id,
  @Column(name: "wide") required final BigInt wide,
  @Column(name: "bytes") required final Uint8List bytes,
  @Column(name: "amount") required final Decimal amount,
  @Column(name: "day") required final LocalDate day,
  @Column(name: "time") required final LocalTime time,
  @Column(name: "stamp") required final LocalDateTime stamp,
  @Column(name: "instant") required final DateTime instant,
});

@Model(table: "readings")
@Relation(
  target: Reading,
  name: "peers",
  fields: ["value"],
  keys: ["value"],
  constraint: false,
)
@Relation(
  target: Reading,
  name: "sameReading",
  fields: ["id", "value"],
  keys: ["id", "value"],
  constraint: false,
)
final class Reading({
  @Id(generated: false) @Column(name: "id") required final int id,
  @Column(name: "value") required final double value,
});
