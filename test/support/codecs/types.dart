import 'dart:convert';

import 'package:orm/schema.dart';

extension type const PersonId(int value) {
  static const codec = Codec<PersonId>.integer(_decode, _encode);
  static PersonId _decode(Object? value) => PersonId(value as int);
  static int _encode(PersonId id) => id.value;
}

final class Email {
  final String value;
  const Email(this.value);
  static const codec = Codec<Email>.text(_decode, _encode);
  static Email _decode(Object? value) => Email(_validate(value as String));
  static String _encode(Email email) => _validate(email.value);
  static String _validate(String value) {
    if (!value.contains('@')) {
      throw const FormatException('Expected an email value.');
    }
    return value;
  }
}

enum Membership {
  @EnumValue('pending-payment')
  pending,
  active,
  @EnumValue('closed')
  cancelled,
}

typedef Location = ({String city, int zone});
const locationCodec = Codec<Location>('json', _location, _locationJson);
Location _location(Object? value) {
  final json = Codecs.json.decode(value) as Map<String, Object?>;
  return (city: json['city'] as String, zone: json['zone'] as int);
}

String _locationJson(Location value) =>
    jsonEncode({'city': value.city, 'zone': value.zone});

const tagsCodec = Codec<List<String>>('json', _tags, jsonEncode);
List<String> _tags(Object? value) =>
    List<String>.unmodifiable(Codecs.json.decode(value) as List<Object?>);
