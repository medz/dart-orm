import 'package:meta/meta.dart';

import '../../driver.dart';
import 'context.dart';
import 'cte.dart';
import 'expression.dart';
import 'nodes.dart';
import 'query.dart';
import 'table.dart';

/// Fixed SQL with :named bound values. Quoted text, identifiers and comments are
/// preserved. This tokenizer is not a SQL parser; use database query checks.
final class SqlTemplate {
  /// Database engine whose quoting and parameter rules this template uses.
  final SqlDialect dialect;
  final List<Object> _parts;

  /// Immutable names of all required bound parameters, excluding repeated uses.
  final Set<String> parameters;

  /// @nodoc
  @internal
  SqlTemplate.internal(this.dialect, this._parts, this.parameters);

  /// Tokenizes a trusted SELECT, WITH, or VALUES source without database access.
  ///
  /// Named placeholders bind values; they do not substitute identifiers or
  /// arbitrary SQL. Validate SQL and result metadata against the target database
  /// before shipping a generated query.
  factory SqlTemplate(String source, {required SqlDialect dialect}) {
    checkSqlText(source);
    final mysql = dialect == SqlDialect.mysql || dialect == SqlDialect.mariadb;
    final parts = <Object>[], names = <String>{};
    final text = StringBuffer();
    var i = 0, ended = false;
    String? firstWord;
    bool identifier(int code) =>
        code >= 65 && code <= 90 || code >= 97 && code <= 122 || code == 95;
    bool continuation(int code) => identifier(code) || code >= 48 && code <= 57;
    Never fail(String message) =>
        throw OrmException('SQL.TEMPLATE', '$message at offset $i.');
    while (i < source.length) {
      final c = source[i];
      if (c.trim().isEmpty) {
        text.write(c);
        i++;
        continue;
      }
      if (source.startsWith('--', i) &&
              (!mysql ||
                  i + 2 == source.length ||
                  source.codeUnitAt(i + 2) <= 32) ||
          mysql && c == '#') {
        final end = source.indexOf('\n', i);
        text.write(source.substring(i, end < 0 ? source.length : end));
        i = end < 0 ? source.length : end;
        continue;
      }
      if (source.startsWith('/*', i)) {
        if (mysql &&
            (source.startsWith('/*!', i) || source.startsWith('/*M!', i))) {
          fail('Executable comments are not allowed in named SQL');
        }
        final start = i;
        i += 2;
        var depth = 1;
        while (i < source.length && depth > 0) {
          if (dialect == SqlDialect.postgres && source.startsWith('/*', i)) {
            depth++;
            i += 2;
          } else if (source.startsWith('*/', i)) {
            depth--;
            i += 2;
          } else {
            i++;
          }
        }
        if (depth != 0) fail('Unterminated block comment');
        text.write(source.substring(start, i));
        continue;
      }
      if (ended) fail('Only one SQL statement is allowed');
      if (c == ';') {
        ended = true;
        i++;
        continue;
      }
      if (c == "'" ||
          c == '"' ||
          (dialect == SqlDialect.sqlite || mysql) && c == '`' ||
          dialect == SqlDialect.sqlite && c == '[') {
        final start = i, close = c == '[' ? ']' : c;
        final escapes =
            c == "'" &&
            dialect == SqlDialect.postgres &&
            i > 0 &&
            source[i - 1].toUpperCase() == 'E' &&
            (i < 2 || !continuation(source.codeUnitAt(i - 2)));
        i++;
        var closed = false;
        while (i < source.length) {
          if (source[i] == '\\' && c == "'" && dialect == SqlDialect.postgres) {
            if (!escapes) {
              fail("Use E-strings or dollar quotes for PostgreSQL backslashes");
            }
            i += 2;
          } else if (source[i] == close) {
            i++;
            if (close != ']' && i < source.length && source[i] == close) {
              i++;
            } else {
              closed = true;
              break;
            }
          } else {
            i++;
          }
        }
        if (!closed) fail('Unterminated quote');
        text.write(source.substring(start, i));
        continue;
      }
      if (c == r'$') {
        final tag = dialect == SqlDialect.postgres
            ? RegExp(r'^\$(?:[A-Za-z_][A-Za-z_0-9]*)?\$')
                  .firstMatch(source.substring(i))
                  ?.group(0)
            : null;
        if (tag == null) fail('Use :name parameters');
        final end = source.indexOf(tag, i + tag.length);
        if (end < 0) fail('Unterminated dollar quote');
        text.write(source.substring(i, end + tag.length));
        i = end + tag.length;
        continue;
      }
      if (c == ':' &&
          (i == 0 || source[i - 1] != ':') &&
          i + 1 < source.length &&
          identifier(source.codeUnitAt(i + 1))) {
        var end = i + 2;
        while (end < source.length && continuation(source.codeUnitAt(end))) {
          end++;
        }
        final name = source.substring(i + 1, end);
        parts.add(text.toString());
        text.clear();
        parts.add(_SqlSlot(name));
        names.add(name);
        i = end;
        continue;
      }
      if (c == '?' && (dialect == SqlDialect.sqlite || mysql) ||
          c == '@' && dialect == SqlDialect.sqlite) {
        fail('Use :name parameters');
      }
      if (c == '\u0001' || c == '\u0002') fail('Reserved control character');
      if (identifier(source.codeUnitAt(i))) {
        var end = i + 1;
        while (end < source.length &&
            (continuation(source.codeUnitAt(end)) ||
                dialect == SqlDialect.postgres && source[end] == r'$')) {
          end++;
        }
        firstWord ??= source.substring(i, end).toUpperCase();
        text.write(source.substring(i, end));
        i = end;
        continue;
      }
      text.write(c);
      i++;
    }
    if (!{'SELECT', 'WITH', 'VALUES'}.contains(firstWord)) {
      fail('A named query requires SELECT, WITH or VALUES');
    }
    parts.add(text.toString());
    return SqlTemplate.internal(
      dialect,
      List.unmodifiable(parts),
      Set.unmodifiable(names),
    );
  }

