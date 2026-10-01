import 'package:orm/schema.dart';

extension type const Email(String value) {}

const emailCodec = Codec<Email>('text', decodeEmail, encodeEmail);

Email decodeEmail(Object? raw) => Email(raw as String);

Object? encodeEmail(Email value) => value.value;

String defaultMarker() => 'seed';

@Model(table: "nominal_accounts")
@Unique(["email"])
@Relation(
  target: Note,
  name: "notes",
  fields: ["id"],
  keys: ["accountId"],
  constraint: false,
)
final class Account({
  @Id(generated: true) @Column(name: "id") required final int id,
  @Column(name: "email", codec: emailCodec) required final Email email,
  @Column(name: "display_name") required final String? label,
  @Column(name: "enabled")
  @DatabaseDefault.sql("false")
  required final bool enabled,
  @Column(name: "marker")
  @ClientDefault(defaultMarker)
  required final String marker,
  @Column(name: "a") required final int a,
  @Column(name: "b") required final int b,
  @Column(name: "c") required final int c,
  @Column(name: "total")
  @Computed(
    "a + b",
    postgres: "a + b",
    mysql: "a + b",
    mariadb: "a + b",
    storage: .stored,
  )
  required final int total,
});

@Model(table: "nominal_notes")
@Relation(
  target: Account,
  name: "account",
  fields: ["accountId"],
  keys: ["id"],
  onDelete: .cascade,
)
final class Note({
  @Id(generated: true) @Column(name: "id") required final int id,
  @Column(name: "account_id") required final int accountId,
  @Column(name: "body") required final String body,
});
