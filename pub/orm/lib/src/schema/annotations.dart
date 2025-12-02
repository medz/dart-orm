import 'package:meta/meta_meta.dart';

/// Model fragment
/// ```
/// @fragment()
/// class Timestamps {
///   external DateTime createdAt;
///   external DateTime updatedAt;
/// }
/// ```
const fragment = _Fragment();

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

@Target({.classType})
class _Fragment {
  const _Fragment();
}

@Target({.getter, .field})
class _Ignore {
  const _Ignore();
}

@Target({.classType})
class Model {
  final String? name;
  final bool ignore;

  const Model({this.name, this.ignore = false});
}
