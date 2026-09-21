import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_system.dart';

import '../../../schema_model.dart';
import '../model.dart';
import '../source.dart';
import '../types.dart';
import 'syntax.dart';

(ModelField, DartType, Object) readColumn(
  RecordLiteralNamedField field,
  TypeSystem typeSystem,
  DartNames names,
) {
  final type = field.fieldExpression.staticType;
  if (type is! InterfaceType ||
      type.element.name != 'ColumnDefinition' ||
      type.element.library.uri.toString() != schemaDeclarationUri) {
    failAt(
      field,
      'COLUMN',
      'Every field must be a column declaration, such as text() or integer().',
    );
  }
  final name = field.name.lexeme;
  if ({
    'table',
    'column',
    'readColumn',
    'hashCode',
    'runtimeType',
    'toString',
    'noSuchMethod',
  }.contains(name)) {
    failAt(
      field,
      'NAME',
      'Field $name conflicts with the generated fields API. Use another Dart name and name: for SQL.',
    );
  }
  final valueType = type.typeArguments.single;
  if (valueType is DynamicType) {
    failAt(
      field,
      'COLUMN',
      'Stored columns require a concrete value type, not dynamic.',
    );
  }
  final nullable = typeSystem.isNullable(valueType);
  var expression = field.fieldExpression;
  ComputedColumn? computed;
  Expression? nullableFactory;
  final modifiers = <String>{};
  while (expression is MethodInvocation &&
      expression.target != null &&
      callElement(expression)?.enclosingElement?.name == 'ColumnDefinition') {
    final method = callName(expression);
    if (!modifiers.add(method)) {
      failAt(expression, 'DUPLICATE', '$method is declared twice on $name.');
    }
    switch (method) {
      case 'nullable':
        nullableFactory = namedArgument(expression, 'clientDefault');
        break;
      case 'identity':
        break;
      case 'computed':
        final sql = stringValue(positionalArguments(expression).single);
        computed = ComputedColumn.forDialects(
          sqlite: namedString(expression, 'sqlite') ?? sql,
          postgres: namedString(expression, 'postgres') ?? sql,
          mysql: namedString(expression, 'mysql') ?? sql,
          mariadb: namedString(expression, 'mariadb') ?? sql,
          storage: enumName(namedArgument(expression, 'storage')) == 'virtual'
              ? ComputedStorage.virtual
              : ComputedStorage.stored,
        );
        if (SqlDialect.values.every(
          (d) => computed!.expression(d).trim().isEmpty,
        )) {
          failAt(
            expression,
            'COLUMN',
            'Computed SQL must be non-empty for at least one database.',
          );
        }
      default:
        failAt(expression, 'COLUMN', 'Unsupported column modifier $method.');
    }
    expression = expression.target!;
  }
  if (expression is! MethodInvocation ||
      callElement(expression)?.library?.uri.toString() !=
          schemaDeclarationUri ||
      callElement(expression) is! TopLevelFunctionElement) {
    failAt(
      expression,
      'COLUMN',
      'Use a column helper directly. Arbitrary factories and aliases are not executed.',
    );
  }
  final call = expression;
  final helper = callName(call);
  if (helper == 'identity' && modifiers.contains('identity')) {
    failAt(call, 'DUPLICATE', 'Identity is declared twice.');
  }
  final generated = helper == 'identity' || modifiers.contains('identity');
  String storage, codec;
  Object? codecIdentity;
  var codecNullable = false;
  Map<String, String>? enumLabels;
  if (helper == 'enumeration') {
    final enumType = typeSystem.promoteToNonNull(valueType);
    if (enumType is! InterfaceType || enumType.element is! EnumElement) {
      failAt(call, 'ENUM', 'Use a concrete enum type and its .values list.');
    }
    final enumeration = enumType.element as EnumElement;
    final values = resolvedElement(positionalArguments(call).single);
    if (values is! FieldElement ||
        values.name != 'values' ||
        values.enclosingElement != enumeration) {
      failAt(call, 'ENUM', 'Pass ${enumeration.name}.values to enumeration().');
    }
    enumLabels = {
      for (final f in enumeration.fields.where((f) => f.isEnumConstant))
        f.name!: f.name!,
    };
    final labels = namedArgument(call, 'labels');
    if (labels != null) {
      if (labels is! SetOrMapLiteral || !labels.isMap) {
        failAt(
          labels,
          'ENUM',
          'Use a literal map of enum constants to storage labels.',
        );
      }
      final mapped = <String, String>{};
      for (final entry in labels.elements) {
        if (entry is! MapLiteralEntry) {
          failAt(
            entry,
            'ENUM',
            'Enum labels do not support collection control flow or spreads.',
          );
        }
        final constant = resolvedElement(entry.key);
        if (constant is! FieldElement ||
            !constant.isEnumConstant ||
            constant.enclosingElement != enumeration ||
            mapped.containsKey(constant.name)) {
          failAt(entry.key, 'ENUM', 'Use each enum constant exactly once.');
        }
        mapped[constant.name!] = stringValue(entry.value);
      }
      if (mapped.length != enumLabels.length) {
        failAt(labels, 'ENUM', 'Provide a label for every enum constant.');
      }
      enumLabels = {for (final key in enumLabels.keys) key: mapped[key]!};
    }
    if (enumLabels.isEmpty ||
        enumLabels.values.toSet().length != enumLabels.length) {
      failAt(
        call,
        'ENUM',
        'Enum storage labels must be non-empty in number and distinct.',
      );
    }
    final symbol = names.type(enumType);
    codec =
        'Codecs.enumeration<$symbol>({${enumLabels.entries.map((e) => '$symbol.${e.key}: ${dartLiteral(e.value)}').join(', ')}})';
    storage = 'text';
  } else if (helper == 'custom') {
    final source = positionalArguments(call).single;
    final constant = constantValue(source);
    storage = constant?.getField('sqlType')?.toStringValue() ?? '';
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
      failAt(
        source,
        'CODEC',
        'Use a public const Codec with a supported storage type.',
      );
    }
    codec = names.codecReference(source);
    codecIdentity = constant;
    final domain = (source.staticType as InterfaceType).typeArguments.single;
    codecNullable = typeSystem.isNullable(domain);
  } else {
    final mapping = switch (helper) {
      'identity' || 'integer' => ('integer', 'integer'),
      'text' => ('text', 'text'),
      'boolean' => ('boolean', 'boolean'),
      'real' => ('real', 'real'),
      'bigInteger' => ('bigint', 'bigint'),
      'decimal' => ('decimal', 'decimal'),
      'dateTime' => ('instant', 'dateTime'),
      'date' => ('date', 'date'),
      'time' => ('time', 'time'),
      'localDateTime' => ('local_datetime', 'localDateTime'),
      'bytes' => ('blob', 'bytes'),
      'json' => ('json', 'jsonDocument'),
      _ => failAt(call, 'COLUMN', 'Unsupported column helper $helper.'),
    };
    (storage, codec) = (mapping.$1, 'Codecs.${mapping.$2}');
  }
  final comparisonCodec = codecIdentity ?? codec;
  if (nullable && !codecNullable) codec += '.nullable()';
  var defaultSql = namedString(call, 'defaultSql');
  final literalDefault = namedArgument(call, 'defaultValue');
  final factory = nullableFactory ?? namedArgument(call, 'clientDefault');
  if (nullableFactory != null && namedArgument(call, 'clientDefault') != null) {
    failAt(field, 'DEFAULT', 'Declare clientDefault only once.');
  }
  if (defaultSql != null && literalDefault != null ||
      computed != null &&
          (generated ||
              defaultSql != null ||
              literalDefault != null ||
              factory != null)) {
    failAt(
      field,
      'DEFAULT',
      'Use defaultValue or defaultSql; computed columns cannot have identity or defaults.',
    );
  }
  if (literalDefault != null) {
    if (literalDefault.staticType is DynamicType) {
      failAt(
        literalDefault,
        'DEFAULT',
        'Defaults require a statically typed value.',
      );
    }
    final value = enumLabels == null
        ? scalarValue(literalDefault)
        : enumLabels[enumName(literalDefault)];
    defaultSql = switch (value) {
      String() => "'${value.replaceAll("'", "''")}'",
      bool() => value ? 'true' : 'false',
      int() => '$value',
      double() when value.isFinite => '$value',
      _ => failAt(
        literalDefault,
        'DEFAULT',
        'Use a non-null literal/const default or an explicit SQL/client default.',
      ),
    };
  }
  String? clientDefault;
  if (factory != null) {
    final signature = factory.staticType;
    var function = resolvedElement(factory);
    if (function is VariableElement) {
      function = function.computeConstantValue()?.toFunctionValue();
    }
    if (signature is! FunctionType ||
        signature.typeParameters.isNotEmpty ||
        signature.formalParameters.any((p) => p.isRequired) ||
        function is! ExecutableElement ||
        signature.returnType is DynamicType ||
        !typeSystem.isSubtypeOf(signature.returnType, valueType)) {
      failAt(
        factory,
        'DEFAULT',
        'Use a public synchronous function or constructor tear-off returning $valueType without required arguments.',
      );
    }
    clientDefault = names.factoryReference(factory, function, signature);
  }
  final bits = namedInteger(call, 'bits');
  final precision = namedInteger(call, 'precision');
  final scale = namedInteger(call, 'scale');
  if (bits != null && (storage != 'integer' || !{16, 32, 64}.contains(bits))) {
    failAt(call, 'STORAGE', 'Integer bits must be 16, 32 or 64.');
  }
  if (storage == 'decimal') {
    if (scale != null && precision == null ||
        precision != null &&
            (precision < 1 ||
                precision > 1000 ||
                (scale ?? 0) < -1000 ||
                (scale ?? 0) > 1000)) {
      failAt(
        call,
        'STORAGE',
        'Decimal precision must be 1..1000; scale -1000..1000 requires precision.',
      );
    }
  } else if (scale != null ||
      precision != null &&
          (!{'instant', 'time', 'local_datetime'}.contains(storage) ||
              precision < 0 ||
              precision > 6)) {
    failAt(call, 'STORAGE', 'Temporal precision must be 0..6.');
  }
  names.exportType(valueType);
  final result = ModelField(
    name: name,
    column: namedString(call, 'name') ?? snakeCase(name),
    type: names.type(valueType),
    codec: codec,
    storage: storage,
    nullable: nullable,
    id: generated,
    generated: generated,
    unique: namedBoolean(call, 'unique') ?? false,
    defaultSql: defaultSql,
    clientDefault: clientDefault,
    computed: computed,
    integerBits: bits,
    decimalPrecision: storage == 'decimal' ? precision : null,
    decimalScale: scale,
    temporalPrecision: storage == 'decimal' ? null : precision,
  );
  return (result, valueType, comparisonCodec);
}
