part of '../../generate.dart';

final class _SchemaReader(
  final CompilationUnit unit,
  final TypeSystem typeSystem,
  final _DartNames names,
) {
  final Map<String, _Entity> entities = {};

  List<_Entity> read() {
    final aliases = {
      for (final d in unit.declarations.whereType<GenericTypeAlias>())
        d.name.lexeme: d,
    };
    final variables = [
      for (final d
          in unit.declarations.whereType<TopLevelVariableDeclaration>())
        ...d.variables.variables,
    ];
    for (final variable in variables) {
      final call = variable.initializer;
      if (call is! MethodInvocation || call.methodName.name != 'entity') {
        continue;
      }
      if (call.methodName.element?.library?.uri.toString() !=
          'package:orm/schema.dart') {
        continue;
      }
      final types = call.typeArguments?.arguments;
      if (types == null || types.length != 1) {
        _fail(call, 'entity requires an explicit record typedef.');
      }
      final row = types.single.toSource();
      final alias = aliases[row];
      if (alias == null ||
          alias.type is! RecordTypeAnnotation ||
          alias.typeParameters != null) {
        _fail(
          call,
          'entity<$row> requires a non-generic named record typedef in this file.',
        );
      }
      final record = alias.type as RecordTypeAnnotation;
      if (record.positionalFields.isNotEmpty || record.namedFields == null) {
        _fail(record, 'Model records must have named fields only.');
      }
      final fields = [
        for (final f in record.namedFields!.fields) _readField(f),
      ];
      if (fields.isEmpty) _fail(record, 'A model needs fields.');
      final name = variable.name.lexeme;
      final table = _namedString(call, 'table') ?? _snake(name);
      if (entities.values.any((e) => e.table == table)) {
        _fail(call, 'Duplicate physical table $table.');
      }
      if (fields.map((f) => f.column).toSet().length != fields.length) {
        _fail(record, 'Duplicate physical column name.');
      }
      final entity = _Entity(name, table, row, fields);
      entities[name] = entity;
    }
    if (entities.isEmpty) {
      throw const GenerationException(
        'No entity<Record>() declarations found.',
      );
    }
    // Keys and indexes are collected before relations, independent of source order.
    for (final variable in variables) {
      final call = variable.initializer;
      if (call is! MethodInvocation || call.target is! SimpleIdentifier) {
        continue;
      }
      final entity = entities[(call.target as SimpleIdentifier).name];
      if (entity == null) continue;
      final method = call.methodName.name;
      if (!{'primaryKey', 'unique', 'index'}.contains(method)) continue;
      final keys = _selector(
        call.argumentList.arguments.first.argumentExpression,
        entity,
      );
      switch (method) {
        case 'primaryKey':
          if (entity.primaryKey.isNotEmpty) {
            _fail(call, 'Primary key declared twice.');
          }
          entity.primaryKey = keys;
        case 'unique':
          entity.uniqueKeys.add(keys);
        case 'index':
          entity.indexes.add(
            _Index(
              _namedString(call, 'name') ?? _snake(variable.name.lexeme),
              keys,
              _named(call, 'unique')?.toSource() == 'true',
            ),
          );
      }
    }
    for (final variable in variables) {
      final call = variable.initializer;
      if (call is! MethodInvocation || call.methodName.name != 'references') {
        continue;
      }
      if (call.target is! MethodInvocation) {
        _fail(call, 'references must follow entity.key().');
      }
      final (source, local) = _key(call.target!);
      final (target, remote) = _key(
        call.argumentList.arguments.first.argumentExpression,
      );
      if (local.length != remote.length) {
        _fail(call, 'Foreign key arity mismatch.');
      }
      final targets = [
        target.primaryKey,
        ...target.uniqueKeys,
        for (final i in target.indexes)
          if (i.unique) i.keys,
      ];
      if (!targets.any((key) => _same(key, remote))) {
        _fail(
          call,
          'Foreign key target must be a primary or unique key in the same column order.',
        );
      }
      for (var i = 0; i < local.length; i++) {
        if (source.field(local[i]).storage != target.field(remote[i]).storage) {
          _fail(call, 'Foreign key storage types differ.');
        }
      }
      final action =
          _named(call, 'onDelete')?.toSource().split('.').last ?? 'restrict';
      final onDelete = switch (action) {
        'restrict' => 'RESTRICT',
        'cascade' => 'CASCADE',
        'setNull' => 'SET NULL',
        'setDefault' => 'SET DEFAULT',
        'noAction' => 'NO ACTION',
        _ => throw GenerationException(
          'Unsupported referential action $action.',
        ),
      };
      if (action == 'setNull' &&
          local.any((key) => !source.field(key).nullable)) {
        _fail(call, 'SET NULL requires nullable foreign key columns.');
      }
      _addEdge(
        source,
        _Edge(variable.name.lexeme, target, local, remote, onDelete),
        call,
      );
      final inverse = _namedString(call, 'inverse');
      if (inverse != null) {
        _addEdge(
          target,
          _Edge(inverse, source, remote, local, onDelete, inverse: true),
          call,
        );
      }
    }
    final indexNames = <String>{};
    for (final entity in entities.values) {
      for (final key in entity.primaryKey) {
        if (entity.field(key).nullable) {
          throw GenerationException(
            '${entity.name} primary keys cannot be nullable.',
          );
        }
      }
      for (final f in entity.fields.where((f) => f.generated)) {
        if (f.storage != 'integer' || !_same(entity.primaryKey, [f.name])) {
          throw GenerationException(
            'Generated identity requires a single integer primary key: ${entity.name}.${f.name}.',
          );
        }
      }
      for (final index in entity.indexes) {
        if (!indexNames.add(index.name)) {
          throw GenerationException('Duplicate index name ${index.name}.');
        }
      }
    }
    return entities.values.toList();
  }

  _Field _readField(RecordTypeAnnotationNamedField field) {
    final type = field.type.type;
    if (type == null) _fail(field, 'Cannot resolve the field type.');
    final nullable = typeSystem.isNullable(type);
    final name = field.name.lexeme;
    if ({'table', 'column'}.contains(name)) {
      _fail(
        field,
        'Field name $name conflicts with the fields API. Use another Dart name and @ColumnName.',
      );
    }
    var id = false, generated = false, unique = false;
    String? column, defaultSql;
    Annotation? custom;
    for (final annotation in field.metadata) {
      final value = annotation.elementAnnotation?.computeConstantValue();
      final annotationType = value?.type;
      if (annotationType is! InterfaceType ||
          annotationType.element.library.uri.toString() !=
              'package:orm/schema.dart') {
        continue;
      }
      switch (annotationType.element.name) {
        case 'Id':
          id = true;
          generated = value!.getField('generated')!.toBoolValue()!;
        case 'Unique':
          unique = true;
        case 'ColumnName':
          column = value!.getField('name')!.toStringValue();
        case 'Default':
          defaultSql = value!.getField('expression')!.toStringValue();
        case 'UseCodec':
          if (custom != null) {
            _fail(annotation, 'UseCodec may only appear once.');
          }
          custom = annotation;
        default:
          _fail(annotation, 'Unsupported ORM annotation.');
      }
    }
    String storage, codec;
    if (custom != null) {
      final value = custom.elementAnnotation!.computeConstantValue()!.getField(
        'codec',
      )!;
      final reference = custom.arguments!.arguments.single.argumentExpression;
      // Constant evaluation erases extension types to their representation.
      // Static compatibility must use the resolved source expression instead.
      final codecType = reference.staticType;
      if (codecType is! InterfaceType ||
          codecType.element.name != 'Codec' ||
          codecType.element.library.uri.toString() != 'package:orm/orm.dart') {
        _fail(custom, 'Use a const Codec<T>.');
      }
      final domain = codecType.typeArguments.single;
      bool same(DartType a, DartType b) =>
          typeSystem.isSubtypeOf(a, b) && typeSystem.isSubtypeOf(b, a);
      if (!same(domain, type) &&
          !same(domain, typeSystem.promoteToNonNull(type))) {
        _fail(custom, 'Codec<$domain> does not match field type $type.');
      }
      storage = value.getField('sqlType')?.toStringValue() ?? '';
      if (!{
        'integer',
        'bigint',
        'real',
        'text',
        'boolean',
        'timestamp',
        'blob',
        'json',
      }.contains(storage)) {
        _fail(custom, 'Unknown codec storage type $storage.');
      }
      codec = names.codecReference(reference);
      if (nullable && !typeSystem.isNullable(domain)) codec += '.nullable()';
    } else if (type is InterfaceType && type.element is EnumElement) {
      storage = 'text';
      codec = names.enumeration(type.element as EnumElement);
      if (nullable) codec += '.nullable()';
    } else {
      if (type is! InterfaceType ||
          !{
            'dart:core',
            'dart:typed_data',
          }.contains(type.element.library.uri.toString())) {
        _fail(field, 'This type needs an explicit @UseCodec.');
      }
      final mapping = switch (type.element.name) {
        'int' => ('integer', 'integer'),
        'String' => ('text', 'text'),
        'double' => ('real', 'real'),
        'bool' => ('boolean', 'boolean'),
        'DateTime' => ('timestamp', 'dateTime'),
        'BigInt' => ('bigint', 'bigint'),
        'Uint8List' => ('blob', 'bytes'),
        _ => throw GenerationException(
          'Unsupported field type $type; declare @UseCodec.',
        ),
      };
      storage = mapping.$1;
      codec = 'Codecs.${mapping.$2}${nullable ? '.nullable()' : ''}';
    }
    return _Field(
      name: name,
      column: column ?? _snake(name),
      type: names.type(type),
      codec: codec,
      storage: storage,
      nullable: nullable,
      id: id,
      generated: generated,
      unique: unique,
      defaultSql: defaultSql,
    );
  }

  (_Entity, List<String>) _key(Expression expression) {
    if (expression is! MethodInvocation ||
        expression.methodName.name != 'key' ||
        expression.target is! SimpleIdentifier) {
      _fail(expression, 'Expected entity.key((row) => row.field).');
    }
    final call = expression;
    final entity = entities[(call.target as SimpleIdentifier).name];
    if (entity == null) _fail(call, 'Key refers to an unknown entity.');
    return (
      entity,
      _selector(call.argumentList.arguments.first.argumentExpression, entity),
    );
  }

  List<String> _selector(Expression expression, _Entity entity) {
    if (expression is! FunctionExpression ||
        expression.parameters?.parameters.length != 1 ||
        expression.body is! ExpressionFunctionBody) {
      _fail(expression, 'Use a one-argument arrow selector.');
    }
    final function = expression;
    final parameter = function.parameters!.parameters.single.name!.lexeme;
    final body = (function.body as ExpressionFunctionBody).expression;
    if (body is RecordLiteral &&
        body.fields.any((f) => f is RecordLiteralNamedField)) {
      _fail(
        body,
        'Keys use positional records to preserve declared column order.',
      );
    }
    final parts = body is RecordLiteral
        ? body.fields.map((f) => f.fieldExpression).toList()
        : [body];
    final keys = <String>[];
    for (final part in parts) {
      final name = switch (part) {
        PrefixedIdentifier(:final prefix, :final identifier)
            when prefix.name == parameter =>
          identifier.name,
        PropertyAccess(
          target: SimpleIdentifier(:final name),
          :final propertyName,
        )
            when name == parameter =>
          propertyName.name,
        _ => _fail(
          part,
          'Key selectors accept direct fields or positional records of fields only.',
        ),
      };
      entity.field(name);
      if (keys.contains(name)) _fail(part, 'A key cannot repeat a field.');
      keys.add(name);
    }
    if (keys.isEmpty) _fail(expression, 'Empty key.');
    return keys;
  }

  void _addEdge(_Entity source, _Edge edge, AstNode node) {
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(edge.name) ||
        source.fields.any((f) => f.name == edge.name) ||
        source.edges.any((e) => e.name == edge.name) ||
        {'table', 'column'}.contains(edge.name)) {
      _fail(node, 'Invalid or duplicate relationship name ${edge.name}.');
    }
    source.edges.add(edge);
  }

  Expression? _named(MethodInvocation call, String name) {
    for (final argument
        in call.argumentList.arguments.whereType<NamedArgument>()) {
      if (argument.name.lexeme == name) return argument.argumentExpression;
    }
    return null;
  }

  String? _namedString(MethodInvocation call, String name) {
    final expression = _named(call, name);
    if (expression == null) return null;
    if (expression is! SimpleStringLiteral) {
      _fail(expression, '$name requires a literal string.');
    }
    return expression.value;
  }

  Never _fail(AstNode node, String message) =>
      throw GenerationException('$message (offset ${node.offset})');
}
