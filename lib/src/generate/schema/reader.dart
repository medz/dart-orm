import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_system.dart';

import '../../../schema_model.dart';
import '../model.dart';
import '../source.dart';
import '../types.dart';
import 'columns.dart';
import 'syntax.dart';

/// Reads source declarations, never application objects or callback results.
final class SchemaReader(
  final CompilationUnit unit,
  final TypeSystem typeSystem,
  final DartNames names,
  final List<VariableDeclaration> declarations,
) {
  final _models = <VariableElement, ModelEntity>{};
  final _definitions = <ModelEntity, InvocationExpression>{};
  final _fieldTypes = <ModelField, DartType>{};
  final _fieldCodecs = <ModelField, Object>{};
  final _relations = <(ModelEntity, String, String, InvocationExpression)>[];

  List<ModelEntity> read() {
    final consumed = <AstNode>{};
    for (final variable in declarations) {
      final declaration = variable.parent as VariableDeclarationList;
      final element = variable.declaredFragment!.element;
      if (!isModel(element.type)) continue;
      final expression = variable.initializer;
      if (!declaration.isFinal ||
          element.isPrivate ||
          databaseMembers.contains(element.name)) {
        failAt(
          variable,
          'MODEL',
          'Use a public final variable initialized with model(...) that does not shadow a Database member.',
        );
      }
      if (expression is! InvocationExpression ||
          callName(expression) != 'model') {
        failAt(
          variable,
          'MODEL',
          'Initialize the model directly with model(...).',
        );
      }
      final record = positionalArguments(expression)[1];
      if (record is! RecordLiteral ||
          record.fields.isEmpty ||
          record.fields.any((f) => f is! RecordLiteralNamedField)) {
        failAt(
          record,
          'FIELDS',
          'Use a non-empty named Record of column declarations as the second argument.',
        );
      }
      final fields = <ModelField>[];
      for (final f in record.fields.cast<RecordLiteralNamedField>()) {
        final (field, valueType, codec) = readColumn(f, typeSystem, names);
        _fieldTypes[field] = valueType;
        _fieldCodecs[field] = codec;
        fields.add(field);
      }
      final modelName = element.name!;
      final row = modelName[0].toUpperCase() + modelName.substring(1);
      final model = ModelEntity(
        modelName,
        stringValue(positionalArguments(expression).first),
        row,
        fields,
      );
      _models[element] = model;
      _definitions[model] = expression;
      consumed.add(expression);
    }
    // A nested/list/function declaration must never disappear from the schema.
    unit.accept(
      _ModelCalls((call) {
        if (!consumed.contains(call)) {
          failAt(
            call,
            'MODEL',
            'Place each model directly in a public final top-level variable.',
          );
        }
      }),
    );
    if (_models.isEmpty) {
      failAt(unit, 'MODEL', 'No model declarations found.');
    }
    for (final entry in _definitions.entries) {
      _constraints(entry.key, entry.value);
    }
    for (final (model, name, parameter, call) in _relations) {
      if (callName(call) == 'references') {
        _reference(model, name, parameter, call);
      }
    }
    // Resolve inverses after all forward references, including other libraries.
    for (final (model, name, parameter, call) in _relations) {
      if (callName(call) == 'referencedBy') {
        _inverseReference(model, name, parameter, call);
      }
    }
    final relationOrder = {
      for (var i = 0; i < _relations.length; i++)
        (_relations[i].$1, _relations[i].$2): i,
    };
    for (final model in _models.values) {
      model.edges.sort(
        (a, b) => relationOrder[(model, a.name)]!.compareTo(
          relationOrder[(model, b.name)]!,
        ),
      );
    }
    _validate();
    // Preserve local declaration order and existing snapshots. External models
    // have no local source order; use physical identity so Dart renames cannot
    // reorder a barrel's migration snapshot.
    final external =
        _models.values
            .where((model) => _definitions[model]!.root != unit)
            .toList()
          ..sort((a, b) => a.table.compareTo(b.table));
    return [
      for (final model in _models.values)
        if (_definitions[model]!.root == unit) model,
      ...external,
    ];
  }

  void _constraints(ModelEntity model, InvocationExpression call) {
    final key = namedArgument(call, 'primaryKey');
    if (key != null) {
      if (model.primaryKey.isNotEmpty) {
        failAt(key, 'KEY', 'Primary key already declared by identity().');
      }
      final (parameter, body) = _selector(key);
      model.primaryKey = _columns(body, model, parameter);
    }
    for (final option in ['uniqueKeys', 'indexes']) {
      final expression = namedArgument(call, option);
      if (expression == null) continue;
      final (parameter, body) = _selector(expression);
      for (final item in _list(body)) {
        if (option == 'uniqueKeys') {
          model.uniqueKeys.add(_columns(item, model, parameter));
          continue;
        }
        if (item is! InvocationExpression || callName(item) != 'index') {
          failAt(item, 'CONSTRAINT', 'Use index(...) directly.');
        }
        model.indexes.add(
          ModelIndex(
            namedString(item, 'name')!,
            _columns(positionalArguments(item).first, model, parameter),
            namedBoolean(item, 'unique') ?? false,
          ),
        );
      }
    }
    final relations = namedArgument(call, 'relations');
    if (relations != null) {
      final (parameter, body) = _selector(relations);
      if (body is! RecordLiteral ||
          body.fields.any((f) => f is! RecordLiteralNamedField)) {
        failAt(body, 'RELATION', 'Return a named Record of relationships.');
      }
      for (final field in body.fields.cast<RecordLiteralNamedField>()) {
        final expression = field.fieldExpression;
        if (expression is! InvocationExpression ||
            callElement(expression) is! TopLevelFunctionElement ||
            callElement(expression)?.library?.uri.toString() !=
                schemaDeclarationUri ||
            !{'references', 'referencedBy'}.contains(callName(expression))) {
          failAt(
            field,
            'RELATION',
            'Use references(...) or referencedBy(...) directly.',
          );
        }
        _relations.add((model, field.name.lexeme, parameter, expression));
      }
    }
    final checks = namedArgument(call, 'checks');
    if (checks != null) {
      for (final item in _list(checks)) {
        if (item is! InvocationExpression || callName(item) != 'check') {
          failAt(item, 'CHECK', 'Use check(...) directly.');
        }
        final sql = stringValue(positionalArguments(item).single);
        final check = CheckSchema.forDialects(
          namedString(item, 'name'),
          sqlite: namedString(item, 'sqlite') ?? sql,
          postgres: namedString(item, 'postgres') ?? sql,
          mysql: namedString(item, 'mysql') ?? sql,
          mariadb: namedString(item, 'mariadb') ?? sql,
        );
        if (SqlDialect.values.every(
              (d) => check.expression(d).trim().isEmpty,
            ) ||
            check.name != null &&
                (check.name!.isEmpty ||
                    model.checks.any((c) => c.name == check.name))) {
          failAt(
            item,
            'CHECK',
            'Use non-empty CHECK expressions and distinct, non-empty constraint names, or omit name.',
          );
        }
        model.checks.add(check);
      }
    }
  }

  void _reference(
    ModelEntity source,
    String name,
    String parameter,
    InvocationExpression call,
  ) {
    final args = positionalArguments(call);
    final target = _target(args[1]);
    final named =
        args.first is RecordLiteral &&
        (args.first as RecordLiteral).fields.any(
          (f) => f is RecordLiteralNamedField,
        );
    var (local, remote) = named
        ? _mappedColumns(args.first, source, target, parameter)
        : (_columns(args.first, source, parameter), target.primaryKey);
    final constraint = namedBoolean(call, 'constraint') ?? true;
    if (remote.isEmpty || local.length != remote.length) {
      failAt(
        call,
        'REFERENCE',
        'Foreign key arity differs or target has no primary key. Use a named Record to map target fields explicitly.',
      );
    }
    final keys = [
      target.primaryKey,
      ...target.uniqueKeys,
      for (final index in target.indexes)
        if (index.unique) index.keys,
    ];
    if (named) {
      // Named fields describe a mapping, not tuple order. Normalize to the
      // target key, or target field order for a read-only non-unique mapping.
      final key =
          keys
              .where(
                (k) =>
                    k.length == remote.length && k.toSet().containsAll(remote),
              )
              .firstOrNull ??
          target.fields.map((f) => f.name).where(remote.contains).toList();
      local = [for (final field in key) local[remote.indexOf(field)]];
      remote = key;
    }
    if (constraint && !keys.any((key) => sameStrings(key, remote))) {
      failAt(call, 'REFERENCE', 'Target must be a primary or unique key.');
    }
    for (var i = 0; i < local.length; i++) {
      final a = source.field(local[i]), b = target.field(remote[i]);
      final at = typeSystem.promoteToNonNull(_fieldTypes[a]!);
      final bt = typeSystem.promoteToNonNull(_fieldTypes[b]!);
      if (a.storage != b.storage ||
          !typeSystem.isSubtypeOf(at, bt) ||
          !typeSystem.isSubtypeOf(bt, at) ||
          _fieldCodecs[a] != _fieldCodecs[b]) {
        failAt(
          call,
          'REFERENCE',
          'Reference ${a.name} -> ${b.name} requires matching value types and codecs.',
        );
      }
    }
    final action = enumName(namedArgument(call, 'onDelete')) ?? 'restrict';
    final sqlAction = switch (action) {
      'restrict' => 'RESTRICT',
      'cascade' => 'CASCADE',
      'setNull' => 'SET NULL',
      'setDefault' => 'SET DEFAULT',
      'noAction' => 'NO ACTION',
      _ => failAt(call, 'REFERENCE', 'Unsupported deletion action.'),
    };
    if (constraint &&
        action == 'setNull' &&
        local.any((key) => !source.field(key).nullable)) {
      failAt(call, 'REFERENCE', 'SET NULL requires nullable source columns.');
    }
    _edge(
      source,
      ModelRelation(name, target, local, remote, constraint ? sqlAction : null),
      call,
    );
  }

  ModelEntity _target(Expression targetExpression) {
    if (targetExpression is! FunctionExpression ||
        targetExpression.parameters!.parameters.isNotEmpty ||
        targetExpression.body is! ExpressionFunctionBody) {
      failAt(
        targetExpression,
        'REFERENCE',
        'Reference the target with () => model.',
      );
    }
    final targetNode =
        (targetExpression.body as ExpressionFunctionBody).expression;
    final target = _models[resolvedElement(targetNode)];
    if (target == null) {
      failAt(
        targetNode,
        'REFERENCE',
        'Target must reference a reachable Model declaration.',
      );
    }
    return target;
  }

  void _inverseReference(
    ModelEntity source,
    String name,
    String parameter,
    InvocationExpression call,
  ) {
    final target = _target(positionalArguments(call).single);
    final on = namedArgument(call, 'on');
    final mapping = on == null
        ? null
        : _mappedColumns(on, source, target, parameter);
    final matches = target.edges.where((edge) {
      if (edge.inverse || edge.target != source) return false;
      if (mapping == null) return true;
      final (local, remote) = mapping;
      if (remote.length != edge.parentKeys.length) return false;
      for (var i = 0; i < remote.length; i++) {
        final at = edge.parentKeys.indexOf(remote[i]);
        if (at < 0 || edge.childKeys[at] != local[i]) return false;
      }
      return true;
    }).toList();
    if (matches.length != 1) {
      final choices = [
        for (final edge in matches)
          '${target.name}.${edge.name}: on: (${[for (var i = 0; i < edge.parentKeys.length; i++) '${edge.parentKeys[i]}: $parameter.${edge.childKeys[i]}'].join(', ')})',
      ];
      failAt(
        call,
        'REFERENCE',
        matches.isEmpty
            ? 'No matching forward references declaration from ${target.name} to ${source.name}.'
            : 'Multiple references from ${target.name} to ${source.name}. Select a mapping: ${choices.join('; ')}.',
      );
    }
    final forward = matches.single;
    _edge(
      source,
      ModelRelation(
        name,
        target,
        forward.childKeys,
        forward.parentKeys,
        forward.onDelete,
        inverse: true,
      ),
      call,
    );
  }

  void _edge(ModelEntity model, ModelRelation edge, AstNode node) {
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(edge.name) ||
        {
          'table',
          'column',
          'readColumn',
          'hashCode',
          'runtimeType',
          'toString',
          'noSuchMethod',
        }.contains(edge.name) ||
        model.fields.any((f) => f.name == edge.name) ||
        model.edges.any((e) => e.name == edge.name)) {
      failAt(
        node,
        'NAME',
        'Invalid or duplicate relation name ${edge.name} on ${model.name}.',
      );
    }
    model.edges.add(edge);
  }

  void _validate() {
    final tables = <String>{}, indexes = <String>{};
    final symbols = <String>{'appSchema', 'AppTables', ...generatedTypeNames};
    for (final model in _models.values) {
      final node = _definitions[model]!;
      if (!tables.add(model.table)) {
        failAt(node, 'DUPLICATE', 'Duplicate physical table ${model.table}.');
      }
      if (model.fields.map((f) => f.column).toSet().length !=
          model.fields.length) {
        failAt(
          node,
          'DUPLICATE',
          'Duplicate physical column on ${model.name}.',
        );
      }
      for (final symbol in [
        model.row,
        model.fieldsType,
        model.setType,
        '${model.symbol}Updates',
        '${model.name}Schema',
        '${model.name}Table',
        for (final field in model.fields) columnSymbol(model, field),
      ]) {
        if (!symbols.add(symbol)) {
          failAt(
            node,
            'NAME',
            'Generated symbol $symbol is ambiguous. Rename the Dart model or field and keep its physical name.',
          );
        }
      }
      if (model.fields.every((field) => field.computed != null)) {
        failAt(node, 'COLUMN', 'A model needs at least one ordinary column.');
      }
      for (final key in model.primaryKey) {
        if (model.field(key).nullable) {
          failAt(node, 'KEY', 'Primary keys cannot be nullable.');
        }
      }
      if (model.uniqueKeys.map((key) => key.join('\u0000')).toSet().length !=
          model.uniqueKeys.length) {
        failAt(node, 'DUPLICATE', 'Duplicate unique key on ${model.name}.');
      }
      for (final field in model.fields.where((f) => f.generated)) {
        if (field.storage != 'integer' ||
            !sameStrings(model.primaryKey, [field.name])) {
          failAt(
            node,
            'KEY',
            'identity() requires a single integer-storage primary key.',
          );
        }
      }
      for (final index in model.indexes) {
        if (!indexes.add(index.name)) {
          failAt(node, 'DUPLICATE', 'Duplicate index name ${index.name}.');
        }
      }
    }
  }

  (String, Expression) _selector(Expression expression) {
    if (expression is! FunctionExpression ||
        expression.parameters?.parameters.length != 1 ||
        expression.body is! ExpressionFunctionBody) {
      failAt(
        expression,
        'SELECTOR',
        'Use a one-argument arrow selector. Arbitrary callback execution is not supported.',
      );
    }
    return (
      expression.parameters!.parameters.single.name!.lexeme,
      (expression.body as ExpressionFunctionBody).expression,
    );
  }

  List<String> _columns(
    Expression expression,
    ModelEntity model,
    String parameter,
  ) {
    final columns = <String>[];
    for (final part in _parts(expression)) {
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
        _ => failAt(
          part,
          'SELECTOR',
          'Select direct fields of $parameter, or an ordered positional Record of them.',
        ),
      };
      if (!model.fields.any((f) => f.name == name)) {
        failAt(part, 'SELECTOR', 'Unknown column $name.');
      }
      if (columns.contains(name)) {
        failAt(part, 'KEY', 'A key cannot repeat $name.');
      }
      columns.add(name);
    }
    return columns;
  }

  (List<String>, List<String>) _mappedColumns(
    Expression expression,
    ModelEntity source,
    ModelEntity target,
    String parameter,
  ) {
    if (expression is! RecordLiteral ||
        expression.fields.isEmpty ||
        expression.fields.any((f) => f is! RecordLiteralNamedField)) {
      failAt(
        expression,
        'REFERENCE',
        'Use a non-empty named Record mapping target fields to local columns.',
      );
    }
    final local = <String>[], remote = <String>[];
    for (final field in expression.fields.cast<RecordLiteralNamedField>()) {
      final name = field.name.lexeme;
      if (!target.fields.any((f) => f.name == name) || remote.contains(name)) {
        failAt(
          field,
          'REFERENCE',
          'Unknown or repeated target field ${target.name}.$name.',
        );
      }
      final columns = _columns(field.fieldExpression, source, parameter);
      if (columns.length != 1 || local.contains(columns.single)) {
        failAt(
          field,
          'REFERENCE',
          'Map each target field to one distinct local column.',
        );
      }
      local.add(columns.single);
      remote.add(name);
    }
    return (local, remote);
  }

  List<Expression> _parts(Expression expression) {
    if (expression is! RecordLiteral) return [expression];
    if (expression.fields.isEmpty ||
        expression.fields.any((f) => f is RecordLiteralNamedField)) {
      failAt(
        expression,
        'KEY',
        'Use a direct column or non-empty positional Record to preserve key order.',
      );
    }
    return [for (final f in expression.fields) f.fieldExpression];
  }

  List<Expression> _list(Expression expression) {
    if (expression is! ListLiteral) {
      failAt(expression, 'LIST', 'Use a literal list of declarations.');
    }
    return [
      for (final item in expression.elements)
        if (item is Expression)
          item
        else
          failAt(
            item,
            'LIST',
            'Collection control flow and spreads are not supported in schema declarations.',
          ),
    ];
  }
}

final class _ModelCalls(final void Function(InvocationExpression) found)
    extends RecursiveAstVisitor<void> {
  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'model' &&
        node.methodName.element?.library?.uri.toString() ==
            schemaDeclarationUri) {
      found(node);
    }
    super.visitMethodInvocation(node);
  }
}
