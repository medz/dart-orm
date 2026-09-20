import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_system.dart';

import '../../schema_model.dart';
import 'exception.dart';
import 'model.dart';
import 'source.dart';
import 'types.dart';

final class SchemaReader(
  final CompilationUnit unit,
  final TypeSystem typeSystem,
  final DartNames names,
) {
  final Map<String, ModelEntity> entities = {};

  List<ModelEntity> read() {
    final aliases = {
      for (final d in unit.declarations.whereType<GenericTypeAlias>())
        d.name.lexeme: d,
    };
    final classes = {
      for (final d in unit.declarations.whereType<ClassDeclaration>())
        d.namePart.typeName.lexeme: d,
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
          schemaDeclarationUri) {
        continue;
      }
      final types = call.typeArguments?.arguments;
      if (types == null || types.length != 1) {
        _fail(call, 'entity requires an explicit model type.');
      }
      final row = types.single.toSource();
      final alias = aliases[row];
      final declaration = classes[row];
      final List<ModelField> fields;
      final AstNode model;
      Set<String>? constructorNamedFields;
      if (declaration != null) {
        model = declaration;
        final parsed = _readClass(declaration);
        fields = parsed.$1;
        constructorNamedFields = parsed.$2;
      } else if (alias != null &&
          alias.type is RecordTypeAnnotation &&
          alias.typeParameters == null) {
        final record = alias.type as RecordTypeAnnotation;
        model = record;
        if (record.positionalFields.isNotEmpty || record.namedFields == null) {
          _fail(record, 'Model records must have named fields only.');
        }
        fields = [
          for (final f in record.namedFields!.fields)
            readField(f, f.name.lexeme, f.type.type, f.metadata),
        ];
      } else {
        _fail(
          call,
          'entity<$row> requires a final primary-constructor class or a non-generic named record typedef in this file.',
        );
      }
      if (fields.isEmpty) _fail(model, 'A model needs fields.');
      final name = variable.name.lexeme;
      if (name.startsWith('_') || databaseMembers.contains(name)) {
        _fail(
          variable,
          'Entity $name must be public and cannot shadow a Database member. Rename the Dart declaration and keep table: for its physical name.',
        );
      }
      final table = namedString(call, 'table') ?? snakeCase(name);
      if (entities.values.any((e) => e.table == table)) {
        _fail(call, 'Duplicate physical table $table.');
      }
      if (fields.map((f) => f.column).toSet().length != fields.length) {
        _fail(model, 'Duplicate physical column name.');
      }
      final entity = ModelEntity(
        name,
        table,
        row,
        fields,
        constructorNamedFields: constructorNamedFields,
      );
      entities[name] = entity;
    }
    if (entities.isEmpty) {
      throw const GenerationException('No entity<Model>() declarations found.');
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
      if (method == 'check') {
        final expression = call.argumentList.arguments.first.argumentExpression;
        if (expression is! SimpleStringLiteral ||
            expression.value.trim().isEmpty) {
          _fail(expression, 'CHECK requires a non-empty SQL string literal.');
        }
        final name = _named(call, 'name') is NullLiteral
            ? null
            : namedString(call, 'name') ?? snakeCase(variable.name.lexeme);
        final check = CheckSchema.forDialects(
          name,
          sqlite: namedString(call, 'sqlite') ?? expression.value,
          postgres: namedString(call, 'postgres') ?? expression.value,
          mysql: namedString(call, 'mysql') ?? expression.value,
          mariadb: namedString(call, 'mariadb') ?? expression.value,
        );
        if (SqlDialect.values.every(
              (d) => check.expression(d).trim().isEmpty,
            ) ||
            name != null &&
                (name.isEmpty || entity.checks.any((c) => c.name == name))) {
          _fail(
            call,
            'CHECK expressions and names must be non-empty; names must be unique per table.',
          );
        }
        entity.checks.add(check);
        continue;
      }
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
            ModelIndex(
              namedString(call, 'name') ?? snakeCase(variable.name.lexeme),
              keys,
              _named(call, 'unique')?.toSource() == 'true',
            ),
          );
      }
    }
    for (final variable in variables) {
      final call = variable.initializer;
      if (call is! MethodInvocation ||
          !{'references', 'relatesTo'}.contains(call.methodName.name) ||
          call.methodName.element?.library?.uri.toString() !=
              schemaDeclarationUri) {
        continue;
      }
      final foreignKey = call.methodName.name == 'references';
      final kind = foreignKey ? 'Foreign key' : 'Relationship';
      if (call.target is! MethodInvocation) {
        _fail(call, '${call.methodName.name} must follow entity.key().');
      }
      final (source, local) = _key(call.target!);
      final (target, remote) = _key(
        call.argumentList.arguments.first.argumentExpression,
      );
      if (local.length != remote.length) {
        _fail(call, '$kind arity mismatch.');
      }
      final targets = [
        target.primaryKey,
        ...target.uniqueKeys,
        for (final i in target.indexes)
          if (i.unique) i.keys,
      ];
      if (foreignKey && !targets.any((key) => sameStrings(key, remote))) {
        _fail(
          call,
          'Foreign key target must be a primary or unique key in the same column order.',
        );
      }
      for (var i = 0; i < local.length; i++) {
        if (source.field(local[i]).storage != target.field(remote[i]).storage) {
          _fail(call, '$kind storage types differ.');
        }
      }
      final action =
          _named(call, 'onDelete')?.toSource().split('.').last ?? 'restrict';
      final onDelete = !foreignKey
          ? null
          : switch (action) {
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
        ModelRelation(variable.name.lexeme, target, local, remote, onDelete),
        call,
      );
      final inverse = namedString(call, 'inverse');
      if (inverse != null) {
        _addEdge(
          target,
          ModelRelation(
            inverse,
            source,
            remote,
            local,
            onDelete,
            inverse: true,
          ),
          call,
        );
      }
    }
    final indexNames = <String>{};
    final symbols = <String>{'appSchema', 'AppTables'};
    for (final entity in entities.values) {
      for (final symbol in [
        entity.fieldsType,
        entity.setType,
        '${entity.symbol}Updates',
        '${entity.name}Schema',
        '${entity.name}Table',
        for (final field in entity.fields) columnSymbol(entity, field),
      ]) {
        if (!symbols.add(symbol)) {
          throw GenerationException(
            'Generated symbol $symbol is ambiguous. Rename an entity or Dart field while keeping its physical SQL name.',
          );
        }
      }
      if (entity.fields.every((f) => f.computed != null)) {
        throw GenerationException(
          '${entity.name} needs at least one ordinary column.',
        );
      }
      for (final key in entity.primaryKey) {
        if (entity.field(key).nullable) {
          throw GenerationException(
            '${entity.name} primary keys cannot be nullable.',
          );
        }
      }
      for (final f in entity.fields.where((f) => f.generated)) {
        if (f.storage != 'integer' ||
            !sameStrings(entity.primaryKey, [f.name])) {
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

  (List<ModelField>, Set<String>) _readClass(ClassDeclaration declaration) {
    final primary = declaration.namePart;
    if (primary is! PrimaryConstructorDeclaration ||
        primary.typeName.lexeme.startsWith('_') ||
        declaration.finalKeyword == null ||
        declaration.abstractKeyword != null ||
        declaration.extendsClause != null ||
        declaration.implementsClause != null ||
        declaration.withClause != null ||
        declaration.body.members.isNotEmpty ||
        primary.typeParameters != null ||
        primary.constructorName != null) {
      _fail(
        declaration,
        'Use a public final class with an unnamed primary constructor, declaring fields only, and no inheritance or type parameters. Put behavior in extensions.',
      );
    }
    final fields = <ModelField>[];
    final named = <String>{};
    for (final parameter in primary.formalParameters.parameters) {
      if (!parameter.isFinal ||
          !parameter.isRequired ||
          parameter.defaultClause != null ||
          parameter.functionTypedSuffix != null ||
          parameter.type == null ||
          parameter.name == null ||
          parameter.name!.lexeme.startsWith('_')) {
        _fail(
          parameter,
          'Model parameters must be public, explicitly typed, required final declaring fields without Dart defaults. Use @Default.sql or @ClientDefault for insert defaults.',
        );
      }
      final name = parameter.name!.lexeme;
      fields.add(
        readField(parameter, name, parameter.type!.type, parameter.metadata),
      );
      if (parameter.isNamed) named.add(name);
    }
    return (fields, named);
  }

  ModelField readField(
    AstNode field,
    String name,
    DartType? type,
    Iterable<Annotation> metadata,
  ) {
    if (type == null) _fail(field, 'Cannot resolve the field type.');
    final nullable = typeSystem.isNullable(type);
    if ({'table', 'column', 'readColumn'}.contains(name)) {
      _fail(
        field,
        'Field name $name conflicts with the fields API. Use another Dart name and @ColumnName.',
      );
    }
    var id = false, generated = false, unique = false;
    String? column, defaultSql, clientDefault;
    ComputedColumn? computed;
    int? integerBits;
    int? decimalPrecision, decimalScale, temporalPrecision;
    Annotation? custom;
    for (final annotation in metadata) {
      final value = annotation.elementAnnotation?.computeConstantValue();
      final annotationType = value?.type;
      if (annotationType is! InterfaceType ||
          annotationType.element.library.uri.toString() !=
              schemaDeclarationUri) {
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
        case 'Computed':
          if (computed != null) {
            _fail(annotation, 'Computed may only appear once.');
          }
          final sql = value!.getField('expression')!.toStringValue()!;
          computed = ComputedColumn.forDialects(
            sqlite: value.getField('sqlite')?.toStringValue() ?? sql,
            postgres: value.getField('postgres')?.toStringValue() ?? sql,
            mysql: value.getField('mysql')?.toStringValue() ?? sql,
            mariadb: value.getField('mariadb')?.toStringValue() ?? sql,
            storage:
                ComputedStorage.values[value
                    .getField('storage')!
                    .getField('index')!
                    .toIntValue()!],
          );
          if (SqlDialect.values.every(
            (d) => computed!.expression(d).trim().isEmpty,
          )) {
            _fail(annotation, 'Computed SQL expressions must be non-empty.');
          }
        case 'ClientDefault':
          if (clientDefault != null) {
            _fail(annotation, 'ClientDefault may only appear once.');
          }
          final reference =
              annotation.arguments!.arguments.single.argumentExpression;
          final signature = reference.staticType;
          if (signature is! FunctionType ||
              signature.typeParameters.isNotEmpty ||
              signature.formalParameters.any((p) => p.isRequired) ||
              signature.returnType is DynamicType ||
              !typeSystem.isSubtypeOf(signature.returnType, type)) {
            _fail(
              annotation,
              'ClientDefault requires a synchronous, zero-required-argument factory returning $type.',
            );
          }
          final function = value!.getField('factory')?.toFunctionValue();
          if (function == null) {
            _fail(
              annotation,
              'ClientDefault requires a constant function reference.',
            );
          }
          clientDefault = names.factoryReference(
            reference,
            function,
            signature,
          );
        case 'IntegerBits':
          if (integerBits != null) {
            _fail(annotation, 'IntegerBits may only appear once.');
          }
          integerBits = value!.getField('value')!.toIntValue();
        case 'UseCodec':
          if (custom != null) {
            _fail(annotation, 'UseCodec may only appear once.');
          }
          custom = annotation;
        case 'TemporalPrecision':
          if (temporalPrecision != null) {
            _fail(annotation, 'TemporalPrecision may only appear once.');
          }
          temporalPrecision = value!.getField('digits')!.toIntValue();
        case 'DecimalDigits':
          if (decimalPrecision != null) {
            _fail(annotation, 'DecimalDigits may only appear once.');
          }
          decimalPrecision = value!.getField('precision')!.toIntValue();
          decimalScale = value.getField('scale')!.toIntValue();
        default:
          _fail(annotation, 'Unsupported ORM annotation.');
      }
    }
    String storage, codec;
    if (computed != null &&
        (generated || defaultSql != null || clientDefault != null)) {
      _fail(field, 'Computed columns cannot have identity or insert defaults.');
    }
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
          codecType.element.library.uri.toString() != codecLibraryUri) {
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
        'decimal',
        'real',
        'text',
        'boolean',
        'instant',
        'date',
        'time',
        'local_datetime',
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
            ...valueLibraryUris,
          }.contains(type.element.library.uri.toString())) {
        _fail(field, 'This type needs an explicit @UseCodec.');
      }
      final mapping = switch (type.element.name) {
        'int' => ('integer', 'integer'),
        'String' => ('text', 'text'),
        'double' => ('real', 'real'),
        'bool' => ('boolean', 'boolean'),
        'DateTime' => ('instant', 'dateTime'),
        'LocalDate' => ('date', 'date'),
        'LocalTime' => ('time', 'time'),
        'LocalDateTime' => ('local_datetime', 'localDateTime'),
        'BigInt' => ('bigint', 'bigint'),
        'Decimal' => ('decimal', 'decimal'),
        'Uint8List' => ('blob', 'bytes'),
        _ => throw GenerationException(
          'Unsupported field type $type; declare @UseCodec.',
        ),
      };
      storage = mapping.$1;
      codec = 'Codecs.${mapping.$2}${nullable ? '.nullable()' : ''}';
    }
    if (decimalPrecision != null &&
        (storage != 'decimal' ||
            decimalPrecision < 1 ||
            decimalPrecision > 1000 ||
            decimalScale! < -1000 ||
            decimalScale > 1000)) {
      _fail(
        field,
        'DecimalDigits requires decimal storage, precision 1..1000 and scale -1000..1000.',
      );
    }
    if (temporalPrecision != null &&
        (!{'time', 'local_datetime', 'instant'}.contains(storage) ||
            temporalPrecision < 0 ||
            temporalPrecision > 6)) {
      _fail(
        field,
        'TemporalPrecision requires time, local timestamp or instant storage and 0..6 digits.',
      );
    }
    if (integerBits != null &&
        (storage != 'integer' || !{16, 32, 64}.contains(integerBits))) {
      _fail(
        field,
        'IntegerBits requires integer storage and a width of 16, 32 or 64.',
      );
    }
    return ModelField(
      name: name,
      column: column ?? snakeCase(name),
      type: names.type(type),
      codec: codec,
      storage: storage,
      nullable: nullable,
      id: id,
      generated: generated,
      unique: unique,
      defaultSql: defaultSql,
      clientDefault: clientDefault,
      computed: computed,
      integerBits: integerBits,
      decimalPrecision: decimalPrecision,
      decimalScale: decimalScale,
      temporalPrecision: temporalPrecision,
    );
  }

  (ModelEntity, List<String>) _key(Expression expression) {
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

  List<String> _selector(Expression expression, ModelEntity entity) {
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

  void _addEdge(ModelEntity source, ModelRelation edge, AstNode node) {
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

  String? namedString(MethodInvocation call, String name) {
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
