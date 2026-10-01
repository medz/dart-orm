import 'dart:convert';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/ast/token.dart' show Keyword;
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_system.dart';

import '../../../schema_model.dart';
import '../model.dart';
import '../source.dart';
import '../types.dart';
import 'diagnostics.dart';

const annotationLibrary = 'package:orm/src/schema/annotations.dart';

List<ElementAnnotation> _annotations(Element element, String name) => [
  for (final annotation in element.metadata.annotations)
    if (annotation.computeConstantValue()?.type
        case InterfaceType(:final element)
        when element.name == name &&
            element.library.uri.toString() == annotationLibrary)
      annotation,
];

String? _annotationName(ElementAnnotation annotation) {
  final type = annotation.computeConstantValue()?.type;
  return type is InterfaceType &&
          type.element.library.uri.toString() == annotationLibrary
      ? type.element.name
      : null;
}

bool isAnnotatedModel(Element element) =>
    element is ClassElement && _annotations(element, 'Model').isNotEmpty;

/// Resolves original class identities from roots, exports and relation targets.
/// Unrelated imports do not become model roots.
Future<List<ClassDeclaration>> annotatedSources(
  List<CompilationUnit> roots,
  Future<CompilationUnit> Function(LibraryElement) resolve,
) async {
  final units = <LibraryElement, CompilationUnit>{
    for (final unit in roots) unit.declaredFragment!.element: unit,
  };
  final pending = <ClassElement>[
    for (final unit in roots)
      for (final declaration in unit.declarations.whereType<ClassDeclaration>())
        if (isAnnotatedModel(declaration.declaredFragment!.element))
          declaration.declaredFragment!.element,
    for (final library in units.keys)
      for (final element in library.exportNamespace.definedNames2.values)
        if (element is ClassElement && isAnnotatedModel(element)) element,
  ];
  final result = <ClassElement, ClassDeclaration>{};
  for (var index = 0; index < pending.length; index++) {
    final element = pending[index];
    if (result.containsKey(element)) continue;
    final unit = units[element.library] ??= await resolve(element.library);
    final declaration = unit.declarations
        .whereType<ClassDeclaration>()
        .firstWhere((node) => node.declaredFragment!.element == element);
    result[element] = declaration;
    for (final owner in <Element>[
      element,
      ...element.fields,
      ...element.constructors.expand(
        (constructor) => constructor.formalParameters,
      ),
    ]) {
      for (final annotation in _annotations(owner, 'Relation')) {
        final target = annotation
            .computeConstantValue()!
            .getField('target')
            ?.toTypeValue();
        if (target is InterfaceType && isAnnotatedModel(target.element)) {
          pending.add(target.element as ClassElement);
        }
      }
    }
  }
  return result.values.toList();
}

