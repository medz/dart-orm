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
        final schemaModel = await library('lib/schema_model.dart');
        final values = await library('lib/values.dart');
        final driver = await library('lib/driver.dart');
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
            'ForeignKey',
            'IndexSchema',
            'CheckSchema',
            'Codec',
            'Decimal',
            'ComputedStorage',
          }),
          isEmpty,
          reason: 'Declarations do not expose physical schema construction.',
        );
        expect(
          exports(schema),
          containsAll([
            'Model',
            'Projection',
            'Id',
            'Column',
            'Unique',
            'ClientDefault',
            'Computed',
            'Check',
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
              contains('UseCodec'),
              contains('ColumnName'),
              contains('Default'),
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
          hasLength(1),
          reason: 'Model metadata has one public constant constructor.',
        );
        expect(
          modelType.methods.where((m) => m.isPublic && m.isStatic),
          isEmpty,
        );
        expect(exports(runtime), {
          'Database',
          'DecodeEvent',
          'WatchQuery',
          'WatchSql',
          'ModelQuery',
          'ModelTable',
          'ModelWritePlan',
          'ModelTableWritePlan',
          'Write',
          'WriteRows',
          'InsertWrite',
          'BatchWrite',
        });
        expect(exports(values), containsAll(['Codec', 'Codecs', 'Decimal']));
        expect(
          exports(schemaModel),
          containsAll(['TableSchema', 'ComputedStorage']),
        );
        expect(
          exports(driver),
          containsAll(['SqlDialect', 'ExecutionOptions']),
        );
        for (final path in ['lib/mysql.dart']) {
          final names = exports(await library(path));
          expect(names, containsAll(['MysqlDriver', 'MysqlOptions']));
          expect(names, isNot(contains('MariadbDriver')));
          expect(names, isNot(contains('MariadbOptions')));
        }
        for (final path in ['lib/mariadb.dart']) {
          final names = exports(await library(path));
          expect(names, containsAll(['MariadbDriver', 'MariadbOptions']));
          expect(names, isNot(contains('MysqlDriver')));
          expect(names, isNot(contains('MysqlOptions')));
        }
        expect(
          exports(migrate),
          containsAll([
            'Migration',
            'Migrator',
            'MigrationHistory',
            'SchemaSnapshot',
          ]),
        );
        expect(
          exports(migrate)
              .intersection({'SqlDialect', 'TableSchema', 'Codecs'}),
          isEmpty,
          reason: 'Migration APIs use the unique owner of each shared type.',
        );
        expect(exports(migrate), isNot(contains('generateSchema')));
        expect(exports(generate), isNot(contains('ormBuilder')));
        expect(exports(builder), {'ormBuilder'});

        // Resolve every public library, including newly added entrypoints.
        // A show list is required whenever a facade reaches into src directly.
        final entrypoints =
            [...Directory('lib').listSync(recursive: true).whereType<File>()]
                .where(
                  (file) =>
                      file.path.endsWith('.dart') &&
                      !file.path.split('/').contains('src'),
                );
        expect(
          Directory('lib/drivers').existsSync()
              ? Directory('lib/drivers').listSync().whereType<File>().toList()
              : <File>[],
          isEmpty,
        );
        expect(File('lib/runtime.dart').existsSync(), isFalse);
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
            'Selection',
            'SelectQuery',
            'Projection',
            'ProjectedSql',
          ]),
        );
        expect(exports(sql), isNot(contains('SqlTemplate')));
        expect(exports(sql), isNot(contains('NoOutput')));
        expect(client, isNot(contains('SelectQuery')));
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
