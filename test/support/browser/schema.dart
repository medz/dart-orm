import 'package:orm/schema.dart';

int nicknameCalls = 0;

String? defaultNickname() {
  nicknameCalls++;
  return 'guest';
}

final Model user = model(
  "users",
  (
    id: integer().identity(),
    email: text(),
    nickname: text().nullable(clientDefault: defaultNickname),
    emailSize: integer().computed(
      "length(email)",
      postgres: "length(email)",
      mysql: "length(email)",
      mariadb: "length(email)",
      storage: .stored,
    ),
    upperNickname: text().nullable().computed(
      "upper(nickname)",
      postgres: "upper(nickname)",
      mysql: "upper(nickname)",
      mariadb: "upper(nickname)",
      storage: .virtual,
    ),
  ),
  uniqueKeys: (r) => [r.email],
  checks: [
    check(
      "length(email) > 0",
      name: "valid_email",
      postgres: "length(email) > 0",
      mysql: "length(email) > 0",
      mariadb: "length(email) > 0",
    ),
  ],
  relations: (r) => (posts: referencedBy(() => post, on: (authorId: r.id))),
);

final Model post = model(
  "posts",
  (id: integer().identity(), authorId: integer(), title: text()),
  relations: (r) =>
      (author: references((id: r.authorId), () => user, onDelete: .cascade)),
);

final Model value = model("values", (
  id: integer().identity(),
  wide: bigInteger(),
  bytes: bytes(),
  amount: decimal(),
  day: date(),
  time: time(),
  stamp: localDateTime(),
  instant: dateTime(),
));

final Model reading = model(
  "readings",
  (id: integer(), value: real()),
  primaryKey: (r) => r.id,
  relations: (r) => (
    peers: references((value: r.value), () => reading, constraint: false),
    sameReading: references(
      (value: r.value, id: r.id),
      () => reading,
      constraint: false,
    ),
  ),
);
