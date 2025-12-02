import 'database.dart';

enum RelationMode { foreignKeys, simulated }

class Datasource<T extends Database> {
  final T database;
  final RelationMode relationMode;
  final String url;

  const Datasource({
    required this.database,
    required this.url,
    this.relationMode = .foreignKeys,
  });
}
