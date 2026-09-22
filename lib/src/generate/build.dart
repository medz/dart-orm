import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart' as builder;
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../../driver.dart' show SqlDialect;
import 'exception.dart';
import 'queries.dart';
import 'schema.dart';
import 'schema/layout.dart';

/// Factory used by build_runner's build.yaml registration.
builder.Builder ormBuilder(builder.BuilderOptions options) {
  if (options.config.keys.any((key) => !{'database', 'schema'}.contains(key))) {
    throw ArgumentError(
      'Use database and schema builder options, or generate_for for individual libraries.',
    );
  }
  final database = options.config['database'];
  if (database != null && !SqlDialect.values.any((d) => d.name == database)) {
    throw ArgumentError('database must be sqlite, postgres, mysql or mariadb.');
  }
  final dialect = database == null
      ? null
      : SqlDialect.values.byName(database as String);
  final schema = options.config['schema'];
  if (schema != null) {
    if (schema is! String || dialect == null) {
      throw ArgumentError(
        'Directory generation needs schema: lib/schema and database: engine.',
      );
    }
    final root = SchemaLayout.stem(schema);
    if (!p.url.isWithin('lib', root)) {
      throw ArgumentError('Put the schema root under lib/.');
    }
    return _OrmDirectoryBuilder(root, dialect);
  }
  return _OrmBuilder(dialect: dialect);
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
  final SqlDialect? dialect;
  const _OrmBuilder({this.dialect});
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
    final result = await generateResolvedSchema(
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
      dialect: dialect,
      stableOrder: dialect != null,
      namespaceOf: dialect == SqlDialect.postgres ? (_) => 'public' : null,
      resolve: (library) async {
        final node = await step.resolver.astNodeFor(
          library.firstFragment,
          resolve: true,
        );
        if (node is! CompilationUnit) {
          throw GenerationException('Cannot resolve schema ${library.uri}.');
        }
        final errors = await node.declaredFragment!.element.session.getErrors(
          library.firstFragment.source.fullName,
        );
        if (errors is! ErrorsResult) {
          throw GenerationException('Cannot validate schema ${library.uri}.');
        }
        final failures = errors.diagnostics.where(
          (e) => e.severity.name.toLowerCase() == 'error',
        );
        if (failures.isNotEmpty) throw GenerationException(failures.join('\n'));
        return node;
      },
    );
    // Both outputs are fully constructed before touching the build writer.
    final snapshot = result.snapshotDart;
    await step.writeAsString(output, result.dart);
    await step.writeAsString(input.changeExtension('.snapshot.dart'), snapshot);
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

final class _OrmDirectoryBuilder(final String root, final SqlDialect dialect)
    implements builder.Builder {
  @override
  Map<String, List<String>> get buildExtensions => {
    r'$lib$': [
      '${p.url.relative(root, from: 'lib')}.orm.dart',
      '${p.url.relative(root, from: 'lib')}.snapshot.dart',
    ],
  };

  @override
  Future<void> build(builder.BuildStep step) async {
    final layout = SchemaLayout(root, dialect: dialect, directory: true);
    final package = step.inputId.package;
    final sources = <builder.AssetId>[];
    final file = builder.AssetId(package, layout.file);
    if (await step.canRead(file)) sources.add(file);
    final direct = await step.findAssets(Glob('$root/*.dart')).toList();
    if (dialect == SqlDialect.postgres &&
        direct.any((f) => SchemaLayout.declaration(f.path))) {
      throw GenerationException(
        'Put PostgreSQL declarations in $root/{schema}/*.dart.',
      );
    }
    sources.addAll(
      dialect == SqlDialect.postgres
          ? await step.findAssets(Glob('$root/*/*.dart')).toList()
          : direct,
    );
    sources.removeWhere((f) => !SchemaLayout.declaration(f.path));
    sources.sort((a, b) => a.path.compareTo(b.path));
    if (sources.isEmpty) {
      return; // Deleting the definition removes owned outputs.
    }
    final units = <CompilationUnit>[];
    final paths = <LibraryElement, String>{};
    final resolver = _OrmBuilder(dialect: dialect);
    for (final source in sources) {
      if (!await step.resolver.isLibrary(source)) {
        throw GenerationException(
          'Use independent Dart schema libraries: $source',
        );
      }
      final (unit, library) = await resolver._resolveSchema(step, source);
      units.add(unit);
      paths[library] = source.path;
    }
    final output = builder.AssetId(package, layout.output);
    final library = units.first.declaredFragment!.element;
    final result = await generateResolvedSchema(
      units.first,
      library,
      p.url.relative(sources.first.path, from: p.url.dirname(output.path)),
      (uri) {
        if (uri.scheme != 'asset') return uri.toString();
        final asset = builder.AssetId.resolve(uri);
        return asset.package == package
            ? p.url.relative(asset.path, from: p.url.dirname(output.path))
            : 'package:${asset.package}/${p.url.relative(asset.path, from: 'lib')}';
      },
      resolve: (owner) async {
        final node = await step.resolver.astNodeFor(
          owner.firstFragment,
          resolve: true,
        );
        if (node is! CompilationUnit) {
          throw GenerationException('Cannot resolve ${owner.uri}.');
        }
        return node;
      },
      additionalRoots: units.skip(1).toList(),
      namespaceOf: (variable) {
        final owner = variable.declaredFragment!.element.library!;
        final path = paths[owner];
        if (path == null) {
          throw GenerationException(
            'Model declared outside the schema layout: ${owner.uri}',
          );
        }
        return layout.namespace(path);
      },
      stableOrder: true,
      dialect: dialect,
    );
    final snapshot = result.snapshotDart;
    await step.writeAsString(output, result.dart);
    await step.writeAsString(
      builder.AssetId(package, '$root.snapshot.dart'),
      snapshot,
    );
  }
}
