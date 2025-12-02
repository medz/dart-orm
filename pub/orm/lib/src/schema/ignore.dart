import 'package:meta/meta_meta.dart';

/// Ignore annotation for ORM schema models/fields/fragments.
///
/// ```prisma
/// @Model()
/// @Ignore() // ignore the model generate in client.
/// class User { ... }
///
/// @model
/// class Profile {
///   @Ignore() // ignore the field generate in client.
///   external int age;
/// }
/// ```
@Target({.classType, .getter, .field})
class Ignore {
  const Ignore();
}
