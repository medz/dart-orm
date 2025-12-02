import 'package:meta/meta_meta.dart';

@Target({.getter, .field})
class ID {
  /// The name of the underlying primary key constraint in the database.
  ///
  /// > [!WARNING]
  /// > Not supported for MySQL.
  final String? map;

  /// Allows you to specify a maximum length for the subpart of the value to be indexed.
  ///
  /// > [!WARNING]
  /// > MySQL only.
  final int? length;

  const ID({this.map, this.length});
}

/// Composite ID annotation.
///
/// > [!IMPORTANT]
/// > Not supported by MongoDB
@Target({TargetKind.classType})
class CompositeID extends ID {
  /// The name that client will expose for the argument covering all fields.
  final String? name;

  /// A list of field names
  final Set<String> fields;

  const CompositeID(this.fields, {this.name, super.map, super.length});
}
