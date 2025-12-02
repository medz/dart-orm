import 'package:meta/meta_meta.dart';

/// Model fragment
/// ```
/// @Fragment()
/// class Timestamps {
///   external DateTime createdAt;
///   external DateTime updatedAt;
/// }
/// ```
@Target({.classType})
class _Fragment {
  const _Fragment();
}

const fragment = _Fragment();

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

@Target({.classType})
class Model {
  final String? name;
  final bool ignore;

  const Model({this.name, this.ignore = false});
}
