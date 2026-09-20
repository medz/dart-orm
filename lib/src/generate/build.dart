import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart' as builder;
import 'package:path/path.dart' as p;

import 'exception.dart';
import 'queries.dart';
import 'schema.dart';

/// Factory used by build_runner's build.yaml registration.
builder.Builder ormBuilder(builder.BuilderOptions options) {
  if (options.config.isNotEmpty) {
    throw ArgumentError(
      'ORM has no builder-specific options. Select schema roots with generate_for.',
    );
  }
  return const _OrmBuilder();
}

/// Fixed SQL files are read as build assets so their edits invalidate output.
builder.Builder ormQueryBuilder(builder.BuilderOptions options) {
  if (options.config.isNotEmpty) {
    throw ArgumentError('Select named SQL libraries with generate_for.');
  }
  return const _OrmQueryBuilder();
}

final class _OrmQueryBuilder implements builder.Builder {
  const _OrmQueryBuilder();
  @override
  Map<String, List<String>> get buildExtensions => const {
    '.dart': ['.queries.dart'],
  };
  @override
  Future<void> build(builder.BuildStep step) async {
    final input = step.inputId;
    if (!await step.resolver.isLibrary(input)) {
      throw const GenerationException(
        'Select a query library, not a part file.',
      );
    }
    final output = input.changeExtension('.queries.dart');
    final (unit, library) = await const _OrmBuilder()._resolveSchema(step);
    final result = await generateResolvedQueries(
      unit,
      library,
      p.url.relative(input.path, from: p.url.dirname(output.path)),
      (uri) {
        if (uri.scheme != 'asset') return uri.toString();
        final asset = builder.AssetId.resolve(uri);
        if (asset.package != input.package) {
          throw GenerationException('Put public domain types under lib/: $uri');
        }
        return p.url.relative(asset.path, from: p.url.dirname(output.path));
      },
      (path) => step.readAsString(
        builder.AssetId.resolve(Uri.parse(path), from: input),
      ),
    );
    await step.writeAsString(output, result.dart);
  }
}

final class _OrmBuilder implements builder.Builder {
  const _OrmBuilder();
  @override
  Map<String, List<String>> get buildExtensions => const {
    '.dart': ['.orm.dart', '.snapshot.dart'],
  };

  @override
  Future<void> build(builder.BuildStep step) async {
    final input = step.inputId;
    if (!await step.resolver.isLibrary(input)) {
      throw const GenerationException(
        'Select a schema library, not a part file.',
      );
    }
    final output = input.changeExtension('.orm.dart');
    final (unit, library) = await _resolveSchema(step);
    final result = generateResolvedSchema(
      unit,
      library,
      p.url.relative(input.path, from: p.url.dirname(output.path)),
      (uri) {
        if (uri.scheme != 'asset') return uri.toString();
        final asset = builder.AssetId.resolve(uri);
        if (asset.package != input.package) {
          throw GenerationException(
            'Cannot import $uri from another package; put public domain types under lib/.',
          );
        }
        return p.url.relative(asset.path, from: p.url.dirname(output.path));
      },
    );
    // Both outputs are fully constructed before touching the build writer.
    final snapshot = result.snapshotDart;
    await step.writeAsString(output, result.dart);
    await step.writeAsString(input.changeExtension('.snapshot.dart'), snapshot);
  }

  Future<(CompilationUnit, LibraryElement)> _resolveSchema(
    builder.BuildStep step,
  ) async {
    for (var attempt = 0; ; attempt++) {
      final library = await step.resolver.libraryFor(step.inputId);
      final node = await step.resolver.astNodeFor(
        library.firstFragment,
        resolve: true,
      );
      if (node is! CompilationUnit) {
        throw GenerationException('Cannot resolve schema ${step.inputId}.');
      }
      final resolvedLibrary = node.declaredFragment!.element;
      try {
        // Resolver's syntax check omits semantic errors. Check those through
        // the public session only after resolver-owned AST resolution. Other
        // concurrent build steps may replace that session; retry resolution.
        final diagnostics = await resolvedLibrary.session.getErrors(
          resolvedLibrary.firstFragment.source.fullName,
        );
        if (diagnostics is! ErrorsResult) {
          throw GenerationException('Cannot validate schema ${step.inputId}.');
        }
        final errors = diagnostics.diagnostics.where(
          (e) => e.severity.name.toLowerCase() == 'error',
        );
        if (errors.isNotEmpty) {
          throw GenerationException(errors.map((e) => e.toString()).join('\n'));
        }
        return (node, resolvedLibrary);
      } on InconsistentAnalysisException {
        if (attempt >= 2) rethrow;
      }
    }
  }
}
