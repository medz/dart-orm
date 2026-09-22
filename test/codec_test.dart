@Tags(['core'])
library;

import 'package:orm/orm.dart';
import 'package:test/test.dart';

void main() {
  test(
    'numeric aggregate text decodes without integer rounding or overflow',
    () {
      expect(Codecs.integer.decode('9223372036854775807'), 9223372036854775807);
      expect(
        Codecs.integer.decode('-9223372036854775808'),
        -9223372036854775808,
      );
      expect(
        () => Codecs.integer.decode('9223372036854775808'),
        throwsFormatException,
      );
      expect(() => Codecs.integer.decode('1.5'), throwsFormatException);
      expect(Codecs.real.decode('1.25'), 1.25);
    },
  );
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

  test(
    'parsed JSON scalars and document presence have unambiguous decoding',
    () {
      expect(Codecs.json.decode('"string"'), 'string');
      expect(Codecs.json.decode(const SqlJson('string')), 'string');
      expect(Codecs.jsonDocument.nullable().decode(null), isNull);
      expect(() => Codecs.jsonDocument.decode(null), throwsFormatException);
      expect(Codecs.jsonDocument.decode('null').value, isNull);
      expect(
        Codecs.jsonDocument.nullable().decode(const SqlJson(null))!.value,
        isNull,
      );
      expect(Codecs.jsonDocument.encode(const SqlJson(null)), 'null');
    },
  );

  test(
    'enum mappings reject duplicates and do not follow mutable caller maps',
    () {
      final labels = {_State.a: 'one', _State.b: 'two'};
      final codec = Codecs.enumeration(labels);
      labels[_State.a] = 'changed';
      expect(codec.encode(_State.a), 'one');
      expect(codec.decode('two'), _State.b);
      expect(
        () => Codecs.enumeration({_State.a: 'x', _State.b: 'x'}),
        throwsArgumentError,
      );
      expect(() => Codecs.enumeration<_State>({}), throwsArgumentError);
      final partial = Codecs.enumeration({_State.a: 'one'});
      expect(() => partial.encode(_State.b), throwsA(isA<OrmException>()));
    },
  );
}

final class _Email(final String value);

enum _State { a, b }
