import 'package:meta/meta.dart';

import '../../schema_model.dart';
import 'nodes.dart';
import 'query.dart';
import 'table.dart';

/// @nodoc
@internal
/// SQL compilation visits subqueries and CTE definitions with the same writer.
/// Batch relationships are additional queries and must be visited separately.
final class ReadTables {
  final bool includeRaw;
  ReadTables({this.includeRaw = false});
  bool opaque = false;
  final Set<TableSchema> tables = Set.identity();
  void query(Query<Object?, Fields> query) {
    final (plan, _) = query.planQuery();
    query.writeQuery(
      SqlWriter(
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
