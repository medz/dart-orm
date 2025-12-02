import 'package:meta/meta_meta.dart';

/// Define model annotation
@Target({.classType})
class Model {
  const Model();
}

/// Custom model table name annotation
@Target({.classType})
class Table {
  final String name;
  const Table(this.name);
}