/// Reads annotated scalar DTOs without instantiating application classes.
final class AnnotationReader(
  final List<ClassDeclaration> declarations,
  final DartNames names, {
  final SqlDialect? dialect,
  final String? defaultNamespace,
}) {
  final _annotationNodes = <ElementAnnotation, Annotation>{};
  final _models = <ClassElement, ModelEntity>{};
  final _nodes = <ModelEntity, ClassDeclaration>{};
  final _types = <ModelField, DartType>{};
  final _codecs = <ModelField, Object>{};
  final _relations = <(ModelEntity, String?, ElementAnnotation)>[];

  List<ModelEntity> read() {
    for (final node in declarations) {
      node.accept(_AnnotationNodes(_annotationNodes));
    }
    _validateMetadata();
    for (final node in declarations) {
      _readModel(node);
    }
    for (final (source, field, annotation) in _relations) {
      _relation(source, field, annotation);
    }
    _validate();
    return _models.values.toList()
      ..sort((a, b) => a.identity.compareTo(b.identity));
  }

  void _validateMetadata() {
    for (final entry in _annotationNodes.entries) {
      final name = _annotationName(entry.key);
      if (name == null) continue;
      final node = entry.value;
      final parent = node.parent;
      final isClass = parent is ClassDeclaration;
      final parameterOwner = parent is FormalParameter
          ? parent.declaredFragment?.element.enclosingElement
          : null;
      final isField =
          parent is FieldDeclaration ||
          parameterOwner is ConstructorElement && parameterOwner.name == 'new';
      final allowed = switch (name) {
        'Model' || 'Index' || 'Check' => isClass,
        'Unique' || 'Relation' => isClass || isField,
        _ => isField,
      };
      if (!allowed || parent is FieldDeclaration && parent.isStatic) {
        failAt(node, 'ANNOTATION', '@$name is not valid on this declaration.');
      }
    }
  }

  void _physicalName(String value, AstNode node, {bool component = false}) {
    if (value.isEmpty ||
        value.contains('\u0000') ||
        component && value.contains('.') ||
        dialect == SqlDialect.postgres && utf8.encode(value).length > 63) {
      failAt(
        node,
        'NAME',
        'Physical names must be non-empty, contain no NUL, fit PostgreSQL limits, and keep table/namespace components separate.',
      );
    }
  }

  void _readModel(ClassDeclaration node) {
    final element = node.declaredFragment!.element;
    final modelAnnotation = _one(element, 'Model')!;
    final metadata = modelAnnotation.computeConstantValue()!;
    final className = element.name!;
    final name = '${className[0].toLowerCase()}${className.substring(1)}';
    if (element.isPrivate ||
        element.isAbstract ||
        element.typeParameters.isNotEmpty ||
        Keyword.keywords[name]?.isReservedWord == true ||
        databaseMembers.contains(name)) {
      failAt(
        node,
        'MODEL',
        'Use a public concrete non-generic model class whose name does not shadow a database member.',
      );
    }
    if (element.supertype?.isDartCoreObject != true ||
        node.withClause != null) {
      failAt(
        node,
        'MODEL',
        'Mapped DTOs must directly extend Object without mixins. Inherited storage and constructor effects are not supported.',
      );
    }
    final constructor = element.constructors
        .where((c) => c.name == 'new')
        .firstOrNull;
    if (constructor == null ||
        constructor.isFactory ||
        constructor.formalParameters.any((p) => !p.isNamed)) {
      failAt(
        node,
        'MODEL',
        'A model needs an unnamed generative constructor with named parameters.',
      );
    }
    FunctionBody? constructorBody;
    Iterable<ConstructorInitializer> initializers = const [];
    if (node.namePart case PrimaryConstructorDeclaration(:final body?)) {
      constructorBody = body.body;
      initializers = body.initializers;
    } else {
      final declaration = node.body.members
          .whereType<ConstructorDeclaration>()
          .where((member) => member.declaredFragment?.element == constructor)
          .firstOrNull;
      constructorBody = declaration?.body;
      initializers = declaration?.initializers ?? const [];
    }
    if (constructorBody != null &&
            constructorBody is! EmptyFunctionBody &&
            !(constructorBody is BlockFunctionBody &&
                constructorBody.block.statements.isEmpty) ||
        initializers.any((initializer) => initializer is! AssertInitializer)) {
      failAt(
        node,
        'MODEL',
        'The mapped constructor must directly store supplied values, with no executable body or transforming initializers.',
      );
    }
    final parameterNodes = <String, FormalParameter>{};
    node.accept(_ParameterNodes(parameterNodes, constructor));
    final fields = <ModelField>[];
    for (final parameter in constructor.formalParameters) {
      final parameterNode = parameterNodes[parameter.name] ?? node;
      final field = element.fields
          .where(
            (f) =>
                !f.isStatic &&
                f.name == parameter.name &&
                !f.isOriginGetterSetter,
          )
          .firstOrNull;
      final owners = <Element>[parameter, ?field];
      if (_combined(owners, 'Ignore', parameterNode) != null) {
        if (owners.any(
          (owner) => owner.metadata.annotations.any(
            (annotation) =>
                _annotationName(annotation) != null &&
                _annotationName(annotation) != 'Ignore',
          ),
        )) {
          failAt(
            parameterNode,
            'ANNOTATION',
            '@Ignore cannot be combined with persistent mapping metadata.',
          );
        }
        if (parameter.isRequired) {
          failAt(
            parameterNode,
            'FIELD',
            'An ignored constructor parameter must be optional.',
          );
        }
        continue;
      }
      if (field == null || parameter is! FieldFormalParameterElement) {
        failAt(
          parameterNode,
          'FIELD',
          'Persistent parameters must directly declare or initialize fields (final T field or this.field). Use @Ignore() for optional nonpersistent inputs.',
        );
      }
      if (field.isLate ||
          field.isPrivate ||
          {
            'table',
            'column',
            'readColumn',
            'hashCode',
            'runtimeType',
            'toString',
            'noSuchMethod',
          }.contains(field.name)) {
        failAt(
          parameterNode,
          'FIELD',
          'Persistent fields must be public, initialized, and not shadow the generated fields API.',
        );
      }
      final typeSystem = element.library.typeSystem;
      if (!typeSystem.isSubtypeOf(field.type, parameter.type) ||
          !typeSystem.isSubtypeOf(parameter.type, field.type)) {
        failAt(
          parameterNode,
          'FIELD',
          'Constructor and stored field types must match.',
        );
      }
      final modelField = _field(
        field,
        parameter,
        owners,
        parameterNode,
        typeSystem,
      );
      fields.add(modelField);
    }
    for (final field in element.fields.where(
      (f) => !f.isStatic && !f.isOriginGetterSetter,
    )) {
      if (!fields.any((mapped) => mapped.name == field.name) &&
          _annotations(field, 'Ignore').isEmpty &&
          !constructor.formalParameters.any(
            (p) => p.name == field.name && _annotations(p, 'Ignore').isNotEmpty,
          )) {
        failAt(
          node,
          'FIELD',
          'Instance field ${field.name} is not supplied by the unnamed constructor. Map it there or mark it @Ignore().',
        );
      }
    }
    if (fields.isEmpty) {
      failAt(node, 'FIELD', 'A model needs at least one scalar field.');
    }
    final explicitNamespace = metadata.getField('namespace')?.toStringValue();
    if (dialect != null &&
        dialect != SqlDialect.postgres &&
        (explicitNamespace != null || defaultNamespace != null)) {
      failAt(
        node,
        'NAMESPACE',
        'Physical namespaces are supported only by PostgreSQL.',
      );
    }
    final namespace =
        explicitNamespace ??
        defaultNamespace ??
        (dialect == SqlDialect.postgres ? 'public' : null);
    _physicalName(
      metadata.getField('table')?.toStringValue() ?? className,
      _node(modelAnnotation),
      component: true,
    );
    if (namespace != null) {
      _physicalName(namespace, _node(modelAnnotation), component: true);
    }
    names.exportType(element.thisType);
    final model = ModelEntity(
      name,
      metadata.getField('table')?.toStringValue() ?? className,
      className,
      fields,
      namespace: namespace,
      sourceType: names.type(element.thisType),
    );
    _models[element] = model;
    _nodes[model] = node;
    for (final annotation in _annotations(element, 'Unique')) {
      model.uniqueKeys.add(
        _keys(
          annotation.computeConstantValue()!,
          'fields',
          model,
          _node(annotation),
        ),
      );
    }
    for (final annotation in _annotations(element, 'Index')) {
      final value = annotation.computeConstantValue()!;
      model.indexes.add(
        ModelIndex(
          value.getField('name')!.toStringValue()!,
          _keys(value, 'fields', model, _node(annotation)),
          value.getField('unique')!.toBoolValue()!,
        ),
      );
    }
    for (final annotation in _annotations(element, 'Check')) {
      final value = annotation.computeConstantValue()!;
      final sql = value.getField('expression')!.toStringValue()!;
      final check = CheckSchema.forDialects(
        value.getField('name')?.toStringValue(),
        sqlite: value.getField('sqlite')?.toStringValue() ?? sql,
        postgres: value.getField('postgres')?.toStringValue() ?? sql,
        mysql: value.getField('mysql')?.toStringValue() ?? sql,
        mariadb: value.getField('mariadb')?.toStringValue() ?? sql,
      );
      if (SqlDialect.values.every(
            (dialect) => check.expression(dialect).trim().isEmpty,
          ) ||
          check.name != null &&
              (check.name!.isEmpty ||
                  model.checks.any((old) => old.name == check.name))) {
        failAt(
          _node(annotation),
          'CHECK',
          'Check expressions need SQL and distinct non-empty optional names.',
        );
      }
      model.checks.add(check);
    }
    for (final annotation in _annotations(element, 'Relation')) {
      _relations.add((model, null, annotation));
    }
    for (final parameter in constructor.formalParameters) {
      final field = element.fields
          .where((f) => f.name == parameter.name)
          .firstOrNull;
      final annotation = _combined(
        [parameter, ?field],
        'Relation',
        parameterNodes[parameter.name] ?? node,
      );
      if (annotation != null) {
        _relations.add((model, parameter.name, annotation));
      }
    }
  }

  ModelField _field(
    FieldElement field,
    FormalParameterElement parameter,
    List<Element> owners,
    AstNode node,
    TypeSystem types,
  ) {
    final type = field.type;
    final base = types.promoteToNonNull(type);
    if (base is DynamicType) {
      failAt(node, 'FIELD', 'Persistent fields cannot use dynamic.');
    }
    final nullable = types.isNullable(type);
    final columnAnnotation = _combined(owners, 'Column', node);
    final column = columnAnnotation?.computeConstantValue();
    final custom = column?.getField('codec');
    final labels = column?.getField('labels')?.toMapValue();
    String storage;
    String codec;
    Object codecIdentity;
    if (custom != null && !custom.isNull) {
      if (labels != null) {
        failAt(node, 'CODEC', 'Use codec or enum labels, not both.');
      }
      final argument = _argument(_node(columnAnnotation!), 'codec');
      if (argument == null) {
        failAt(node, 'CODEC', 'Use a public const codec reference in @Column.');
      }
      final codecType = argument.staticType;
      if (codecType is! InterfaceType) {
        failAt(node, 'CODEC', 'Use a public const Codec.');
      }
      final domain = codecType.typeArguments.single;
      if (!types.isSubtypeOf(base, types.promoteToNonNull(domain)) ||
          !types.isSubtypeOf(types.promoteToNonNull(domain), base) ||
          !nullable && types.isNullable(domain)) {
        failAt(
          node,
          'CODEC',
          'Codec value type must match the persistent field.',
        );
      }
      storage = custom.getField('sqlType')?.toStringValue() ?? '';
      codec = names.codecReference(argument);
      codecIdentity = custom;
      if (nullable && !types.isNullable(domain)) codec += '.nullable()';
    } else {
      if (base is! InterfaceType) {
        failAt(
          node,
          'CODEC',
          'Persistent record values require a public const codec.',
        );
      }
      if (labels != null && base.element is! EnumElement) {
        failAt(node, 'ENUM', 'Storage labels require an enum field.');
      }
      final uri = base.element.library.uri.toString();
      final name = base.element.name;
      final mapping = switch ((uri, name)) {
        ('dart:core', 'int') => ('integer', 'integer'),
        ('dart:core', 'String') => ('text', 'text'),
        ('dart:core', 'bool') => ('boolean', 'boolean'),
        ('dart:core', 'double') => ('real', 'real'),
        ('dart:core', 'BigInt') => ('bigint', 'bigint'),
        ('dart:core', 'DateTime') => ('instant', 'dateTime'),
        ('dart:typed_data', 'Uint8List') => ('blob', 'bytes'),
        (_, 'Decimal') when valueLibraryUris.contains(uri) => (
          'decimal',
          'decimal',
        ),
        (_, 'LocalDate') when valueLibraryUris.contains(uri) => (
          'date',
          'date',
        ),
        (_, 'LocalTime') when valueLibraryUris.contains(uri) => (
          'time',
          'time',
        ),
        (_, 'LocalDateTime') when valueLibraryUris.contains(uri) => (
          'local_datetime',
          'localDateTime',
        ),
        (_, 'SqlJson') when valueLibraryUris.contains(uri) => (
          'json',
          'jsonDocument',
        ),
        _ => null,
      };
      if (mapping != null) {
        storage = mapping.$1;
        codec = 'Codecs.${mapping.$2}';
      } else if (base.element is EnumElement) {
        storage = 'text';
        final symbol = names.type(base);
        final enumFields = base.element.fields
            .where((f) => f.isEnumConstant)
            .toList();
        final storageLabels = <String, String>{};
        if (labels == null) {
          for (final field in enumFields) {
            storageLabels[field.name!] = field.name!;
          }
        } else {
          for (final entry in labels.entries) {
            final key = entry.key!;
            final index = key.getField('index')?.toIntValue();
            if (key.type != base ||
                index == null ||
                index >= enumFields.length) {
              failAt(
                node,
                'ENUM',
                'Every storage label must name a value of $base.',
              );
            }
            storageLabels[enumFields[index].name!] = entry.value!
                .toStringValue()!;
          }
          if (storageLabels.length != enumFields.length ||
              storageLabels.values.toSet().length != enumFields.length) {
            failAt(
              node,
              'ENUM',
              'Provide distinct storage labels for every enum value.',
            );
          }
        }
        codec =
            'Codecs.enumeration<$symbol>({${enumFields.map((field) => '$symbol.${field.name}: ${dartLiteral(storageLabels[field.name]!)}').join(', ')}})';
      } else {
        failAt(
          node,
          'CODEC',
          'Unsupported persistent type $type. Declare a public const codec with @Column(codec: ...).',
        );
      }
      codecIdentity = codec;
      if (nullable) codec += '.nullable()';
    }
    if (!{
      'integer',
      'bigint',
      'decimal',
      'text',
      'real',
      'boolean',
      'instant',
      'date',
      'time',
      'local_datetime',
      'blob',
      'json',
    }.contains(storage)) {
      failAt(node, 'CODEC', 'The codec must use a supported storage type.');
    }
    final id = _combined(owners, 'Id', node)?.computeConstantValue();
    final generated = id?.getField('generated')?.toBoolValue() ?? false;
    final unique = _combined(owners, 'Unique', node)?.computeConstantValue();
    if (unique != null &&
        unique.getField('fields')!.toListValue()!.isNotEmpty) {
      failAt(
        node,
        'KEY',
        'Put composite @Unique field lists on the model class.',
      );
    }
    final dbAnnotation = _combined(owners, 'DatabaseDefault', node);
    final database = dbAnnotation?.computeConstantValue();
    String? defaultSql;
    if (database != null) {
      defaultSql = database.getField('expression')?.toStringValue();
      if (defaultSql == null) {
        final value = database.getField('value')!;
        if (custom != null && !custom.isNull && !value.isNull) {
          failAt(
            _node(dbAnnotation!),
            'DEFAULT',
            'Custom codecs require DatabaseDefault.sql with an already encoded database expression. Generation never executes application encoders.',
          );
        }

        if (!types.isSubtypeOf(value.type!, type) && !value.isNull ||
            value.isNull && !nullable) {
          failAt(
            _node(dbAnnotation!),
            'DEFAULT',
            'Database default must match the field type and nullability.',
          );
        }
        if (labels != null &&
            value.type is InterfaceType &&
            (value.type as InterfaceType).element is EnumElement) {
          final label = labels[value]?.toStringValue();
          if (label == null) {
            failAt(
              node,
              'DEFAULT',
              'The default enum value needs a storage label.',
            );
          }
          defaultSql = "'${label.replaceAll("'", "''")}'";
        } else {
          defaultSql = _sqlConstant(value, _node(dbAnnotation!));
        }
      }
      if (defaultSql.trim().isEmpty) {
        failAt(node, 'DEFAULT', 'Database SQL defaults cannot be empty.');
      }
    }
    final clientAnnotation = _combined(owners, 'ClientDefault', node);
    String? clientDefault;
    if (clientAnnotation != null) {
      final expression = _node(clientAnnotation)
          .arguments!
          .arguments
          .single
          .argumentExpression;
      final function = clientAnnotation
          .computeConstantValue()!
          .getField('factory')!
          .toFunctionValue();
      final signature = expression.staticType;
      if (function == null ||
          signature is! FunctionType ||
          signature.typeParameters.isNotEmpty ||
          signature.formalParameters.any((p) => p.isRequired) ||
          signature.returnType is DynamicType ||
          !types.isSubtypeOf(signature.returnType, type)) {
        failAt(
          expression,
          'DEFAULT',
          'Use a public synchronous factory returning $type without required arguments.',
        );
      }
      clientDefault = names.factoryReference(expression, function, signature);
    } else if (!generated && defaultSql == null && parameter.hasDefaultValue) {
      final value = parameter.computeConstantValue();
      if (value == null) {
        failAt(node, 'DEFAULT', 'Cannot resolve constructor constant default.');
      }
      clientDefault = '() => ${_constructorDefault(value, type, node)}';
    }
    final computedMetadata = _combined(
      owners,
      'Computed',
      node,
    )?.computeConstantValue();
    ComputedColumn? computed;
    if (computedMetadata != null) {
      if (generated ||
          defaultSql != null ||
          clientAnnotation != null ||
          parameter.hasDefaultValue) {
        failAt(
          node,
          'DEFAULT',
          'Computed columns cannot declare identity or insert defaults.',
        );
      }
      final expression = computedMetadata
          .getField('expression')!
          .toStringValue()!;
      computed = ComputedColumn.forDialects(
        sqlite:
            computedMetadata.getField('sqlite')?.toStringValue() ?? expression,
        postgres:
            computedMetadata.getField('postgres')?.toStringValue() ??
            expression,
        mysql:
            computedMetadata.getField('mysql')?.toStringValue() ?? expression,
        mariadb:
            computedMetadata.getField('mariadb')?.toStringValue() ?? expression,
        storage:
            ComputedStorage.values[computedMetadata
                .getField('storage')!
                .getField('index')!
                .toIntValue()!],
      );
      if (SqlDialect.values.every(
        (dialect) => computed!.expression(dialect).trim().isEmpty,
      )) {
        failAt(
          node,
          'COLUMN',
          'Computed SQL must be non-empty for at least one database.',
        );
      }
    }
    final bits = column?.getField('bits')?.toIntValue();
    final precision = column?.getField('precision')?.toIntValue();
    final scale = column?.getField('scale')?.toIntValue();
    if (bits != null &&
        (storage != 'integer' || !{16, 32, 64}.contains(bits))) {
      failAt(node, 'STORAGE', 'Integer bits must be 16, 32 or 64.');
    }
    if (storage == 'decimal') {
      if (scale != null && precision == null ||
          precision != null &&
              (precision < 1 ||
                  precision > 1000 ||
                  (scale ?? 0) < -1000 ||
                  (scale ?? 0) > 1000)) {
        failAt(
          node,
          'STORAGE',
          'Decimal precision must be 1..1000; scale -1000..1000 requires precision.',
        );
      }
    } else if (scale != null ||
        precision != null &&
            (!{'instant', 'time', 'local_datetime'}.contains(storage) ||
                precision < 0 ||
                precision > 6)) {
      failAt(node, 'STORAGE', 'Temporal precision must be 0..6.');
    }
    _physicalName(
      column?.getField('name')?.toStringValue() ?? snakeCase(field.name!),
      node,
    );
    names.exportType(type);
    final result = ModelField(
      name: field.name!,
      column:
          column?.getField('name')?.toStringValue() ?? snakeCase(field.name!),
      type: names.type(type),
      codec: codec,
      storage: storage,
      nullable: nullable,
      id: id != null,
      generated: generated,
      unique: unique != null,
      defaultSql: defaultSql,
      clientDefault: clientDefault,
      computed: computed,
      integerBits: bits,
      decimalPrecision: storage == 'decimal' ? precision : null,
      decimalScale: scale,
      temporalPrecision: storage == 'decimal' ? null : precision,
    );
    _types[result] = type;
    _codecs[result] = codecIdentity;
    return result;
  }

  Annotation _node(ElementAnnotation annotation) =>
      _annotationNodes[annotation]!;

  ElementAnnotation? _one(Element element, String name) => _combined(
    [element],
    name,
    _annotations(element, name).isEmpty
        ? declarations.first
        : _node(_annotations(element, name).first),
  );

  ElementAnnotation? _combined(
    List<Element> owners,
    String name,
    AstNode node,
  ) {
    final annotations = <int, ElementAnnotation>{};
    for (final owner in owners) {
      for (final annotation in _annotations(owner, name)) {
        annotations[_node(annotation).offset] = annotation;
      }
    }
    if (annotations.length > 1) {
      failAt(
        node,
        'DUPLICATE',
        '@$name is declared more than once for the same field.',
      );
    }
    return annotations.values.firstOrNull;
  }

  List<String> _keys(
    DartObject value,
    String property,
    ModelEntity model,
    AstNode node,
  ) {
    final keys = [
      for (final item in value.getField(property)!.toListValue()!)
        item.toStringValue()!,
    ];
    if (keys.isEmpty || keys.toSet().length != keys.length) {
      failAt(
        node,
        'KEY',
        'A key requires a non-empty ordered list of distinct fields.',
      );
    }
    for (final key in keys) {
      if (!model.fields.any((f) => f.name == key)) {
        failAt(node, 'KEY', 'Unknown field ${model.row}.$key.');
      }
    }
    return keys;
  }

  void _relation(
    ModelEntity source,
    String? field,
    ElementAnnotation annotation,
  ) {
    final node = _node(annotation);
    final value = annotation.computeConstantValue()!;
    final targetType = value.getField('target')!.toTypeValue();
    final target = targetType is InterfaceType
        ? _models[targetType.element]
        : null;
    if (target == null) {
      failAt(
        node,
        'REFERENCE',
        'Relation target must be a reachable @Model class.',
      );
    }
    final name = value.getField('name')!.toStringValue()!;
    final local = field == null
        ? _keys(value, 'fields', source, node)
        : [field];
    if (field != null && value.getField('fields')!.toListValue()!.isNotEmpty) {
      failAt(node, 'REFERENCE', 'Put composite relations on the model class.');
    }
    if (local.any((key) => !source.fields.any((f) => f.name == key))) {
      failAt(
        node,
        'REFERENCE',
        'Relations must reference persistent scalar fields.',
      );
    }
    final single = value.getField('key')?.toStringValue();
    final keys = value.getField('keys')!.toListValue()!;
    if (single != null && keys.isNotEmpty) {
      failAt(node, 'REFERENCE', 'Use key or keys, not both.');
    }
    final remote = single != null
        ? [single]
        : keys.isEmpty
        ? target.primaryKey
        : _keys(value, 'keys', target, node);
    if (remote.isEmpty ||
        remote.length != local.length ||
        remote.toSet().length != remote.length ||
        remote.any((key) => !target.fields.any((f) => f.name == key))) {
      failAt(
        node,
        'REFERENCE',
        'Reference fields must exist and have matching non-empty arity.',
      );
    }
    final constraint = value.getField('constraint')!.toBoolValue()!;
    if (constraint &&
        ![
          target.primaryKey,
          ...target.uniqueKeys,
          for (final index in target.indexes)
            if (index.unique) index.keys,
        ].any((key) => sameStrings(key, remote))) {
      failAt(
        node,
        'REFERENCE',
        'Target fields must match an ordered primary or unique key.',
      );
    }
    final types = _nodes[source]!.declaredFragment!.element.library.typeSystem;
    for (var i = 0; i < local.length; i++) {
      final a = source.field(local[i]), b = target.field(remote[i]);
      final at = types.promoteToNonNull(_types[a]!),
          bt = types.promoteToNonNull(_types[b]!);
      if (a.storage != b.storage ||
          !types.isSubtypeOf(at, bt) ||
          !types.isSubtypeOf(bt, at) ||
          _codecs[a] != _codecs[b]) {
        failAt(
          node,
          'REFERENCE',
          'Reference ${a.name} -> ${b.name} requires matching value types, storage and codecs.',
        );
      }
    }
    final actionIndex = value
        .getField('onDelete')!
        .getField('index')!
        .toIntValue()!;
    final action = [
      'RESTRICT',
      'CASCADE',
      'SET NULL',
      'SET DEFAULT',
      'NO ACTION',
    ][actionIndex];
    if (constraint &&
        action == 'SET NULL' &&
        local.any((key) => !source.field(key).nullable)) {
      failAt(node, 'REFERENCE', 'SET NULL requires nullable source fields.');
    }
    _edge(
      source,
      ModelRelation(name, target, local, remote, constraint ? action : null),
      node,
    );
    final inverse = value.getField('inverse')?.toStringValue();
    if (inverse != null) {
      _edge(
        target,
        ModelRelation(
          inverse,
          source,
          remote,
          local,
          constraint ? action : null,
          inverse: true,
        ),
        node,
      );
    }
  }

  void _edge(ModelEntity source, ModelRelation edge, AstNode node) {
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(edge.name) ||
        Keyword.keywords[edge.name]?.isReservedWord == true ||
        {
          'table',
          'column',
          'readColumn',
          'hashCode',
          'runtimeType',
          'toString',
          'noSuchMethod',
        }.contains(edge.name) ||
        source.fields.any((f) => f.name == edge.name) ||
        source.edges.any((e) => e.name == edge.name)) {
      failAt(node, 'NAME', 'Invalid or duplicate relation name ${edge.name}.');
    }
    source.edges.add(edge);
  }

  void _validate() {
    final identities = <String>{},
        symbols = <String>{'appSchema', 'AppTables', ...generatedTypeNames};
    final indexes = <String>{};
    for (final model in _models.values) {
      final node = _nodes[model]!;
      if (!identities.add(model.identity)) {
        failAt(
          node,
          'DUPLICATE',
          'Duplicate physical table ${model.identity}.',
        );
      }
      if (model.fields.map((f) => f.column).toSet().length !=
          model.fields.length) {
        failAt(node, 'DUPLICATE', 'Duplicate physical column on ${model.row}.');
      }
      for (final symbol in [
        model.row,
        model.fieldsType,
        model.setType,
        '${model.symbol}Updates',
        '${model.binding}Schema',
        '${model.binding}Table',
        for (final field in model.fields) columnSymbol(model, field),
      ]) {
        if (!symbols.add(symbol)) {
          failAt(
            node,
            'NAME',
            'Generated symbol $symbol is ambiguous. Rename the Dart class or field and preserve its physical name explicitly.',
          );
        }
      }
      if (model.fields.every((field) => field.computed != null)) {
        failAt(
          node,
          'COLUMN',
          'A model needs at least one ordinary scalar column.',
        );
      }
      for (final key in model.primaryKey) {
        if (model.field(key).nullable) {
          failAt(node, 'KEY', 'Primary keys cannot be nullable.');
        }
      }
      for (final field in model.fields.where((f) => f.generated)) {
        if (field.storage != 'integer' ||
            !sameStrings(model.primaryKey, [field.name])) {
          failAt(
            node,
            'KEY',
            'Generated identity requires one integer-storage primary key.',
          );
        }
      }
      if (model.uniqueKeys.map((key) => key.join('\u0000')).toSet().length !=
          model.uniqueKeys.length) {
        failAt(node, 'DUPLICATE', 'Duplicate unique key on ${model.row}.');
      }
      for (final index in model.indexes) {
        _physicalName(index.name, node);
        if (!indexes.add('${model.namespace ?? ''}.${index.name}')) {
          failAt(node, 'DUPLICATE', 'Duplicate index name ${index.name}.');
        }
      }
      // Reuse physical identifier validation rather than deriving Dart names
      // from PostgreSQL namespaces. SQL generation quotes each identity part.
      model.snapshot();
    }
  }

  // Constant evaluation erases extension types. Preserve public references and
  // constructor syntax first; never emit an erased primitive as a domain type.
  String _constructorDefault(DartObject value, DartType type, AstNode node) {
    final expression = node is FormalParameter
        ? node.defaultClause?.value
        : null;
    if (expression != null) {
      final source = _constantExpression(expression);
      if (source != null) return source;
    }
    if (_containsExtension(type)) {
      failAt(
        node,
        'DEFAULT',
        'This constructor constant cannot preserve its extension-type identity in the generated client. Use a public const reference or @ClientDefault factory.',
      );
    }
    return _dartConstant(value, node);
  }

  bool _containsExtension(DartType type) => switch (type) {
    InterfaceType() =>
      type.element is ExtensionTypeElement ||
          type.typeArguments.any(_containsExtension),
    RecordType() =>
      type.positionalFields.any((field) => _containsExtension(field.type)) ||
          type.namedFields.any((field) => _containsExtension(field.type)),
    _ => false,
  };

  String? _constantExpression(Expression expression) {
    if (expression is SimpleStringLiteral) return dartLiteral(expression.value);
    if (expression is IntegerLiteral) return '${expression.value}';
    if (expression is DoubleLiteral && expression.value.isFinite) {
      return '${expression.value}';
    }
    if (expression is BooleanLiteral) return '${expression.value}';
    if (expression is NullLiteral) return 'null';
    if (expression is ParenthesizedExpression) {
      return _constantExpression(expression.expression);
    }
    if (expression is PrefixExpression && expression.operator.lexeme == '-') {
      final inner = _constantExpression(expression.operand);
      return inner == null ? null : '-($inner)';
    }
    final referenced = switch (expression) {
      Identifier() => expression.element,
      PropertyAccess() => expression.propertyName.element,
      _ => null,
    };
    final element = referenced is PropertyAccessorElement
        ? referenced.variable
        : referenced;
    if (element is VariableElement &&
        element.isConst &&
        element.isStatic &&
        !element.isPrivate) {
      return names.codecReference(expression);
    }
    if (expression is InstanceCreationExpression) {
      final constructor = expression.constructorName.element;
      if (constructor == null ||
          constructor.isPrivate ||
          constructor.enclosingElement.isPrivate) {
        return null;
      }
      final arguments = <String>[];
      for (final argument in expression.argumentList.arguments) {
        final value = _constantExpression(argument.argumentExpression);
        if (value == null) return null;
        arguments.add(
          argument is NamedArgument ? '${argument.name.lexeme}: $value' : value,
        );
      }
      final name = names.type(expression.staticType!);
      final suffix = constructor.name == 'new' ? '' : '.${constructor.name}';
      return 'const $name$suffix(${arguments.join(', ')})';
    }
    return null;
  }

  String _dartConstant(DartObject value, AstNode node) {
    if (value.isNull) return 'null';
    if (value.toStringValue() case final text?) return dartLiteral(text);
    if (value.toBoolValue() case final boolean?) return '$boolean';
    if (value.toIntValue() case final integer?) return '$integer';
    if (value.toDoubleValue() case final number? when number.isFinite) {
      return '$number';
    }
    final type = value.type;
    if (type is InterfaceType && type.element is EnumElement) {
      final index = value.getField('index')!.toIntValue()!;
      final field = type.element.fields
          .where((f) => f.isEnumConstant)
          .elementAt(index);
      return '${names.type(type)}.${field.name}';
    }
    if (type is InterfaceType) {
      final arguments = type.typeArguments.map(names.type).join(', ');
      if (value.toListValue() case final items?) {
        return 'const <$arguments>[${items.map((v) => _dartConstant(v, node)).join(', ')}]';
      }
      if (value.toSetValue() case final items?) {
        return 'const <$arguments>{${items.map((v) => _dartConstant(v, node)).join(', ')}}';
      }
      if (value.toMapValue() case final items?) {
        return 'const <$arguments>{${items.entries.map((e) => '${_dartConstant(e.key!, node)}: ${_dartConstant(e.value!, node)}').join(', ')}}';
      }
    }
    failAt(
      node,
      'DEFAULT',
      'This constructor constant cannot be emitted in an independent client library. Use a public @ClientDefault factory.',
    );
  }

  String _sqlConstant(DartObject value, AstNode node) {
    if (value.isNull) return 'NULL';
    if (value.toStringValue() case final text?) {
      return "'${text.replaceAll("'", "''")}'";
    }
    if (value.toBoolValue() case final boolean?) {
      return boolean ? 'true' : 'false';
    }
    if (value.toIntValue() case final integer?) return '$integer';
    if (value.toDoubleValue() case final number? when number.isFinite) {
      return '$number';
    }
    final type = value.type;
    if (type is InterfaceType && type.element is EnumElement) {
      final field = type.element.fields
          .where((f) => f.isEnumConstant)
          .elementAt(value.getField('index')!.toIntValue()!);
      return "'${field.name}'";
    }
    failAt(
      node,
      'DEFAULT',
      'Database defaults need a scalar constant or DatabaseDefault.sql.',
    );
  }
}

Expression? _argument(Annotation annotation, String name) {
  for (final argument in annotation.arguments?.arguments ?? <Argument>[]) {
    if (argument is NamedArgument && argument.name.lexeme == name) {
      return argument.argumentExpression;
    }
  }
  return null;
}

final class _ParameterNodes(
  final Map<String, FormalParameter> result,
  final ConstructorElement constructor,
) extends GeneralizingAstVisitor<void> {
  @override
  void visitFormalParameter(FormalParameter node) {
    if (node.declaredFragment?.element.enclosingElement == constructor &&
        node.name != null) {
      result[node.name!.lexeme] = node;
    }
    super.visitFormalParameter(node);
  }
}

final class _AnnotationNodes(final Map<ElementAnnotation, Annotation> result)
    extends RecursiveAstVisitor<void> {
  @override
  void visitAnnotation(Annotation node) {
    if (node.elementAnnotation case final element?) result[element] = node;
    super.visitAnnotation(node);
  }
}
