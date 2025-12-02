import 'package:meta/meta_meta.dart';

@Target({.getter, .field})
class _Ignore {
  const _Ignore();
}

/// Ignore annotation for model fields.
///
/// ```prisma
/// @model
/// class Profile {
///   @ignore // ignore the field generate in client.
///   external int age;
/// }
/// ```
const ignore = _Ignore();
