import 'package:orm/schema.dart';

// A distinct domain type with the same short name exercises generated imports.
final class Email {
  final String label;
  const Email(this.label);
}

const emailCodec = Codec<Email>.text(_decode, _encode);
Email _decode(Object? value) => Email(value as String);
String _encode(Email value) => value.label;
