part of '../../generate.dart';

final class _Field {
  final String name;
  final String column;
  final String type;
  final String codec;
  final String storage;
  final bool nullable;
  final bool id;
  final bool generated;
  final bool unique;
  final String? defaultSql;
  const _Field({
    required this.name,
    required this.column,
    required this.type,
    required this.codec,
    required this.storage,
    required this.nullable,
    this.id = false,
    this.generated = false,
    this.unique = false,
    this.defaultSql,
  });
  Map<String, Object?> snapshot() => {
    'name': column,
    'type': storage,
    'nullable': nullable,
    'generated': generated,
    if (defaultSql != null) 'default': defaultSql,
  };
}

final class _Entity {
  final String name;
  final String table;
  final String row;
  final List<_Field> fields;
  List<String> primaryKey;
  final List<List<String>> uniqueKeys;
  final List<_Index> indexes = [];
  final List<_Edge> edges = [];
  _Entity(this.name, this.table, this.row, this.fields)
    : primaryKey = [
        for (final f in fields)
          if (f.id) f.name,
      ],
      uniqueKeys = [
        for (final f in fields)
          if (f.unique) [f.name],
      ];
  String get symbol => name[0].toUpperCase() + name.substring(1);
  String get fieldsType => '${symbol}Fields';
  String get setType => '${symbol}TableSet';
  String get rowType => 'models.$row';
  _Field field(String name) => fields.firstWhere(
    (f) => f.name == name,
    orElse: () => throw GenerationException('$this has no field $name.'),
  );
  List<String> columns(List<String> keys) => [
    for (final key in keys) field(key).column,
  ];
  Map<String, Object?> snapshot() => {
    'name': table,
    'columns': [for (final f in fields) f.snapshot()],
    'primaryKey': columns(primaryKey),
    'uniqueKeys': [for (final key in uniqueKeys) columns(key)],
    'indexes': [
      for (final i in indexes)
        {'name': i.name, 'columns': columns(i.keys), 'unique': i.unique},
    ],
    'foreignKeys': [
      for (final edge in edges)
        if (!edge.inverse)
          {
            'columns': columns(edge.parentKeys),
            'target': edge.target.table,
            'targetColumns': edge.target.columns(edge.childKeys),
            'onDelete': edge.onDelete,
          },
    ],
  };
  @override
  String toString() => name;
}

final class _Index(
  final String name,
  final List<String> keys,
  final bool unique,
);
final class _Edge(
  final String name,
  final _Entity target,
  final List<String> parentKeys,
  final List<String> childKeys,
  final String onDelete, {
  final bool inverse = false,
});

String _snake(String value) => value
    .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
    .toLowerCase();
String _literal(String value) => jsonEncode(value).replaceAll(r'$', r'\$');
String _strings(List<String> values) => '[${values.map(_literal).join(', ')}]';
String _columnSymbol(_Entity entity, _Field field) =>
    '_${entity.name}${field.name[0].toUpperCase()}${field.name.substring(1)}';
bool _same(List<String> a, List<String> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((v) => v);
