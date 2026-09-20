import 'dart:convert' show jsonEncode;

import '../../driver.dart' show Backend, SqlCommand, SqlDialect;
import '../../runtime.dart' show SqlDatabase;
import '../../schema_model.dart' show CheckSchema, TableSchema;
import '../../values.dart' show Codecs, OrmException;
import 'catalog.dart' show inspectTable;
import 'sql_utils.dart' show quoteIdentifier;
import 'sqlite_checks.dart' show sqliteName, sqliteTokens;

/// An enforced, validated row CHECK read from this database's catalog.
final class CheckInfo {
  /// Database constraint name, or null for an unnamed constraint.
  final String? name;

  /// Catalog SQL expression evaluated by the row CHECK constraint.
  final String expression;

  /// Records one catalog CHECK without evaluating its expression.
  const CheckInfo(this.name, this.expression);
}

TableSchema withChecks(TableSchema table, List<CheckSchema> checks) =>
    TableSchema(
      table.name,
      columns: table.columns,
      primaryKey: table.primaryKey,
      uniqueKeys: table.uniqueKeys,
      foreignKeys: table.foreignKeys,
      indexes: table.indexes,
      checks: checks,
    );

({List<CheckSchema> removed, List<CheckSchema> added}) checkDelta(
  List<CheckSchema> before,
  List<CheckSchema> after,
  SqlDialect dialect,
) {
  final added = after.toList(), removed = <CheckSchema>[];
  for (final old in before) {
    final index = added.indexWhere(
      (c) =>
          c.name == old.name &&
          c.expression(dialect) == old.expression(dialect),
    );
    if (index < 0) {
      removed.add(old);
    } else {
      added.removeAt(index);
    }
  }
  return (removed: removed, added: added);
}

String _checkSignature(String expression) {
  var tokens = sqliteTokens(expression);
  // Strip enclosing parentheses, not parentheses that determine precedence.
  while (tokens.length >= 2 &&
      tokens.first.text == '(' &&
      tokens.last.text == ')') {
    var depth = 0, enclosing = true;
    for (var i = 0; i < tokens.length - 1; i++) {
      if (tokens[i].text == '(') depth++;
      if (tokens[i].text == ')') depth--;
      if (depth == 0) {
        enclosing = false;
        break;
      }
    }
    if (!enclosing) break;
    tokens = tokens.sublist(1, tokens.length - 1);
  }
  return jsonEncode(
    tokens
        .map(
          (t) => t.text.startsWith('i:')
              ? sqliteName(t.text.substring(2))
              : t.text.startsWith('s:')
              ? t.text
              : sqliteName(t.text),
        )
        .toList(),
  );
}

// PostgreSQL rewrites IN, casts and parentheses in stored expressions. Ask its
// planner to render both projections in the same typed context; never compare
// expressions by deleting casts or precedence-bearing syntax. EXPLAIN does not
// run the SELECT, though PostgreSQL can evaluate immutable constants in planning.
Future<List<String>> checkExpressions(
  SqlDatabase<Backend> db,
  String table,
  List<String> expressions,
) async {
  if (db.dialect == SqlDialect.sqlite) {
    return expressions.map(_checkSignature).toList();
  }
  if (expressions.isEmpty) return const [];
  final result = await db.execute(
    SqlCommand(
      'EXPLAIN (VERBOSE, FORMAT JSON, COSTS OFF) SELECT '
      '${expressions.map((e) => '($e\n)').join(', ')} FROM ONLY ${quoteIdentifier(table)}',
    ),
  );
  final json = Codecs.json.decode(result.rows.single.single) as List<Object?>;
  final plan =
      (json.single as Map<String, Object?>)['Plan'] as Map<String, Object?>;
  final output = (plan['Output'] as List<Object?>).cast<String>();
  if (output.length != expressions.length) {
    throw const OrmException('SCHEMA.CHECK', 'CHECK projection arity differs.');
  }
  return output;
}

/// One actual constraint is consumed per declaration, including unnamed copies.
Future<List<int?>> matchChecks(
  SqlDatabase<Backend> db,
  String table,
  List<CheckSchema> expected,
  List<CheckInfo> actual,
) async {
  if (expected.isEmpty) return const [];
  final signatures = await checkExpressions(db, table, [
    ...expected.map((c) => c.expression(db.dialect)),
    ...actual.map((c) => c.expression),
  ]);
  final used = <int>{}, matches = <int?>[];
  for (var i = 0; i < expected.length; i++) {
    int? found;
    for (var j = 0; j < actual.length; j++) {
      final name = expected[i].name;
      final sameName =
          name == null ||
          (db.dialect == SqlDialect.sqlite
              ? actual[j].name != null &&
                    sqliteName(name) == sqliteName(actual[j].name!)
              : name == actual[j].name);
      if (!used.contains(j) &&
          sameName &&
          signatures[i] == signatures[expected.length + j]) {
        found = j;
        used.add(j);
        break;
      }
    }
    matches.add(found);
  }
  return matches;
}

Future<void> dropCheck(
  SqlDatabase<Backend> db,
  String table,
  CheckSchema check,
) async {
  final actual = (await inspectTable(db, table)).checks;
  final match = (await matchChecks(db, table, [check], actual)).single;
  if (match == null || actual[match].name == null) {
    throw OrmException(
      'MIGRATION.DRIFT',
      'Expected CHECK is missing or differs on $table.',
    );
  }
  await db.execute(
    SqlCommand(
      'ALTER TABLE ${quoteIdentifier(table)} DROP CONSTRAINT ${quoteIdentifier(actual[match].name!)}',
    ),
  );
}
