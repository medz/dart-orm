part of '../sql.dart';

/// Fixed SQL with :named bound values. Quoted text, identifiers and comments are
/// preserved. This tokenizer is not a SQL parser; use database query checks.
final class SqlTemplate {
  final SqlDialect dialect;
  final List<Object> _parts;
  final Set<String> parameters;
  SqlTemplate._(this.dialect, this._parts, this.parameters);
  factory SqlTemplate(String source, {required SqlDialect dialect}) {
    _checkSqlText(source);
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
    return SqlTemplate._(
      dialect,
      List.unmodifiable(parts),
      Set.unmodifiable(names),
    );
  }

  SqlCommand compile(
    Capabilities capabilities,
    Map<String, Expr<Object?>> arguments,
  ) {
    final w = _Writer(
      capabilities.dialect,
      {},
      exactDecimal: capabilities.exactDecimal,
      temporal: capabilities.temporal,
    );
    final sql = _write(w, arguments);
    final command = w.finish(sql);
    if (command.parameters.length > capabilities.maxParameters) {
      throw const OrmException(
        'QUERY.PARAMETERS',
        'Named SQL exceeds the parameter limit.',
      );
    }
    return command;
  }

  String _write(_Writer w, Map<String, Expr<Object?>> arguments) {
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
              if (_unwrapStorage(expression._node) is! _Parameter) {
                throw const OrmException(
                  'SQL.PARAMETERS',
                  'Named SQL arguments must be bound values.',
                );
              }
              return expression._node.write(w);
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
  final Table<R, F> result;
  final Map<SqlDialect, SqlTemplate> sql;
  SqlQueryDefinition(this.result, Map<SqlDialect, SqlTemplate> sql)
    : sql = Map.unmodifiable(sql);
  Query<R, F> bind(QueryContext db, Map<String, Expr<Object?>> arguments) {
    final template = sql[db.dialect];
    if (template == null) {
      throw const OrmException(
        'QUERY.DIALECT',
        'No SQL source was declared for this backend.',
      );
    }
    final fields = result.createFields(TableRef(result.schema));
    return Query._(
      db,
      fields,
      _QueryState(
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
) implements _CteDefinition {
  @override
  String _writeDefinition(_Writer writer) {
    if (writer.reads case final reads?) reads.opaque = true;
    return '${writer.quote(name)} AS (\n${template._write(writer, arguments)}\n)';
  }
}
