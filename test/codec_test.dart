import 'package:orm/orm.dart';
import 'package:test/test.dart';

void main() {
  test(
    'erased codecs keep checked argument types without function getter casts',
    () {
      final List<Codec<Object?>> codecs = [
        Codecs.integer,
        Codecs.text.nullable(),
        Codecs.boolean,
      ];
      expect(codecs[0].encode(codecs[0].decode(42)), 42);
      expect(codecs[1].encode(codecs[1].decode(null)), null);
      expect(codecs[2].encode(codecs[2].decode(1)), true);
      expect(() => codecs[0].encode('42'), throwsA(isA<TypeError>()));
      expect(codecs.map((c) => c.acceptsNull), [false, true, false]);
    },
  );

  test('mapped domain codecs preserve one decode and one encode boundary', () {
    final codec = Codecs.text.map<_Email>(_Email.new, (email) => email.value);
    final Codec<Object?> erased = codec;
    final email = erased.decode('seven@example.com') as _Email;
    expect(email.value, 'seven@example.com');
    expect(erased.encode(email), 'seven@example.com');
    expect(codec.nullable().decode(null), null);
  });
}

final class _Email(final String value);
