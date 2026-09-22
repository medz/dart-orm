@Tags(['core'])
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:orm/driver.dart' as raw;
import 'package:orm/migrate.dart' as migrations;
import 'package:orm/schema_model.dart' as schema;
import 'package:orm/sql.dart' as sql;
import 'package:orm/values.dart' as values;
import 'package:test/test.dart';

void main() {
  test(
    'libraries, executables, and generated fixtures are standalone Dart',
    () {
      final files = [
        for (final root in ['lib', 'bin', 'tool', 'example', 'test'])
          ..._dartFiles(Directory(root)),
      ];
      expect(files, isNotEmpty);
      expect(files.any((file) => file.path.endsWith('.orm.dart')), isTrue);
      expect(files.any((file) => file.path.endsWith('.snapshot.dart')), isTrue);
      expect(files.any((file) => file.path.endsWith('.queries.dart')), isFalse);
      for (final file in files) {
        final unit = parseString(
          content: file.readAsStringSync(),
          path: file.path,
        ).unit;
        expect(
          unit.directives.where(
            (directive) =>
                directive is PartDirective || directive is PartOfDirective,
          ),
          isEmpty,
          reason: '${file.path} must import and export standalone libraries',
        );
      }
    },
  );

  test('values and metadata can be authored without a query or session', () {
    final decimal = values.Decimal.parse('9007199254740993.01');
    expect(
      values.Codecs.decimal.decode(values.Codecs.decimal.encode(decimal)),
      decimal,
    );
    final nullable = values.Codecs.text.nullable();
    expect(nullable.sameStorageAs(values.Codecs.text.nullable()), isTrue);
    expect(nullable.sameStorageAs(values.Codecs.text), isFalse);
    final table = schema.TableSchema(
      'independent',
      columns: [schema.Column('amount', values.Codecs.decimal)],
    );
    final ddl = migrations.createSchema([table], raw.SqlDialect.sqlite);
    expect(ddl.first.sql, contains('CREATE TABLE "independent"'));
  });

  test(
    'a raw driver executes commands without constructing an ORM runtime',
    () async {
      final driver = _RawDriver();
      final result = await driver.run(
        (connection) =>
            connection.execute(raw.SqlCommand('SELECT value', [42])),
      );
      expect(result.rows, [
        [42],
      ]);
      expect(result.columns, ['value']);
      await driver.close();
    },
  );

  test('typed queries compile without a driver or a runtime session', () {
    final builder = sql.SqlBuilder(raw.SqlDialect.postgres);
    final query = builder
        .table(_table)
        .where((row) => row.id.gt(.value(12)))
        .take(5);
    final command = query.compile();
    expect(command.sql, contains(r'$1'));
    expect(command.parameters, contains(12));
    expect(query.inspect().reads, ['independent']);
    expect(
      () => query.get(),
      throwsA(
        isA<values.OrmException>().having(
          (e) => e.code,
          'code',
          'QUERY.UNBOUND',
        ),
      ),
    );
  });

  test(
    'physical library dependencies follow the public layer boundaries',
    () async {
      final root = Directory.current.absolute.path;
      final contexts = AnalysisContextCollection(includedPaths: [root]);
      try {
        Future<LibraryElement> resolve(String entry) async {
          final path = '$root/lib/$entry';
          final result = await contexts
              .contextFor(path)
              .currentSession
              .getResolvedLibrary(path);
          return (result as ResolvedLibraryResult).element;
        }

        String? localName(Uri uri) {
          if (uri.scheme == 'package' && uri.path.startsWith('orm/')) {
            return uri.path.substring(4);
          }
          if (uri.scheme == 'file' &&
              uri.toFilePath().startsWith('$root/lib/')) {
            return uri.toFilePath().substring('$root/lib/'.length);
          }
          return null;
        }

        // Internal imports must obey the same boundaries as public facades.
        // Otherwise importing src/query directly could evade the SQL-layer ban.
        String layer(String name) {
          if (name == 'src/schema/model.dart') return 'schema_model.dart';
          if (name == 'src/schema/declaration.dart') {
            return 'schema.dart';
          }
          for (final (prefix, entry) in [
            ('src/values/', 'values.dart'),
            ('src/driver/', 'driver.dart'),
            ('src/query/', 'sql.dart'),
            ('src/runtime/', 'runtime.dart'),
            ('src/orm/', 'orm.dart'),
            ('src/migrate/', 'migrate.dart'),
            ('src/generate/', 'generate.dart'),
            ('src/cli/', 'cli.dart'),
            ('src/sqlite/', 'drivers/sqlite.dart'),
            ('src/postgres/', 'drivers/postgres.dart'),
            ('src/mysql/', 'drivers/mysql.dart'),
          ]) {
            if (name.startsWith(prefix)) return entry;
          }
          return name;
        }

        Set<Uri> dependencies(LibraryElement entry) {
          final visited = <Uri>{};
          void visit(LibraryElement library) {
            if (!visited.add(library.uri) || library.uri.scheme == 'dart') {
              return;
            }
            for (final dependency in [
              ...library.exportedLibraries,
              for (final fragment in library.fragments)
                ...fragment.importedLibraries,
            ]) {
              visit(dependency);
            }
          }

          visit(entry);
          return visited;
        }

        const forbidden = <String, Set<String>>{
          'values.dart': {
            'driver.dart',
            'schema_model.dart',
            'schema.dart',
            'sql.dart',
            'runtime.dart',
            'orm.dart',
            'migrate.dart',
            'generate.dart',
          },
          'driver.dart': {
            'schema_model.dart',
            'schema.dart',
            'sql.dart',
            'runtime.dart',
            'orm.dart',
            'migrate.dart',
            'generate.dart',
          },
          'schema_model.dart': {
            'schema.dart',
            'sql.dart',
            'runtime.dart',
            'orm.dart',
            'migrate.dart',
            'generate.dart',
          },
          'schema.dart': {
            'sql.dart',
            'runtime.dart',
            'orm.dart',
            'migrate.dart',
            'generate.dart',
          },
          'sql.dart': {
            'runtime.dart',
            'orm.dart',
            'migrate.dart',
            'generate.dart',
          },
          'runtime.dart': {
            'schema_model.dart',
            'schema.dart',
            'sql.dart',
            'orm.dart',
            'migrate.dart',
            'generate.dart',
          },
          'migrate.dart': {
            'schema.dart',
            'sql.dart',
            'orm.dart',
            'generate.dart',
          },
          'drivers/sqlite.dart': {
            'schema_model.dart',
            'schema.dart',
            'sql.dart',
            'runtime.dart',
            'orm.dart',
            'migrate.dart',
            'generate.dart',
          },
          'drivers/postgres.dart': {
            'schema_model.dart',
            'schema.dart',
            'sql.dart',
            'runtime.dart',
            'orm.dart',
            'migrate.dart',
            'generate.dart',
          },
          'drivers/mysql.dart': {
            'schema_model.dart',
            'schema.dart',
            'sql.dart',
            'runtime.dart',
            'orm.dart',
            'migrate.dart',
            'generate.dart',
          },
          'drivers/mariadb.dart': {
            'schema_model.dart',
            'schema.dart',
            'sql.dart',
            'runtime.dart',
            'orm.dart',
            'migrate.dart',
            'generate.dart',
          },
        };
        for (final entry in forbidden.entries) {
          final closure = dependencies(await resolve(entry.key));
          final local = closure
              .map(localName)
              .whereType<String>()
              .map(layer)
              .toSet();
          expect(
            local.intersection(entry.value),
            isEmpty,
            reason: '${entry.key} imports a higher layer',
          );
          for (final dependency in closure) {
            expect(
              dependency.toString(),
              isNot(startsWith('package:analyzer/')),
              reason: '${entry.key} imports the generator',
            );
            expect(
              dependency.toString(),
              isNot(startsWith('package:build/')),
              reason: '${entry.key} imports build tooling',
            );
          }
          if (!entry.key.startsWith('drivers/')) {
            expect(
              closure.map((uri) => uri.toString()),
              isNot(contains('dart:io')),
              reason: '${entry.key} should be platform independent',
            );
          }
        }
      } finally {
        await contexts.dispose();
      }
    },
  );
}

