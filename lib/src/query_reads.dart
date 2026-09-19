part of '../sql.dart';

/// SQL compilation visits subqueries and CTE definitions with the same writer.
/// Batch relationships are additional queries and must be visited separately.
final class _ReadTables {
  final bool includeRaw;
  _ReadTables({this.includeRaw = false});
  bool opaque = false;
  final Set<TableSchema> tables = Set.identity();
  void query(Query<Object?, Fields> query) {
    final (plan, _) = query._plan();
    query._write(
      _Writer(
        query.database.dialect,
        {},
        database: query.database,
        reads: this,
        exactDecimal: query.database.capabilities.exactDecimal,
        temporal: query.database.capabilities.temporal,
      ),
      plan,
    );
    for (final binding in plan.relations) {
      binding.collectReads(query.database, this);
    }
  }
}
