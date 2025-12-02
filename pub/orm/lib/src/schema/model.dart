import 'package:meta/meta_meta.dart';

/// Define model annotation
@Target({.classType})
class Model {
  final String? name;
  final bool ignore;

  const Model({this.name, this.ignore = false});
}