Iterable<File> _dartFiles(Directory directory) sync* {
  for (final entry in directory.listSync(followLinks: false)) {
    if (entry is File && entry.path.endsWith('.dart')) {
      yield entry;
    } else if (entry is Directory) {
      final name = entry.path.split(Platform.pathSeparator).last;
      if (name != 'build' && !name.startsWith('.')) {
        yield* _dartFiles(entry);
      }
    }
  }
}

final _id = schema.Column('id', values.Codecs.integer);
final _schema = schema.TableSchema(
  'independent',
  columns: [_id],
  primaryKey: ['id'],
);
final _table = sql.Table<int, _Fields>(_schema, _Fields.new, (row) => row.id);

final class _Fields extends sql.Fields {
  _Fields(super.table);
  late final id = column(_id);
}

final class _RawDriver implements raw.Driver<raw.Sqlite> {
  @override
  raw.Capabilities get capabilities => const raw.Capabilities(
    dialect: raw.SqlDialect.sqlite,
    maxParameters: 999,
  );
  @override
  Future<R> run<R>(Future<R> Function(raw.SqlConnection) action) =>
      action(_RawConnection());
  @override
  Future<void> close() async {}
}

final class _RawConnection implements raw.SqlConnection {
  @override
  bool get transactionActive => false;
  @override
  Future<raw.SqlResult> execute(
    raw.SqlCommand command, {
    raw.ExecutionOptions options = const raw.ExecutionOptions(),
  }) async => raw.SqlResult([command.parameters], columns: ['value']);
  @override
  Future<raw.SqlCursor> openCursor(
    raw.SqlCommand command, {
    raw.ExecutionOptions options = const raw.ExecutionOptions(),
  }) => throw UnsupportedError('No cursor needed for this protocol test.');
  @override
  Future<void> invalidate() async {}
}
