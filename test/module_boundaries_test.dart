import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:test/test.dart';

void main() {
  test('independent modules use public entrypoints without runtime/dev cycles', () {
    final root = Directory.current.uri;
    final library = Directory('lib');
    final errors = <String>[];
    final graph = <String, Set<String>>{};
    final developmentPackages = {
      'analyzer',
      'dart_style',
      'path',
      'test',
      'lints',
    };
    for (final file
        in library
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      final relative = root.resolve(file.path).path.substring(root.path.length);
      final segments = relative.split('/');
      final internal = segments.length >= 4 && segments[1] == 'src';
      final module = internal
          ? segments[2]
          : segments.last.replaceFirst('.dart', '');
      graph.putIfAbsent(module, () => {});
      final unit = parseString(
        content: file.readAsStringSync(),
        path: file.path,
      ).unit;
      if (!internal && unit.declarations.isNotEmpty) {
        errors.add(
          '$relative: entrypoints contain exports, not implementation',
        );
      }
      for (final directive in unit.directives) {
        if (directive is PartDirective || directive is PartOfDirective) {
          errors.add('$relative: part libraries are forbidden');
        }
        if (directive is! NamespaceDirective) continue;
        final uris = [
          directive.uri.stringValue!,
          for (final configuration in directive.configurations)
            configuration.uri.stringValue!,
        ];
        for (final source in uris) {
          if (!internal) {
            final explicitNativeExport =
                source.startsWith('package:') &&
                !source.startsWith('package:orm/') &&
                directive.combinators.isNotEmpty &&
                directive.combinators.every((c) => c is ShowCombinator);
            if (directive is! ExportDirective ||
                (!source.startsWith('src/$module/') && !explicitNativeExport) ||
                source.contains('..')) {
              errors.add(
                '$relative: entrypoint may only export its own src/$module files ($source)',
              );
            }
            continue;
          }
          if (source.startsWith('package:orm/')) {
            final target = source.substring('package:orm/'.length);
            if (target.contains('/') || !target.endsWith('.dart')) {
              errors.add(
                '$relative: cross-module dependency must use a public barrel ($source)',
              );
              continue;
            }
            final targetModule = target.replaceFirst('.dart', '');
            if (!File('lib/$target').existsSync()) {
              errors.add('$relative: missing public entrypoint $source');
            }
            if (targetModule == module) {
              errors.add(
                '$relative: own-module dependencies must be relative ($source)',
              );
            } else {
              graph[module]!.add(targetModule);
            }
            if (module != 'dev' && targetModule == 'dev') {
              errors.add('$relative: runtime module depends on dev');
            }
          } else if (source.startsWith('package:')) {
            final package = source
                .substring('package:'.length)
                .split('/')
                .first;
            if (module != 'dev' && developmentPackages.contains(package)) {
              errors.add(
                '$relative: runtime module depends on development package $package',
              );
            }
          } else if (!source.startsWith('dart:')) {
            final resolved = root.resolve(file.path).resolve(source).path;
            if (!resolved.startsWith(root.resolve('lib/src/$module/').path)) {
              errors.add(
                '$relative: relative dependency escapes its module ($source)',
              );
            }
          }
        }
      }
    }
    void visit(String module, Set<String> chain) {
      if (chain.contains(module)) {
        errors.add(
          'Module dependency cycle: ${[...chain, module].join(' -> ')}',
        );
        return;
      }
      for (final dependency in graph[module] ?? <String>{}) {
        visit(dependency, {...chain, module});
      }
    }

    for (final module in graph.keys) {
      if (!File('lib/$module.dart').existsSync()) {
        errors.add('Module $module has no public entrypoint');
      }
      visit(module, {});
    }
    expect(errors, isEmpty, reason: errors.join('\n'));
  });

  test('CLI and generated examples use independent public libraries', () {
    final errors = <String>[];
    final files = <File>[
      ...Directory('bin').listSync(recursive: true).whereType<File>(),
      ...Directory('example').listSync().whereType<File>(),
      ...Directory('example/migrations')
          .listSync(recursive: true)
          .whereType<File>(),
    ].where((file) => file.path.endsWith('.dart'));
    for (final file in files) {
      final unit = parseString(
        content: file.readAsStringSync(),
        path: file.path,
      ).unit;
      for (final directive in unit.directives) {
        if (directive is PartDirective || directive is PartOfDirective) {
          errors.add('${file.path}: part libraries are forbidden');
        }
        if (directive is NamespaceDirective) {
          for (final uri in [
            directive.uri,
            ...directive.configurations.map((c) => c.uri),
          ]) {
            if (uri.stringValue!.startsWith('package:orm/src/')) {
              errors.add('${file.path}: uses a private ORM module');
            }
            if (file.path.startsWith('example/migrations/') &&
                (uri.stringValue!.contains('models') ||
                    uri.stringValue!.contains('.snapshot.'))) {
              errors.add(
                '${file.path}: history depends on current application schema',
              );
            }
          }
        }
      }
    }
    expect(errors, isEmpty, reason: errors.join('\n'));
  });
}
