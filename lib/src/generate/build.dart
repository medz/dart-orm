import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart' as builder;
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../../driver.dart' show SqlDialect;
import 'exception.dart';
import 'schema.dart';
import 'schema/layout.dart';

/// Factory used by build_runner's build.yaml registration.
///
/// Use `models` for a recursive model source directory, `database` for the target
/// engine, and `default_namespace` for PostgreSQL's default physical namespace.
/// Individual libraries can instead be selected with `generate_for`.
builder.Builder ormBuilder(builder.BuilderOptions options) {
  if (options.config.keys.any(
    (key) => !{'database', 'models', 'default_namespace'}.contains(key),
  )) {
    throw ArgumentError(
      'Use database, models and default_namespace builder options, or generate_for for individual libraries.',
    );
  }
  final database = options.config['database'];
  if (database != null && !SqlDialect.values.any((d) => d.name == database)) {
    throw ArgumentError('database must be sqlite, postgres, mysql or mariadb.');
  }
  final dialect = database == null
      ? null
      : SqlDialect.values.byName(database as String);
  final defaultNamespace = options.config['default_namespace'];
  if (defaultNamespace != null && defaultNamespace is! String) {
    throw ArgumentError('default_namespace must be a string.');
  }
  final models = options.config['models'];
  if (models != null) {
    if (models is! String) {
      throw ArgumentError('models must be a source root under lib/.');
    }
    final root = SchemaLayout.stem(models, paths: p.url);
    if (!p.url.isWithin('lib', root)) {
      throw ArgumentError('Put the model source root under lib/.');
    }
    return _OrmDirectoryBuilder(
      root,
      dialect,
      defaultNamespace: defaultNamespace as String?,
    );
  }
  return _OrmBuilder(
    dialect: dialect,
    defaultNamespace: defaultNamespace as String?,
  );
}

final class _OrmBuilder implements builder.Builder {
  final SqlDialect? dialect;
  final String? defaultNamespace;
  const _OrmBuilder({this.dialect, this.defaultNamespace});

  @override
  Map<String, List<String>> get buildExtensions => const {
    '.dart': ['.orm.dart', '.snapshot.dart'],
  };

  @override
  Future<void> build(builder.BuildStep step) async {
    final input = step.inputId;
    if (!await step.resolver.isLibrary(input)) {
      throw const GenerationException(
        'Select a model library, not a part file.',
      );
    }
    final output = input.changeExtension('.orm.dart');
    final (unit, library) = await _resolveSchema(step);
    final result = await generateResolvedSchema(
      unit,
      library,
      (uri) => _importPath(uri, input.package, output.path),
      dialect: dialect,
      defaultNamespace: defaultNamespace,
      resolve: (library) => _resolveReference(step, library),
    );
    // Both outputs are fully constructed before touching the build writer.
    final snapshot = result.snapshotDart;
    await step.writeAsString(output, result.dart);
    await step.writeAsString(input.changeExtension('.snapshot.dart'), snapshot);
  }

  Future<CompilationUnit> _resolveReference(
    builder.BuildStep step,
    LibraryElement library,
  ) async {
    final (unit, _) = await _resolveSchema(
      step,
      builder.AssetId.resolve(library.uri, from: step.inputId),
    );
    return unit;
  }

  Future<(CompilationUnit, LibraryElement)> _resolveSchema(
    builder.BuildStep step, [
    builder.AssetId? source,
  ]) async {
    final input = source ?? step.inputId;
    for (var attempt = 0; ; attempt++) {
      final library = await step.resolver.libraryFor(input);
      final node = await step.resolver.astNodeFor(
        library.firstFragment,
        resolve: true,
      );
      if (node is! CompilationUnit) {
        throw GenerationException('Cannot resolve model source $input.');
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
          throw GenerationException('Cannot validate model source $input.');
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

final class _OrmDirectoryBuilder implements builder.Builder {
  final String root;
  final SqlDialect? dialect;
  final String? defaultNamespace;
  const _OrmDirectoryBuilder(this.root, this.dialect, {this.defaultNamespace});

  @override
  Map<String, List<String>> get buildExtensions => {
    r'$lib$': [
      '${p.url.relative(root, from: 'lib')}.orm.dart',
      '${p.url.relative(root, from: 'lib')}.snapshot.dart',
    ],
  };

  @override
  Future<void> build(builder.BuildStep step) async {
    final layout = SchemaLayout(root, directory: true, paths: p.url);
    final package = step.inputId.package;
    final sources = <builder.AssetId>[];
    final file = builder.AssetId(package, layout.file);
    if (await step.canRead(file)) sources.add(file);
    sources.addAll(await step.findAssets(Glob('$root/**.dart')).toList());
    sources.removeWhere((f) => !SchemaLayout.declaration(f.path));
    sources.sort((a, b) => a.path.compareTo(b.path));
    if (sources.isEmpty) {
      return; // Deleting the definitions removes owned outputs.
    }
    final units = <CompilationUnit>[];
    final resolver = _OrmBuilder(dialect: dialect);
    for (final source in sources) {
      if (!await step.resolver.isLibrary(source)) {
        throw GenerationException(
          'Use independent Dart model libraries: $source',
        );
      }
      final (unit, _) = await resolver._resolveSchema(step, source);
      units.add(unit);
    }
    final output = builder.AssetId(package, layout.output);
    final library = units.first.declaredFragment!.element;
    final result = await generateResolvedSchema(
      units.first,
      library,
      (uri) => _importPath(uri, package, output.path),
      resolve: (owner) => resolver._resolveReference(step, owner),
      additionalRoots: units.skip(1).toList(),
      dialect: dialect,
      defaultNamespace: defaultNamespace,
    );
    final snapshot = result.snapshotDart;
    await step.writeAsString(output, result.dart);
    await step.writeAsString(
      builder.AssetId(package, '$root.snapshot.dart'),
      snapshot,
    );
  }
}

String _importPath(Uri uri, String package, String output) {
  if (uri.scheme != 'asset') return uri.toString();
  final asset = builder.AssetId.resolve(uri);
  if (asset.package == package) {
    return p.url.relative(asset.path, from: p.url.dirname(output));
  }
  if (!p.url.isWithin('lib', asset.path)) {
    throw GenerationException(
      'Cannot import $uri from another package; put public domain types under lib/.',
    );
  }
  return 'package:${asset.package}/${p.url.relative(asset.path, from: 'lib')}';
}
