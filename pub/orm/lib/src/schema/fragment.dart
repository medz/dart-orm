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
class Fragment {
  const Fragment();
}
