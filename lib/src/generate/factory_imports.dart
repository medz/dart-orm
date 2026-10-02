import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import 'schema/diagnostics.dart';
import 'source.dart';

Expression unwrapFactory(Expression value) {
  while (value is ParenthesizedExpression) {
    value = value.expression;
  }
  return value;
}

/// A factory-only public qualifier, with constructor arguments in that scope.
final class FactoryTarget {
  final Element symbol;
  final AstNode spelling;
  final List<String>? arguments;
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
final class FactoryImports(final String Function(Uri) importUri) {
  final Map<(String, String), String> _prefixes = {};

  Iterable<String> get directives => _prefixes.entries.map(
    (entry) => 'import ${entry.key.$1} as ${entry.value} show ${entry.key.$2};',
  );

  FactoryTarget resolve(
    Element symbol,
    Expression expression,
    AstNode context, {
    FunctionType? constructor,
    required String Function(DartType, Map<TypeParameterElement, String>)
    render,
  }) {
    final owner = expression.root as CompilationUnit;
    var alias = _sourceAlias(expression);
    AstNode spelling = expression;
    List<String>? arguments;
    var expanded = false;
    if (constructor != null && alias != null) {
      final value = unwrapFactory(
        expression is FunctionReference ? expression.function : expression,
      );
      final named = value is ConstructorReference
          ? value.constructorName.type
          : null;
      if (named == null) {
        failAt(
          expression,
          'DEFAULT',
          'Cannot resolve the constructor alias qualifier.',
        );
      }
      arguments = _arguments(named, {}, render, expression);
      if (arguments.length != alias.typeParameters.length) {
        final inferred = constructor.returnType.alias;
        if (inferred?.element == alias) {
          arguments = inferred!.typeArguments
              .map((type) => render(type, {}))
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
      if (body is! NamedType || body.element == null) {
        failAt(
          expression,
          'DEFAULT',
          'A factory qualifier alias must resolve to a named public type.',
        );
      }
      expandedAliases.add(declaration!);
      final environment = <TypeParameterElement, String>{};
      if (constructor != null) {
        if (arguments!.length != alias.typeParameters.length) {
          failAt(
            expression,
            'DEFAULT',
            'Cannot determine this factory alias constructor type arguments.',
          );
        }
        for (var index = 0; index < arguments.length; index++) {
          environment[alias.typeParameters[index]] = arguments[index];
        }
        arguments = _arguments(body, environment, render, expression);
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
      reference: _reference(target, expression, context),
    );
  }

  List<String> _arguments(
    NamedType type,
    Map<TypeParameterElement, String> environment,
    String Function(DartType, Map<TypeParameterElement, String>) render,
    Expression expression,
  ) {
    final explicit = type.typeArguments?.arguments;
    if (explicit != null) {
      return [
        for (final argument in explicit)
          if (argument.type case final resolved?)
            render(resolved, environment)
          else
            failAt(
              expression,
              'DEFAULT',
              'Cannot resolve a constructor alias type argument.',
            ),
      ];
    }
    // Alias bodies may instantiate a generic type to its bounds without spelling
    // arguments. Keep that resolved instantiation rather than inferring anew in
    // the generated callback's context.
    final resolved = type.type;
    final inferred =
        resolved?.alias?.typeArguments ??
        (resolved is InterfaceType
            ? resolved.typeArguments
            : const <DartType>[]);
    return [for (final argument in inferred) render(argument, environment)];
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
    AstNode context,
  ) {
    final symbol = target.symbol;
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
          !_sharedExternalRoute(owner, context, expression, symbol)) {
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
      () => 'factories${_prefixes.length}',
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
    final packages = <String, String>{};
    final libraries = <LibraryElement>{};
    void register(LibraryElement library) {
      if (!libraries.add(library)) return;
      final uri = library.uri;
      if (uri.scheme == 'package') {
        final relative = uri.pathSegments.skip(1).join('/');
        final path = library.firstFragment.source.fullName;
        if (path.endsWith(relative)) {
          packages[uri.pathSegments.first] = path.substring(
            0,
            path.length - relative.length,
          );
        }
      }
      for (final exported in library.exportedLibraries) {
        register(exported);
      }
    }

    register(owner.declaredFragment!.element);
    register(model.declaredFragment!.element);
    for (final directive in model.directives.whereType<ImportDirective>()) {
      if (directive.libraryImport?.importedLibrary case final imported?) {
        register(imported);
      }
    }
    String? path(String base, String value) {
      final uri = Uri.parse(value);
      if (uri.scheme == 'package') {
        final root = packages[uri.pathSegments.first];
        return root == null
            ? null
            : '$root${uri.pathSegments.skip(1).join('/')}';
      }
      final resolved = Uri.file(base).resolveUri(uri);
      return resolved.scheme == 'file' ? resolved.toFilePath() : null;
    }

    String route(ImportDirective directive, Uri base) => [
      base.resolve(directive.uri.stringValue!).toString(),
      for (final config in directive.configurations)
        '${config.name.toSource()}=${config.value?.toSource()}:${base.resolve(config.uri.stringValue!)}',
    ].join('|');
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
    final prefix = _sourcePrefix(expression);
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
    String tail(Expression value, String? prefix) {
      final text = value.toSource();
      return prefix == null ? text : text.substring(prefix.length + 1);
    }

    String aliasShape(GenericTypeAlias alias, CompilationUnit unit) {
      var text =
          '${alias.typeParameters?.toSource() ?? ''}:${alias.type.toSource()}';
      final prefixes =
          unit.directives
              .whereType<ImportDirective>()
              .map((directive) => directive.prefix?.name)
              .whereType<String>()
              .toList()
            ..sort((left, right) => right.length.compareTo(left.length));
      for (final prefix in prefixes) {
        text = text.replaceAll('$prefix.', '');
      }
      return text;
    }

    final fields = field.fields.variables
        .map((variable) => variable.name.lexeme)
        .toSet();
    var valid = true;
    final visited = <String>{};
    var found = 0;
    void visit(String file) {
      if (!visited.add(file)) return;
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
            result.unit.declarations.any(
              (node) => switch (node) {
                FunctionDeclaration() => node.name.lexeme == symbol,
                ClassDeclaration() => node.namePart.typeName.lexeme == symbol,
                GenericTypeAlias() => node.name.lexeme == symbol,
                TopLevelVariableDeclaration() => node.variables.variables.any(
                  (variable) => variable.name.lexeme == symbol,
                ),
                _ => false,
              },
            )) {
          valid = false;
          return;
        }
        for (final alias in aliases) {
          final counterpart = result.unit.declarations
              .whereType<GenericTypeAlias>()
              .where((node) => node.name.lexeme == alias.name.lexeme)
              .firstOrNull;
          if (counterpart == null ||
              aliasShape(counterpart, result.unit) !=
                  aliasShape(alias, owner)) {
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
                  .containsAll(fields),
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
        if (tail(factory, branchPrefix) != tail(expression, prefix)) {
          valid = false;
          return;
        }
        if (!publicEntrypoint &&
            !implicitCore &&
            (expected.isEmpty ||
                !result.unit.directives.whereType<ImportDirective>().any(
                  (directive) =>
                      directive.prefix?.name == branchPrefix &&
                      exposes(directive) &&
                      expected.contains(route(directive, result.uri)),
                ))) {
          valid = false;
        }
        if (!publicEntrypoint &&
            implicitCore &&
            result.unit.directives.whereType<ImportDirective>().any(
              (directive) =>
                  directive.prefix?.name == branchPrefix &&
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
        for (final literal in [
          directive.uri,
          ...directive.configurations.map((config) => config.uri),
        ]) {
          final next = path(file, literal.stringValue!);
          if (next == null) {
            valid = false;
          } else {
            visit(next);
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
      for (final literal in [
        directive.uri,
        ...directive.configurations.map((config) => config.uri),
      ]) {
        final next = path(
          model.declaredFragment!.source.fullName,
          literal.stringValue!,
        );
        if (next == null) {
          valid = false;
        } else {
          visit(next);
        }
      }
    }
    return valid && found > 0;
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
