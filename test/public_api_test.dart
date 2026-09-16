import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:test/test.dart';

import '../example/schema.orm.dart';

void main() {
  test('generated clients expose row types and an immutable schema', () {
    const User user = (id: 1, email: 'a', nickname: null, score: 0);
    expect(user.id, 1);
    expect(appSchema.clear, throwsUnsupportedError);
  });

  test(
    'entrypoint exports and runtime dependency boundaries stay explicit',
    () async {
      final contexts = AnalysisContextCollection(
        includedPaths: [Directory.current.absolute.path],
      );
      try {
        Future<LibraryElement> library(String path) async {
          final absolute = File(path).absolute.path;
          final result = await contexts
              .contextFor(absolute)
              .currentSession
              .getResolvedLibrary(absolute);
          return (result as ResolvedLibraryResult).element;
        }

        Set<String> exports(LibraryElement library) =>
            library.exportNamespace.definedNames2.keys.toSet();
        final runtime = await library('lib/orm.dart');
        final schema = await library('lib/schema.dart');
        final migrate = await library('lib/migrate.dart');
        final generate = await library('lib/generate.dart');
        final builder = await library('lib/builder.dart');
        final sqlite = exports(await library('lib/sqlite.dart'));
        expect(
          sqlite,
          containsAll([
            'sqlite',
            'SqliteDriver',
            'SqliteOptions',
            'SqliteWebOptions',
          ]),
        );
        expect(
          sqlite,
          isNot(
            anyOf(
              contains('SqliteExecutor'),
              contains('OpenedSqlite'),
              contains('sqliteWorkerBuild'),
            ),
          ),
        );
        expect(exports(schema), isNot(contains('Database')));
        expect(exports(runtime), isNot(contains('Migration')));
        expect(
          exports(migrate),
          containsAll(['Migration', 'SqlDialect', 'TableSchema', 'Codecs']),
        );
        expect(exports(migrate), isNot(contains('generateSchema')));
        expect(exports(generate), isNot(contains('ormBuilder')));
        expect(exports(builder), {'ormBuilder', 'ormQueryBuilder'});
        final client = exports(await library('example/schema.orm.dart'));
        expect(
          client,
          containsAll(['User', 'Post', 'UsersFields', 'AppTables']),
        );
        expect(
          client,
          isNot(contains('users')),
        ); // Declaration values stay in schema.dart.
        expect(
          exports(await library('test/support/named_sql/queries.queries.dart')),
          containsAll(['AuthorStats', 'Echo']),
        );

        final visited = <Uri>{};
        void visit(LibraryElement library) {
          if (!visited.add(library.uri)) return;
          // SDK implementation imports depend on the analyzer's host platform.
          if (library.uri.scheme == 'dart') return;
          for (final dependency in [
            ...library.exportedLibraries,
            for (final fragment in library.fragments)
              ...fragment.importedLibraries,
          ]) {
            visit(dependency);
          }
        }

        for (final entry in [runtime, schema, migrate]) {
          visit(entry);
        }
        for (final uri in visited) {
          expect(uri.toString(), isNot(startsWith('package:analyzer/')));
          expect(uri.toString(), isNot(startsWith('package:build/')));
          expect(
            uri.toString(),
            isNot(anyOf('dart:io', 'dart:ffi', 'dart:isolate')),
          );
        }
      } finally {
        await contexts.dispose();
      }
    },
  );
}
