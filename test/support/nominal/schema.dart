import 'package:orm/schema.dart';

extension type const Email(String value) {}

const emailCodec = Codec<Email>('text', decodeEmail, encodeEmail);

Email decodeEmail(Object? raw) => Email(raw as String);

Object? encodeEmail(Email value) => value.value;

String defaultMarker() => 'seed';

final Model account = model(
  "nominal_accounts",
  (
    id: integer().identity(),
    email: custom(emailCodec),
    label: text(name: "display_name").nullable(),
    enabled: boolean(defaultSql: "false"),
    marker: text(clientDefault: defaultMarker),
    a: integer(),
    b: integer(),
    c: integer(),
    total: integer().computed(
      "a + b",
      postgres: "a + b",
      mysql: "a + b",
      mariadb: "a + b",
      storage: .stored,
    ),
  ),
  uniqueKeys: (r) => [r.email],
  relations: (r) => (notes: referencedBy(() => note, on: (accountId: r.id))),
);

final Model note = model(
  "nominal_notes",
  (id: integer().identity(), accountId: integer(), body: text()),
  relations: (r) => (
    account: references((id: r.accountId), () => account, onDelete: .cascade),
  ),
);
