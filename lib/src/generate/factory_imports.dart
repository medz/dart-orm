import 'dart:convert';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

import 'schema/diagnostics.dart';
import 'source.dart';

Expression unwrapFactory(Expression value) {
  while (value is ParenthesizedExpression) {
    value = value.expression;
  }
  return value;
}

/// A factory type occurrence retained until public routes have been resolved.
final class FactoryTypeUse {
  final DartType type;
  final TypeAnnotation? spelling;
  final Map<TypeParameterElement, FactoryTypeUse> environment;
  final bool omitted;
  FactoryTypeUse(
    this.type, {
    this.spelling,
    Map<TypeParameterElement, FactoryTypeUse> environment = const {},
    this.omitted = false,
  }) : environment = Map.unmodifiable(environment);
}

/// A factory-only public qualifier, with constructor arguments in that scope.
final class FactoryTarget {
  final Element symbol;
  final AstNode spelling;
  final List<FactoryTypeUse>? arguments;
  final bool expanded;
  final List<GenericTypeAlias> aliases;
  final String? reference;
  const FactoryTarget(
    this.symbol,
    this.spelling,
    this.arguments, {
    this.expanded = false,
    this.aliases = const [],
    this.reference,
  });
}

/// Imports used only for client-default references whose public entrypoint must
/// survive generation. Ordinary type and codec references retain their identity.
final class FactoryImports(
  final String Function(Uri) importUri,
  final String Function(String) allocatePrefix,
) {
  final Map<(String, String), String> _prefixes = {};

  Iterable<String> get directives => _prefixes.entries.map(
    (entry) => 'import ${entry.key.$1} as ${entry.value} show ${entry.key.$2};',
  );

  FactoryTarget resolve(
    Element symbol,
    Expression expression,
    AstNode context, {
    FunctionType? constructor,
    NamedType? typeSpelling,
    DartType? instantiatedType,
    String? fieldName,
    Map<TypeParameterElement, FactoryTypeUse> environment = const {},
  }) {
    final owner = expression.root as CompilationUnit;
    var alias = typeSpelling == null
        ? _sourceAlias(expression)
        : (typeSpelling.element is TypeAliasElement
              ? typeSpelling.element as TypeAliasElement
              : null);
    AstNode spelling = typeSpelling ?? expression;
    List<FactoryTypeUse>? arguments;
    var expanded = false;
    if (constructor != null || typeSpelling != null) {
      final value = unwrapFactory(
        expression is FunctionReference ? expression.function : expression,
      );
      final named =
          typeSpelling ??
          (value is ConstructorReference ? value.constructorName.type : null);
      if (named == null) {
        failAt(
          expression,
          'DEFAULT',
          'Cannot resolve the constructor alias qualifier.',
        );
      }
      arguments = _arguments(
        named,
        environment,
        expression,
        inferredArguments: constructor?.returnType.alias?.typeArguments,
        instantiatedType: instantiatedType ?? constructor?.returnType,
      );
      if (alias != null &&
          alias.isPrivate &&
          arguments.length != alias.typeParameters.length) {
        final inferred = constructor?.returnType.alias;
        if (inferred?.element == alias) {
          arguments = inferred!.typeArguments
              .map((type) => FactoryTypeUse(type, omitted: true))
              .toList();
        } else {
          failAt(
            expression,
            'DEFAULT',
            'Cannot determine constructor alias type arguments. Instantiate the factory explicitly.',
          );
        }
      }
    }
    final visited = <TypeAliasElement>{};
    final expandedAliases = <GenericTypeAlias>[];
    while (alias != null && alias.isPrivate) {
      if (!visited.add(alias) ||
          alias.library != owner.declaredFragment!.element) {
        failAt(
          expression,
          'DEFAULT',
          'Cannot resolve this local factory alias to a unique public entrypoint.',
        );
      }
      final declaration = owner.declarations
          .whereType<GenericTypeAlias>()
          .where((node) => node.declaredFragment!.element == alias)
          .firstOrNull;
      final body = declaration?.type;
      if (body is! NamedType ||
          body.element == null ||
          body.element is TypeParameterElement) {
        failAt(
          expression,
          'DEFAULT',
          'A factory qualifier alias must resolve to a named public type.',
        );
      }
      expandedAliases.add(declaration!);
      final environment = <TypeParameterElement, FactoryTypeUse>{};
      if (arguments != null) {
        if (arguments.length != alias.typeParameters.length) {
          failAt(
            expression,
            'DEFAULT',
            'Cannot determine this factory alias constructor type arguments.',
          );
        }
        for (var index = 0; index < arguments.length; index++) {
          environment[alias.typeParameters[index]] = arguments[index];
        }
        arguments = _arguments(body, environment, expression);
      }
      symbol = body.element!;
      spelling = body;
      expanded = true;
      alias = symbol is TypeAliasElement ? symbol : null;
    }
    symbol = alias ?? symbol;
    final target = FactoryTarget(
      symbol,
      spelling,
      arguments,
      expanded: expanded,
      aliases: expandedAliases,
    );
    return FactoryTarget(
      symbol,
      spelling,
      arguments,
      expanded: expanded,
      aliases: expandedAliases,
      reference: _reference(target, expression, context, fieldName: fieldName),
    );
  }

  List<FactoryTypeUse> _arguments(
    NamedType type,
    Map<TypeParameterElement, FactoryTypeUse> environment,
    Expression expression, {
    List<DartType>? inferredArguments,
    DartType? instantiatedType,
  }) {
    final explicit = type.typeArguments?.arguments;
    if (explicit != null) {
      final materialized = instantiatedType?.alias?.element == type.element
          ? instantiatedType!.alias!.typeArguments
          : instantiatedType is InterfaceType &&
                instantiatedType.element == type.element
          ? instantiatedType.typeArguments
          : null;
      return [
        for (var index = 0; index < explicit.length; index++)
          if ((materialized != null && index < materialized.length
                  ? materialized[index]
                  : explicit[index].type)
              case final resolved?)
            FactoryTypeUse(
              resolved,
              spelling: explicit[index],
              environment: environment,
            )
          else
            failAt(
              expression,
              'DEFAULT',
              'Cannot resolve a constructor alias type argument.',
            ),
      ];
    }
    // Omitted arguments on public types must remain omitted: the target
    // compiler instantiates bounds through that same public entrypoint. Only a
    // private alias needs a concrete environment before its body can expand.
    if (type.element case TypeAliasElement(isPrivate: true)) {
      // Resolve private bounds below, retaining their original type syntax.
    } else {
      return [];
    }
    final resolved = type.type;
    var inferred =
        resolved?.alias?.typeArguments ??
        inferredArguments ??
        (resolved is InterfaceType
            ? resolved.typeArguments
            : const <DartType>[]);
    final unit = type.root as CompilationUnit;
    final declaration = unit.declarations
        .whereType<GenericTypeAlias>()
        .where((node) => node.declaredFragment!.element == type.element)
        .firstOrNull;
    final parameters = declaration?.typeParameters?.typeParameters;
    // An omitted constructor tear-off can retain a generic signature instead of
    // an instantiated alias. Its local declaration still supplies the bounds.
    if (resolved == null && inferred.isEmpty && declaration != null) {
      inferred = [
        for (final parameter in parameters ?? <TypeParameter>[])
          parameter.bound?.type ??
              unit.declaredFragment!.element.typeProvider.dynamicType,
      ];
    }
    final uses = <FactoryTypeUse>[];
    final inferredEnvironment = Map<TypeParameterElement, FactoryTypeUse>.of(
      environment,
    );
    for (var index = 0; index < inferred.length; index++) {
      final parameter = parameters == null || index >= parameters.length
          ? null
          : parameters[index];
      final bound = parameter?.bound;
      final spelling =
          bound?.type != null &&
              _matchesBound(
                bound!.type!,
                inferred[index],
                inferredEnvironment,
                expression,
              )
          ? bound
          : null;
      final use = FactoryTypeUse(
        // Analyzer's instantiated alias types erase nullable dependent bounds.
        // Retain the proven source bound and substitute its parameters at render.
        spelling?.type ?? inferred[index],
        spelling: spelling,
        environment: inferredEnvironment,
        omitted: true,
      );
      uses.add(use);
      if (parameter?.declaredFragment?.element case final element?) {
        inferredEnvironment[element] = use;
      }
    }
    return uses;
  }

  // Compare the analyzer's inferred argument against the bound after earlier
  // parameter substitutions. Keep the bound AST and environment for rendering;
  // public-route validation still occurs for every resulting type occurrence.
  bool _matchesBound(
    DartType template,
    DartType actual,
    Map<TypeParameterElement, FactoryTypeUse> environment,
    Expression expression, {
    Set<TypeParameterElement> visiting = const {},
  }) {
    if (template is TypeParameterType) {
      final use = environment[template.element];
      if (use == null || visiting.contains(template.element)) return false;
      var source = use.type;
      if (template.nullabilitySuffix == NullabilitySuffix.question) {
        final types = (expression.root as CompilationUnit)
            .declaredFragment!
            .element
            .typeSystem;
        source = types.promoteToNonNull(source);
        actual = types.promoteToNonNull(actual);
      }
      return _matchesBound(
        source,
        actual,
        use.environment,
        expression,
        visiting: {...visiting, template.element},
      );
    }
    if (template == actual) return true;
    if (template.nullabilitySuffix != actual.nullabilitySuffix) return false;
    bool matches(DartType left, DartType right) =>
        _matchesBound(left, right, environment, expression, visiting: visiting);
    if (template is InterfaceType && actual is InterfaceType) {
      return template.element == actual.element &&
          template.typeArguments.length == actual.typeArguments.length &&
          [
            for (var index = 0; index < template.typeArguments.length; index++)
              matches(
                template.typeArguments[index],
                actual.typeArguments[index],
              ),
          ].every((value) => value);
    }
    if (template is RecordType && actual is RecordType) {
      return template.positionalFields.length ==
              actual.positionalFields.length &&
          template.namedFields.length == actual.namedFields.length &&
          [
            for (
              var index = 0;
              index < template.positionalFields.length;
              index++
            )
              matches(
                template.positionalFields[index].type,
                actual.positionalFields[index].type,
              ),
            for (var index = 0; index < template.namedFields.length; index++)
              template.namedFields[index].name ==
                      actual.namedFields[index].name &&
                  matches(
                    template.namedFields[index].type,
                    actual.namedFields[index].type,
                  ),
          ].every((value) => value);
    }
    return false;
  }

  bool _conditionalOwner(
    CompilationUnit owner,
    AstNode context,
    Expression expression,
  ) {
    final model = context.root as CompilationUnit;
    final mixin = expression
        .thisOrAncestorOfType<MixinDeclaration>()
        ?.declaredFragment
        ?.element;
    final applied = context
        .thisOrAncestorOfType<ClassDeclaration>()
        ?.withClause
        ?.mixinTypes
        .where((type) => type.element == mixin)
        .firstOrNull;
    for (final directive in model.directives.whereType<ImportDirective>()) {
      if (directive.prefix?.name != applied?.importPrefix?.name.lexeme) {
        continue;
      }
      final imported = directive.libraryImport?.importedLibrary;
      if (imported != null &&
          _reaches(imported, owner.declaredFragment!.element, {}) &&
          (directive.configurations.isNotEmpty ||
              _conditionalExport(
                imported,
                owner.declaredFragment!.element,
                {},
              ))) {
        return true;
      }
    }
    return false;
  }

  String? _reference(
    FactoryTarget target,
    Expression expression,
    AstNode context, {
    String? fieldName,
  }) {
    final symbol = target.symbol;
    if (symbol.isPrivate) {
      failAt(
        expression,
        'DEFAULT',
        'Cannot expose private factory symbol ${symbol.name}. Use a public entrypoint.',
      );
    }
    final owner = expression.root as CompilationUnit;
    final model = context.root as CompilationUnit;
    final library = symbol.library!;
    final local = library == owner.declaredFragment!.element;
    var unit = local ? model : owner;
    final mixin = expression
        .thisOrAncestorOfType<MixinDeclaration>()
        ?.declaredFragment
        ?.element;
    final applied = context
        .thisOrAncestorOfType<ClassDeclaration>()
        ?.withClause
        ?.mixinTypes
        .where((type) => type.element == mixin)
        .firstOrNull;
    var prefix = local
        ? applied?.importPrefix?.name.lexeme
        : target.spelling is NamedType
        ? (target.spelling as NamedType).importPrefix?.name.lexeme
        : _sourcePrefix(expression);
    final conditionalMixin =
        context.root != owner && _conditionalOwner(owner, context, expression);
    if (conditionalMixin) {
      final modelPrefix = applied?.importPrefix?.name.lexeme;
      final exposed = model.directives.whereType<ImportDirective>().any((
        directive,
      ) {
        final namespace = directive.libraryImport?.namespace.definedNames2;
        final visible = namespace?[symbol.name];
        return directive.prefix?.name == modelPrefix &&
            namespace?[mixin?.name] == mixin &&
            (visible is PropertyAccessorElement ? visible.variable : visible) ==
                symbol;
      });
      if (exposed) {
        if (!_sharedExternalRoute(
          owner,
          context,
          expression,
          symbol,
          publicEntrypoint: true,
          aliases: target.aliases,
          fieldName: fieldName,
          referenceSpelling: target.spelling is NamedType
              ? target.spelling as NamedType
              : null,
        )) {
          failAt(
            expression,
            'DEFAULT',
            'Cannot preserve the conditional factory expression or local alias type arguments through this public entrypoint. Keep the factory name and alias mapping consistent across branches.',
          );
        }
        unit = model;
        prefix = modelPrefix;
      } else if (!local &&
          !_sharedExternalRoute(
            owner,
            context,
            expression,
            symbol,
            fieldName: fieldName,
            referencePrefix: prefix,
            aliases: target.aliases,
            referenceSpelling: target.spelling is NamedType
                ? target.spelling as NamedType
                : null,
          )) {
        failAt(
          expression,
          'DEFAULT',
          'The conditional mixin uses different or unresolved external factory routes. '
              'Expose the factory through the mixin entrypoint, or use the same public '
              'fixed-library wrapper in every branch.',
        );
      }
    }
    final candidates = <ImportDirective>[];
    var conditionalOwner = false;
    for (final directive in unit.directives.whereType<ImportDirective>()) {
      final imported = directive.libraryImport?.importedLibrary;
      if (imported == null) {
        continue;
      }
      if (directive.prefix?.name != prefix) {
        continue;
      }
      if ((local || unit == model) &&
          mixin != null &&
          directive.libraryImport!.namespace.definedNames2[mixin.name] !=
              mixin) {
        continue;
      }
      if (_reaches(imported, library, {})) {
        conditionalOwner |=
            directive.configurations.isNotEmpty ||
            _conditionalExport(imported, library, {});
      }
      final visible =
          directive.libraryImport!.namespace.definedNames2[symbol.name];
      if ((visible is PropertyAccessorElement ? visible.variable : visible) ==
          symbol) {
        candidates.add(directive);
      }
    }
    if (candidates.isEmpty) {
      if (library.uri.toString() == 'dart:core' &&
          target.spelling is NamedType &&
          (target.spelling as NamedType).importPrefix == null) {
        return null;
      }
      if (conditionalOwner || (!local && target.expanded)) {
        failAt(
          expression,
          'DEFAULT',
          'The conditional annotation entrypoint does not expose the public '
              'client-default symbol ${symbol.name}. Export it through that '
              'entrypoint so generated clients preserve platform selection.',
        );
      }
      return null;
    }
    final entries = <String>{};
    String? directEntry;
    var conditionalEntries = false;
    var needsEntrypoint = symbol is TypeAliasElement || target.expanded;
    for (final directive in candidates) {
      final base = unit.declaredFragment!.element.uri;
      final uri = base.resolve(directive.uri.stringValue!);
      conditionalEntries |=
          directive.configurations.isNotEmpty ||
          _conditionalExport(
            directive.libraryImport!.importedLibrary!,
            library,
            {},
          );
      needsEntrypoint |=
          uri != library.uri || directive.configurations.isNotEmpty;
      if (directive.deferredKeyword != null && needsEntrypoint) {
        failAt(
          expression,
          'DEFAULT',
          'Client defaults require a synchronous, nondeferred public '
              'entrypoint. The generator cannot bypass a deferred import.',
        );
      }
      String literal(StringLiteral value) =>
          dartLiteral(importUri(base.resolve(value.stringValue!)));
      final entry = [
        literal(directive.uri),
        for (final configuration in directive.configurations)
          'if (${configuration.name.toSource()}${configuration.value == null ? '' : ' == ${configuration.value!.toSource()}'}) '
              '${literal(configuration.uri)}',
        // Only this public symbol is needed. Visibility was checked against the
        // original namespace above, including all show/hide combinators.
      ].join(' ');
      entries.add(entry);
      if (uri == library.uri && directive.configurations.isEmpty) {
        directEntry = entry;
      }
    }
    if (!needsEntrypoint) return null;
    if (entries.length != 1 && conditionalEntries) {
      failAt(
        expression,
        'DEFAULT',
        'The client-default symbol ${symbol.name} has multiple public '
            'import routes with different platform selection. Use an '
            'unambiguous import for the model or annotation.',
      );
    }
    // Plain imports/reexports of the same declaration have no platform choice.
    // Prefer the original direct import when available; every remaining plain
    // route was checked against the same visible public symbol above.
    final entry = (directEntry ?? entries.first, symbol.name!);
    final generated = _prefixes.putIfAbsent(
      entry,
      () => allocatePrefix('factories${_prefixes.length}'),
    );
    return '$generated.${symbol.name}';
  }

  // Prove an external callback route is shared by every mixin branch before
  // retaining a fixed wrapper/import. Reading inactive syntax here is confined
  // to factory references; it does not resolve field types or codecs.
  bool _sharedExternalRoute(
    CompilationUnit owner,
    AstNode context,
    Expression expression,
    Element factorySymbol, {
    bool publicEntrypoint = false,
    List<GenericTypeAlias> aliases = const [],
    String? fieldName,
    String? referencePrefix,
    NamedType? referenceSpelling,
  }) {
    final symbol = factorySymbol.name!;
    final implicitCore = factorySymbol.library!.uri.toString() == 'dart:core';
    final model = context.root as CompilationUnit;
    final mixin = expression.thisOrAncestorOfType<MixinDeclaration>();
    final field = expression.thisOrAncestorOfType<FieldDeclaration>();
    if (mixin == null || field == null) return false;
    final applied = context
        .thisOrAncestorOfType<ClassDeclaration>()
        ?.withClause
        ?.mixinTypes
        .where((type) => type.element == mixin.declaredFragment!.element)
        .firstOrNull;
    final session = owner.declaredFragment!.element.session;
    String? path(String base, String value) =>
        session.uriConverter.uriToPath(Uri.file(base).resolve(value));

    String route(ImportDirective directive, Uri base) => [
      base.resolve(directive.uri.stringValue!).toString(),
      for (final config in directive.configurations)
        '${config.name.toSource()}=${config.value?.toSource()}:${base.resolve(config.uri.stringValue!)}',
    ].join('|');
    bool visible(NodeList<Combinator> combinators, String name) =>
        combinators.every(
          (combinator) => switch (combinator) {
            ShowCombinator() => combinator.shownNames.any(
              (node) => node.name == name,
            ),
            HideCombinator() => !combinator.hiddenNames.any(
              (node) => node.name == name,
            ),
          },
        );

    bool declares(CompilationUnit unit, String name) => unit.declarations.any(
      (node) => switch (node) {
        FunctionDeclaration() => node.name.lexeme == name,
        ClassDeclaration() => node.namePart.typeName.lexeme == name,
        MixinDeclaration() => node.name.lexeme == name,
        EnumDeclaration() => node.namePart.typeName.lexeme == name,
        ExtensionDeclaration() => node.name?.lexeme == name,
        ExtensionTypeDeclaration() => node.namePart.typeName.lexeme == name,
        GenericTypeAlias() => node.name.lexeme == name,
        TopLevelVariableDeclaration() => node.variables.variables.any(
          (variable) => variable.name.lexeme == name,
        ),
        _ => false,
      },
    );

    // Inactive branches have syntax, but no resolved namespace. Follow public
    // exports to declaration identities while retaining conditional choices.
    // Prefix-normalized tokens and identical names alone do not prove identity.
    // Each environment variable has one value. Retain both a selected value
    // and earlier exclusions, so nested comparisons cannot select two values
    // of the same variable at once.
    var activeConditions = <String, (String?, Set<String>)>{};
    String conditionKey(Map<String, (String?, Set<String>)> conditions) {
      final keys = conditions.keys.toList()..sort();
      return jsonEncode([
        for (final key in keys)
          [key, conditions[key]!.$1, conditions[key]!.$2.toList()..sort()],
      ]);
    }

    Iterable<(StringLiteral, Map<String, (String?, Set<String>)>)> branches(
      StringLiteral uri,
      NodeList<Configuration> configurations,
      Map<String, (String?, Set<String>)> inherited,
    ) sync* {
      final remaining = Map<String, (String?, Set<String>)>.of(inherited);
      for (final config in configurations) {
        final key = config.name.toSource();
        final value = config.value?.stringValue ?? 'true';
        final (selected, excluded) = remaining[key] ?? (null, <String>{});
        if ((selected == null || selected == value) &&
            !excluded.contains(value)) {
          yield (config.uri, {...remaining, key: (value, excluded)});
        }
        if (selected == value) return;
        remaining[key] = (selected, {...excluded, value});
      }
      yield (uri, remaining);
    }

    late String? Function(String, String, Set<(String, String)>) origin;
    String? exportedOrigin(
      String file,
      StringLiteral uri,
      NodeList<Configuration> configurations,
      String name,
      Set<(String, String)> visiting,
    ) {
      String? resolve(
        StringLiteral literal,
        Map<String, (String?, Set<String>)> conditions,
      ) {
        final value = literal.stringValue!;
        if (Uri.parse(value).isScheme('dart')) {
          return factorySymbol.library!.uri.toString() == value
              ? '$value#$name'
              : null;
        }
        final next = path(file, value);
        if (next == null) return null;
        final previous = activeConditions;
        activeConditions = conditions;
        try {
          return origin(next, name, visiting);
        } finally {
          activeConditions = previous;
        }
      }

      final choices = branches(uri, configurations, activeConditions).toList();
      final identities = <(String, String)>[];
      for (final choice in choices) {
        final selected = resolve(choice.$1, choice.$2);
        if (selected == null) return null;
        identities.add((conditionKey(choice.$2), selected));
      }
      if (identities.every((branch) => branch.$2 == identities.first.$2)) {
        return identities.first.$2;
      }
      return jsonEncode([
        for (final (conditions, identity) in identities) [conditions, identity],
      ]);
    }

    origin = (file, name, visiting) {
      if (!visiting.add((file, name))) return null;
      try {
        final result = session.getParsedUnit(file);
        if (result is! ParsedUnitResult) return null;
        if (declares(result.unit, name)) return '$file#$name';
        final origins = <String>{};
        for (final directive
            in result.unit.directives.whereType<ExportDirective>()) {
          if (!visible(directive.combinators, name)) continue;
          final selected = exportedOrigin(
            file,
            directive.uri,
            directive.configurations,
            name,
            visiting,
          );
          if (selected != null) origins.add(selected);
        }
        return origins.length == 1 ? origins.single : null;
      } finally {
        visiting.remove((file, name));
      }
    };

    String? occurrenceOrigin(
      String file,
      CompilationUnit unit,
      String? prefix,
    ) {
      if (prefix == null && declares(unit, symbol)) return '$file#$symbol';
      final origins = <String>{};
      for (final directive in unit.directives.whereType<ImportDirective>()) {
        if (directive.prefix?.name != prefix ||
            directive.deferredKeyword != null ||
            !visible(directive.combinators, symbol)) {
          continue;
        }
        final selected = exportedOrigin(
          file,
          directive.uri,
          directive.configurations,
          symbol,
          {},
        );
        if (selected != null) origins.add(selected);
      }
      return origins.length == 1 ? origins.single : null;
    }

    bool exposes(ImportDirective directive) => directive.combinators.every(
      (combinator) => switch (combinator) {
        ShowCombinator() => combinator.shownNames.any(
          (name) => name.name == symbol,
        ),
        HideCombinator() => !combinator.hiddenNames.any(
          (name) => name.name == symbol,
        ),
      },
    );
    final prefix = referenceSpelling != null
        ? referencePrefix
        : _sourcePrefix(expression);
    final expected = <String>{
      for (final directive in owner.directives.whereType<ImportDirective>())
        if (directive.prefix?.name == prefix &&
            exposes(directive) &&
            directive.libraryImport?.namespace.definedNames2.containsKey(
                  symbol,
                ) ==
                true)
          route(directive, owner.declaredFragment!.element.uri),
    };
    final harmlessImports = <String>{
      for (final directive in owner.directives.whereType<ImportDirective>())
        if (directive.prefix?.name == prefix &&
            directive.libraryImport?.namespace.definedNames2.containsKey(
                  symbol,
                ) ==
                false)
          route(directive, owner.declaredFragment!.element.uri),
    };
    String shape(AstNode node, CompilationUnit unit) {
      final prefixes = unit.directives
          .whereType<ImportDirective>()
          .map((directive) => directive.prefix?.name)
          .whereType<String>()
          .toSet();
      final pieces = <String>[];
      var token = node.beginToken;
      String? previous;
      while (true) {
        final next = token.next;
        if (prefixes.contains(token.lexeme) &&
            next?.lexeme == '.' &&
            previous != '.') {
          if (next == node.endToken) break;
          previous = next!.lexeme;
          token = next.next!;
          continue;
        }
        pieces.add(token.lexeme);
        if (token == node.endToken) break;
        previous = token.lexeme;
        token = token.next!;
      }
      return pieces.join(' ');
    }

    List<NamedType> typeOccurrences(AstNode node) {
      final result = <NamedType>[];
      void collect(TypeAnnotation type) {
        switch (type) {
          case NamedType():
            result.add(type);
            for (final argument
                in type.typeArguments?.arguments ?? <TypeAnnotation>[]) {
              collect(argument);
            }
          case GenericFunctionType():
            break;
          case RecordTypeAnnotation():
            for (final field in type.positionalFields) {
              collect(field.type);
            }
            for (final field
                in type.namedFields?.fields ??
                    <RecordTypeAnnotationNamedField>[]) {
              collect(field.type);
            }
        }
      }

      switch (node) {
        case GenericTypeAlias():
          collect(node.type);
          for (final parameter
              in node.typeParameters?.typeParameters ?? <TypeParameter>[]) {
            if (parameter.bound case final bound?) {
              collect(bound);
            }
          }
        case FunctionReference():
          for (final argument
              in node.typeArguments?.arguments ?? <TypeAnnotation>[]) {
            collect(argument);
          }
        case TypeLiteral():
          // Before resolution a generic tear-off parses as a type literal.
          if (node.type case NamedType(:final typeArguments?)) {
            for (final argument in typeArguments.arguments) {
              collect(argument);
            }
          }
        case ConstructorReference():
          collect(node.constructorName.type);
      }
      return result;
    }

    final selectedField =
        fieldName ??
        (field.fields.variables.length == 1
            ? field.fields.variables.single.name.lexeme
            : null);
    if (selectedField == null) return false;
    var valid = true;
    final visited = <(String, String)>{};
    var found = 0;
    String? publicEntrypointFile;
    void visit(String file, Map<String, (String?, Set<String>)> conditions) {
      if (!visited.add((file, conditionKey(conditions)))) {
        return;
      }
      activeConditions = conditions;
      final result = session.getParsedUnit(file);
      if (result is! ParsedUnitResult) {
        valid = false;
        return;
      }
      final selected = result.unit.declarations
          .whereType<MixinDeclaration>()
          .where((node) => node.name.lexeme == mixin.name.lexeme)
          .firstOrNull;
      if (selected != null) {
        found++;
        if (!publicEntrypoint &&
            prefix == null &&
            declares(result.unit, symbol)) {
          valid = false;
          return;
        }
        for (final alias in aliases) {
          final counterpart = result.unit.declarations
              .whereType<GenericTypeAlias>()
              .where((node) => node.name.lexeme == alias.name.lexeme)
              .firstOrNull;
          if (counterpart == null ||
              shape(counterpart.type, result.unit) !=
                  shape(alias.type, owner) ||
              (counterpart.typeParameters == null
                      ? null
                      : shape(counterpart.typeParameters!, result.unit)) !=
                  (alias.typeParameters == null
                      ? null
                      : shape(alias.typeParameters!, owner))) {
            valid = false;
            return;
          }
        }
        final corresponding = selected.body.members
            .whereType<FieldDeclaration>()
            .where(
              (node) => node.fields.variables
                  .map((variable) => variable.name.lexeme)
                  .toSet()
                  .contains(selectedField),
            )
            .firstOrNull;
        final annotation = corresponding?.metadata
            .where(
              (node) => node.name.toSource().split('.').last == 'ClientDefault',
            )
            .firstOrNull;
        if (annotation?.arguments?.arguments.length != 1) {
          valid = false;
          return;
        }
        final factory = unwrapFactory(
          annotation!.arguments!.arguments.single.argumentExpression,
        );
        final branchPrefix = result.unit.directives
            .whereType<ImportDirective>()
            .map((directive) => directive.prefix?.name)
            .whereType<String>()
            .where((name) => factory.toSource().startsWith('$name.'))
            .firstOrNull;
        if (shape(factory, result.unit) != shape(expression, owner)) {
          valid = false;
          return;
        }
        var routePrefix = branchPrefix;
        if (referenceSpelling != null) {
          final sourceAlias = referenceSpelling
              .thisOrAncestorOfType<GenericTypeAlias>();
          final sourceAnchor = sourceAlias ?? expression;
          final branchAnchor = sourceAlias == null
              ? factory
              : result.unit.declarations
                    .whereType<GenericTypeAlias>()
                    .where(
                      (node) => node.name.lexeme == sourceAlias.name.lexeme,
                    )
                    .firstOrNull;
          final sourceTypes = typeOccurrences(sourceAnchor);
          final occurrence = sourceTypes.indexWhere(
            (type) => type.offset == referenceSpelling.offset,
          );
          final branchTypes = branchAnchor == null
              ? <NamedType>[]
              : typeOccurrences(branchAnchor);
          if (occurrence < 0 ||
              occurrence >= branchTypes.length ||
              branchTypes[occurrence].name.lexeme !=
                  referenceSpelling.name.lexeme) {
            valid = false;
            return;
          }
          routePrefix = branchTypes[occurrence].importPrefix?.name.lexeme;
        }

        if (publicEntrypoint) {
          final exposed = origin(publicEntrypointFile!, symbol, {});
          final occurrence = occurrenceOrigin(file, result.unit, routePrefix);
          if (exposed == null || exposed != occurrence) {
            valid = false;
          }
        }

        if (!publicEntrypoint &&
            !implicitCore &&
            (expected.isEmpty ||
                !result.unit.directives.whereType<ImportDirective>().any(
                  (directive) =>
                      directive.prefix?.name == routePrefix &&
                      exposes(directive) &&
                      expected.contains(route(directive, result.uri)),
                ))) {
          valid = false;
        }
        if (!publicEntrypoint &&
            implicitCore &&
            result.unit.directives.whereType<ImportDirective>().any(
              (directive) =>
                  directive.prefix?.name == routePrefix &&
                  exposes(directive) &&
                  !expected.contains(route(directive, result.uri)) &&
                  !harmlessImports.contains(route(directive, result.uri)),
            )) {
          valid = false;
        }
        return;
      }
      for (final directive
          in result.unit.directives.whereType<ExportDirective>()) {
        if (directive.combinators.any(
          (combinator) => switch (combinator) {
            ShowCombinator() => !combinator.shownNames.any(
              (name) => name.name == mixin.name.lexeme,
            ),
            HideCombinator() => combinator.hiddenNames.any(
              (name) => name.name == mixin.name.lexeme,
            ),
          },
        )) {
          continue;
        }
        for (final branch in branches(
          directive.uri,
          directive.configurations,
          conditions,
        )) {
          final literal = branch.$1;
          final value = literal.stringValue!;
          // SDK libraries cannot declare this user-owned annotated mixin.
          if (Uri.parse(value).isScheme('dart')) continue;
          final next = path(file, value);
          if (next == null) {
            valid = false;
          } else {
            visit(next, branch.$2);
          }
        }
      }
    }

    for (final directive in model.directives.whereType<ImportDirective>()) {
      if (directive.prefix?.name != applied?.importPrefix?.name.lexeme ||
          directive.libraryImport?.namespace.definedNames2[mixin.name.lexeme] !=
              mixin.declaredFragment!.element) {
        continue;
      }
      for (final branch in branches(
        directive.uri,
        directive.configurations,
        const {},
      )) {
        final literal = branch.$1;
        final next = path(
          model.declaredFragment!.source.fullName,
          literal.stringValue!,
        );
        if (next == null) {
          valid = false;
        } else {
          publicEntrypointFile = next;
          visit(next, branch.$2);
        }
      }
    }
    return valid && found > 0;
  }

  void validateInferredType(
    Element symbol,
    Expression expression,
    AstNode context,
  ) {
    if (symbol.isPrivate) {
      failAt(
        expression,
        'DEFAULT',
        'Cannot expose inferred private factory type ${symbol.name}. Spell a public type argument explicitly.',
      );
    }
    if (symbol.library!.uri.isScheme('dart')) return;
    final owner = expression.root as CompilationUnit;
    if (_conditionalOwner(owner, context, expression) ||
        owner.directives.whereType<ImportDirective>().any((directive) {
          final library = directive.libraryImport?.importedLibrary;
          return library != null &&
              _reaches(library, symbol.library!, {}) &&
              (directive.configurations.isNotEmpty ||
                  _conditionalExport(library, symbol.library!, {}));
        })) {
      failAt(
        expression,
        'DEFAULT',
        'Cannot preserve the public route of inferred factory type ${symbol.name}. Spell the type argument explicitly.',
      );
    }
  }

  String? _sourcePrefix(Expression expression) {
    final value = unwrapFactory(
      expression is FunctionReference ? expression.function : expression,
    );
    return switch (value) {
      PrefixedIdentifier(:final prefix) when prefix.element is PrefixElement =>
        prefix.name,
      PropertyAccess(:final target?) => _sourcePrefix(target),
      ConstructorReference(:final constructorName) =>
        constructorName.type.importPrefix?.name.lexeme,
      _ => null,
    };
  }

  TypeAliasElement? _sourceAlias(Expression expression) {
    final value = unwrapFactory(
      expression is FunctionReference ? expression.function : expression,
    );
    final element = switch (value) {
      SimpleIdentifier() => value.element,
      PrefixedIdentifier(:final prefix, :final identifier) =>
        prefix.element is PrefixElement ? identifier.element : prefix.element,
      PropertyAccess(:final target?) => _sourceAlias(target),
      ConstructorReference(:final constructorName) =>
        constructorName.type.element,
      _ => null,
    };
    return element is TypeAliasElement ? element : null;
  }

  bool _reaches(
    LibraryElement from,
    LibraryElement target,
    Set<LibraryElement> visited,
  ) {
    if (from == target) return true;
    if (!visited.add(from)) return false;
    return from.exportedLibraries.any(
      (next) => _reaches(next, target, visited),
    );
  }

  bool _conditionalExport(
    LibraryElement from,
    LibraryElement target,
    Set<LibraryElement> visited,
  ) {
    if (from == target || !visited.add(from)) return false;
    for (final fragment in from.fragments) {
      final parsed = from.session.getParsedUnit(fragment.source.fullName);
      for (final export in fragment.libraryExports) {
        final next = export.exportedLibrary;
        if (next == null || !_reaches(next, target, {})) continue;
        if (parsed is ParsedUnitResult &&
            parsed.unit.directives.whereType<ExportDirective>().any(
              (directive) =>
                  directive.exportKeyword.offset ==
                      export.exportKeywordOffset &&
                  directive.configurations.isNotEmpty,
            )) {
          return true;
        }
        if (_conditionalExport(next, target, visited)) return true;
      }
    }
    return false;
  }
}
