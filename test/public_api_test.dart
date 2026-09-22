@Tags(['core'])
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:test/test.dart';

import '../example/schema.orm.dart';

void main() {
  test('generated clients expose row types and an immutable schema', () {
    final user = User(id: 1, email: 'a', nickname: null, score: 0);
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
        final sql = await library('lib/sql.dart');
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
        expect(
          exports(schema).intersection({
            'Database',
            'TableSchema',
            'Column',
            'ForeignKey',
            'IndexSchema',
            'CheckSchema',
          }),
          isEmpty,
          reason: 'Declarations do not expose physical schema construction.',
        );
        expect(
          exports(schema),
          containsAll([
            'Model',
            'model',
            'Codec',
            'Decimal',
            'ComputedStorage',
          ]),
        );
        expect(
          exports(schema),
          isNot(
            anyOf([
              contains('entity'),
              contains('Entity'),
              contains('EntityKey'),
              contains('SchemaConstraint'),
              contains('Id'),
              contains('UseCodec'),
              contains('ColumnName'),
              contains('Unique'),
              contains('Default'),
              contains('ClientDefault'),
              contains('Computed'),
              contains('EnumValue'),
              contains('IntegerBits'),
              contains('DecimalDigits'),
              contains('TemporalPrecision'),
            ]),
          ),
        );
        final modelType =
            schema.exportNamespace.definedNames2['Model'] as ClassElement;
        expect(modelType.typeParameters, isEmpty);
        expect(
          modelType.constructors.where((c) => c.isPublic),
          isEmpty,
          reason: 'Create declarations only through model(...).',
        );
        expect(
          modelType.methods.where((m) => m.isPublic && m.isStatic),
          isEmpty,
        );
        expect(exports(runtime), isNot(contains('Migration')));
        for (final path in ['lib/mysql.dart', 'lib/drivers/mysql.dart']) {
          final names = exports(await library(path));
          expect(names, containsAll(['MysqlDriver', 'MysqlOptions']));
          expect(names, isNot(contains('MariadbDriver')));
          expect(names, isNot(contains('MariadbOptions')));
        }
        for (final path in ['lib/mariadb.dart', 'lib/drivers/mariadb.dart']) {
          final names = exports(await library(path));
          expect(names, containsAll(['MariadbDriver', 'MariadbOptions']));
          expect(names, isNot(contains('MysqlDriver')));
          expect(names, isNot(contains('MysqlOptions')));
        }
        expect(
          exports(migrate),
          containsAll(['Migration', 'SqlDialect', 'TableSchema', 'Codecs']),
        );
        expect(exports(migrate), isNot(contains('generateSchema')));
        expect(exports(generate), isNot(contains('ormBuilder')));
        expect(exports(builder), {'ormBuilder'});

        // Resolve every public library, including newly added entrypoints.
        // A show list is required whenever a facade reaches into src directly.
        final entrypoints = [
          ...Directory('lib').listSync().whereType<File>(),
          ...Directory('lib/drivers').listSync().whereType<File>(),
        ].where((file) => file.path.endsWith('.dart'));
        const implementationNames = {
          'SqlNode',
          'SqlWriter',
          'ColumnNode',
          'ParameterNode',
          'QueryState',
          'SelectionPlan',
          'RowDecoder',
          'Join',
          'CteDefinition',
          'UnionSource',
          'ReadTables',
          'MutationKind',
          'RelationBinding',
          'TypedRelationBinding',
          'ConnectionWait',
          'TransactionControl',
          'BackfillBudget',
          'BackfillPaused',
          'quoteIdentifier',
          'migrationHash',
          'readBackfillProgress',
          'diffSchema',
          'SqliteExecutor',
          'OpenedSqlite',
          'sqliteWorkerBuild',
          'databaseMembers',
          'isMysqlDialect',
        };
        for (final file in entrypoints) {
          final entry = await library(file.path);
          final namespace = entry.exportNamespace.definedNames2;
          expect(
            namespace.keys.toSet().intersection(implementationNames),
            isEmpty,
            reason: '${file.path} exports an implementation detail',
          );
          expect(
            namespace.entries
                .where((entry) => entry.value.metadata.hasInternal)
                .map((entry) => entry.key),
            isEmpty,
            reason: '${file.path} exports an @internal declaration',
          );
          final unit = parseString(
            content: file.readAsStringSync(),
            path: file.path,
          ).unit;
          for (final directive
              in unit.directives.whereType<ExportDirective>()) {
            if (directive.uri.stringValue!.split('/').contains('src')) {
              expect(
                directive.combinators.whereType<ShowCombinator>(),
                isNotEmpty,
                reason: '${file.path} broadly exports ${directive.uri}',
              );
            }
          }
        }
        final client = exports(await library('example/schema.orm.dart'));
        expect(
          client,
          containsAll(['User', 'Post', 'UserFields', 'AppTables']),
        );
        expect(
          client,
          isNot(contains('users')),
        ); // Declaration values stay in schema.dart.
        expect(
          exports(sql),
          containsAll([
            'Sql',
            'SqlQuery',
            'SqlValue',
            'ResultShape',
            'ResultColumn',
          ]),
        );
        expect(exports(sql), isNot(contains('SqlTemplate')));
        expect(exports(schema), isNot(contains('sqlQuery')));
        expect(exports(generate), isNot(contains('generateQueries')));

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
