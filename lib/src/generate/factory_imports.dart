import 'dart:convert';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import 'schema/diagnostics.dart';

/// A factory-only public qualifier, with constructor arguments in that scope.
final class FactoryTarget {
  final Element symbol;
  final AstNode spelling;
  final List<String>? arguments;
  final bool expanded;
  final String? reference;
  const FactoryTarget(
    this.symbol,
    this.spelling,
    this.arguments, {
    this.expanded = false,
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
      final value = expression is FunctionReference
          ? expression.function
          : expression;
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
    while (alias != null && alias.isPrivate) {
      if (!visited.add(alias) ||
          alias.library != owner.declaredFragment!.element) {
        failAt(
          expression,
          'DEFAULT',
          'Cannot resolve this local factory alias to a unique public entrypoint.',
        );
      }
      // The model itself is one fixed source library. A private alias in a
      // platform-selected mixin cannot be imported under its original name.
      if (context.root != owner &&
          _conditionalOwner(owner, context, expression)) {
        failAt(
          expression,
          'DEFAULT',
          'The conditional mixin does not expose its private factory alias. Expose a public alias through the mixin entrypoint to preserve each branch selection.',
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
    );
    return FactoryTarget(
      symbol,
      spelling,
      arguments,
      expanded: expanded,
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
    final unit = local ? model : owner;
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
    final prefix = local
        ? applied?.importPrefix?.name.lexeme
        : target.spelling is NamedType
        ? (target.spelling as NamedType).importPrefix?.name.lexeme
        : _sourcePrefix(expression);
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
      if (local &&
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
    var needsEntrypoint = symbol is TypeAliasElement || target.expanded;
    for (final directive in candidates) {
      final base = unit.declaredFragment!.element.uri;
      final uri = base.resolve(directive.uri.stringValue!);
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
          jsonEncode(importUri(base.resolve(value.stringValue!)));
      entries.add(
        [
          literal(directive.uri),
          for (final configuration in directive.configurations)
            'if (${configuration.name.toSource()}${configuration.value == null ? '' : ' == ${configuration.value!.toSource()}'}) '
                '${literal(configuration.uri)}',
          // Only this public symbol is needed. Visibility was checked against the
          // original namespace above, including all show/hide combinators.
        ].join(' '),
      );
    }
    if (!needsEntrypoint) return null;
    if (entries.length != 1) {
      failAt(
        expression,
        'DEFAULT',
        'The client-default symbol ${symbol.name} has multiple public '
            'import routes with different platform selection. Use an '
            'unambiguous import for the model or annotation.',
      );
    }
    final entry = (entries.single, symbol.name!);
    final generated = _prefixes.putIfAbsent(
      entry,
      () => 'factories${_prefixes.length}',
    );
    return '$generated.${symbol.name}';
  }

  String? _sourcePrefix(Expression expression) {
    final value = expression is FunctionReference
        ? expression.function
        : expression;
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
    final value = expression is FunctionReference
        ? expression.function
        : expression;
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