  /// Compiles SQL and bound parameters without executing the template.
  ///
  /// [arguments] must contain exactly [parameters], each represented by a bound
  /// value expression. Dialect mismatches and parameter overflow are rejected.
  SqlCommand compile(
    Capabilities capabilities,
    Map<String, Expr<Object?>> arguments,
  ) {
    final w = SqlWriter(
      capabilities.dialect,
      {},
      exactDecimal: capabilities.exactDecimal,
      temporal: capabilities.temporal,
    );
    final sql = writeQuery(w, arguments);
    final command = w.finish(sql);
    if (command.parameters.length > capabilities.maxParameters) {
      throw const OrmException(
        'QUERY.PARAMETERS',
        'Named SQL exceeds the parameter limit.',
      );
    }
    return command;
  }

  /// @nodoc
  @internal
  String writeQuery(SqlWriter w, Map<String, Expr<Object?>> arguments) {
    if (w.dialect != dialect) {
      throw const OrmException(
        'QUERY.DIALECT',
        'SQL template belongs to another dialect.',
      );
    }
    if (arguments.length != parameters.length ||
        !parameters.every(arguments.containsKey)) {
      throw const OrmException(
        'SQL.PARAMETERS',
        'Named SQL argument names differ from its declaration.',
      );
    }
    final bound = <String, String>{};
    return _parts
        .map(
          (part) => switch (part) {
            String() => part,
            _SqlSlot(:final name) => bound.putIfAbsent(name, () {
              final expression = arguments[name]!;
              if (unwrapStorage(expression.expressionNode) is! ParameterNode) {
                throw const OrmException(
                  'SQL.PARAMETERS',
                  'Named SQL arguments must be bound values.',
                );
              }
              return expression.expressionNode.write(w);
            }),
            _ => throw StateError('Unknown SQL fragment'),
          },
        )
        .join();
  }
}

final class _SqlSlot(final String name);

/// Generated query definitions reuse table fields and the ordinary Query
/// compiler. Their CTE source makes table mutations invalid before execution.
final class SqlQueryDefinition<R, F extends Fields> {
  /// Declared result columns, codecs, and row decoder.
  final Table<R, F> result;

  /// Immutable SQL variants keyed by their target database engine.
  final Map<SqlDialect, SqlTemplate> sql;

  /// Combines a typed result declaration with trusted engine-specific SQL.
  SqlQueryDefinition(this.result, Map<SqlDialect, SqlTemplate> sql)
    : sql = Map.unmodifiable(sql);

  /// Creates a query bound to [db], without executing its SQL source.
  ///
  /// The context selects its engine's template. Further filters and projections
  /// operate on the declared result columns; generated bindings normally supply
  /// the typed argument map. No fallback to another engine's SQL is attempted.
  Query<R, F> bind(QueryContext db, Map<String, Expr<Object?>> arguments) {
    final template = sql[db.dialect];
    if (template == null) {
      throw const OrmException(
        'QUERY.DIALECT',
        'No SQL source was declared for this backend.',
      );
    }
    final fields = result.createFields(TableRef(result.schema));
    return Query.internal(
      db,
      fields,
      QueryState(
        fields.table,
        ctes: [
          _SqlCte(result.schema.name, template, Map.unmodifiable(arguments)),
        ],
      ),
      result.selectRow(fields),
    );
  }
}

final class _SqlCte(
  @override final String name,
  final SqlTemplate template,
  final Map<String, Expr<Object?>> arguments,
) implements CteDefinition {
  /// @nodoc
  @internal
  @override
  String writeDefinition(SqlWriter writer) {
    if (writer.reads case final reads?) reads.opaque = true;
    return '${writer.quote(name)} AS (\n${template.writeQuery(writer, arguments)}\n)';
  }
}
