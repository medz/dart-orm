import 'package:orm/schema.dart';

extension type const Email(String value) {}

const emailCodec = Codec<Email>('text', decodeEmail, encodeEmail);
Email decodeEmail(Object? raw) => Email(raw as String);
Object? encodeEmail(Email value) => value.value;
String defaultMarker() => 'seed';

final class Account(
  @Id.generated() final int id,
  @Unique() @UseCodec(emailCodec) final Email email,
  @ColumnName('display_name') final String? label,
  @Default.sql('false') final bool enabled,
  @ClientDefault(defaultMarker) final String marker,
  final int a,
  final int b,
  final int c,
  @Computed.sql('a + b') final int total,
);

final class Note({
  @Id.generated() required final int id,
  required final int accountId,
  required final String body,
});

final accounts = entity<Account>(table: 'nominal_accounts');
final notes = entity<Note>(table: 'nominal_notes');
final account = notes
    .key((n) => n.accountId)
    .references(
      accounts.key((a) => a.id),
      inverse: 'notes',
      onDelete: .cascade,
    );
