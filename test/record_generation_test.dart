import 'dart:io';

import 'package:orm/generate.dart';
import 'package:test/test.dart';

void main() {
  late Directory fixtures;
  setUpAll(() async {
    fixtures = await Directory('.dart_tool/orm-record-tests')
        .create(recursive: true);
  });
  tearDownAll(() => fixtures.delete(recursive: true));

  Future<GeneratedSchema> generate(String name, String source) async {
    final file = File('${fixtures.path}/$name.dart');
    await file.writeAsString("import 'package:orm/schema.dart';\n$source");
    return generateSchema(file.path);
  }

  test('one Record definition generates nominal rows, queries and independent snapshots', () async {
    final generated = await generateSchema('example/company/schema.dart');
    expect(
      generated.dart,
      await File('example/company/schema.orm.dart').readAsString(),
    );
    expect(
      generated.snapshotDart,
      await File('example/company/schema.snapshot.dart').readAsString(),
    );
    expect(generated.dart, contains('final class Employee('));
    expect(
      generated.dart,
      contains('Relation<Employee, EmployeeFields> get manager'),
    );
    expect(generated.dart, contains('required final int? managerId'));
    expect(generated.dart, contains('models.ProjectStatus'));
    expect(generated.snapshotDart, isNot(contains('models.')));
    expect(generated.snapshotDart, isNot(contains('schema.dart')));
  });

  test(
    'const SQL names and typed defaults preserve quoting and physical identity',
    () async {
      const common = '''
const tableName = 'people';
const columnName = 'contact_email';
const defaultName = "O'Brien";
''';
      final before = await generate('names_before', '''
$common
final Model person = model(tableName, (
 id: identity(), email: text(name: columnName, defaultValue: defaultName),
));
''');
      final after = await generate('names_after', '''
$common
final Model customer = model(tableName, (
 id: identity(), address: text(name: columnName, defaultValue: defaultName),
));
''');
      expect(after.snapshotDart, before.snapshotDart);
      expect(after.snapshotDart, contains("O''Brien"));
    },
  );

  test(
    'generation references client factories without executing them',
    () async {
      final generated = await generate('factory', '''
int forbidden() => throw StateError('generation executed application code');
final Model sample = model('sample', (id: identity(), value: integer(clientDefault: forbidden)));
''');
      expect(generated.dart, contains('clientDefault: models.forbidden'));
      expect(generated.snapshotDart, isNot(contains('forbidden')));
    },
  );

  test('same field shape keeps distinct model and table identities', () async {
    final result = await generate('identity', '''
final primaryUser = model('primary_users', (id: identity(), name: text()));
final archivedUser = model('archived_users', (id: identity(), name: text()));
''');
    expect(result.dart, contains('final class PrimaryUser('));
    expect(result.dart, contains('final class ArchivedUser('));
    expect(result.snapshot.tables.map((t) => t.name), [
      'primary_users',
      'archived_users',
    ]);
  });

  test('composite, alternate unique and read-only relationships preserve key order', () async {
    final result = await generate('composite', '''
final Model team = model('teams', (tenant: integer(), code: text(), slug: text(unique: true)),
 primaryKey: (t) => (t.tenant, t.code),
 relations: (t) => (members: referencedBy(() => member, on: (tenant: t.tenant, teamCode: t.code)),));
final Model member = model('members', (id: identity(), tenant: integer(), teamCode: text(), slug: text()),
 relations: (m) => (
   team: references((m.tenant, m.teamCode), () => team, onDelete: .cascade),
   bySlug: references((slug: m.slug), () => team),
   byCode: references((code: m.teamCode), () => team, constraint: false),
 ));
''');
    final foreignKeys = result.snapshot.tables.last.foreignKeys;
    expect(foreignKeys.length, 2);
    expect(foreignKeys.first.columns, ['tenant', 'team_code']);
    expect(foreignKeys.first.targetColumns, ['tenant', 'code']);
    expect(result.dart, contains('get byCode'));
  });

  test(
    'enum labels and defaults share one encoding without annotations',
    () async {
      final result = await generate('enums', '''
enum Status { waiting, done }
final Model job = model('jobs', (
 id: identity(),
 status: enumeration(Status.values, labels: {Status.waiting: 'pending', Status.done: 'complete'}, defaultValue: Status.waiting),
));
''');
      expect(result.dart, contains('models.Status.waiting: "pending"'));
      expect(result.snapshotDart, contains("'pending'"));
    },
  );

  test(
    'prefixed model calls preserve inferred fields and self references',
    () async {
      final generated = await generate('prefixed', '''
import 'package:orm/schema.dart' as schema;
final Model employee = schema.model('employees', (
  id: identity(), managerId: integer().nullable(),
), relations: (e) => (
  manager: references(e.managerId, () => employee),
  reports: referencedBy(() => employee),
), indexes: (e) => [index(e.managerId, name: 'employees_manager')]);
''');
      expect(generated.snapshot.tables.single.foreignKeys.single.columns, [
        'manager_id',
      ]);
      expect(generated.dart, contains('get manager =>'));
      expect(generated.dart, contains('get reports =>'));
    },
  );

  test('barrel exports follow mutual model references and leave unrelated imports out', () async {
    final split = await Directory('${fixtures.path}/split').create();
    await File('${split.path}/department.dart').writeAsString('''
import 'package:orm/schema.dart';
import 'employee.dart';
final department = model('departments', (
  id: identity(), headId: integer().nullable(),
), relations: (d) => (head: references(d.headId, () => employee), employees: referencedBy(() => employee)));
final unused = model('unused', (invalid: 'not a column',));
''');
    await File('${split.path}/employee.dart').writeAsString('''
import 'package:orm/schema.dart';
import 'department.dart';
enum Role { member, manager }
final Model employee = model('employees', (
  id: identity(), role: enumeration(Role.values),
  departmentId: integer(),
), relations: (e) => (department: references(e.departmentId, () => department),));
''');
    final root = File('${split.path}/schema.dart');
    await root.writeAsString("export 'employee.dart' show employee;\n");
    await writeGeneratedSchema(root.path);
    final generated = await generateSchema(root.path);
    expect(generated.snapshot.tables.map((t) => t.name).toSet(), {
      'employees',
      'departments',
    });
    expect(generated.dart, contains('show Role'));
    final analysis = await Process.run(Platform.resolvedExecutable, [
      'analyze',
      '${split.path}/schema.orm.dart',
    ]);
    expect(
      analysis.exitCode,
      0,
      reason: '${analysis.stdout}\n${analysis.stderr}',
    );
  });

  for (final local in [false, true]) {
    test(
      'exported model renames preserve snapshot identity (local: $local)',
      () async {
        final split = await Directory('${fixtures.path}/rename_$local')
            .create();
        final first = File('${split.path}/first.dart');
        Future<void> rename(String name) => first.writeAsString('''
import 'package:orm/schema.dart';
final $name = model('first_table', (id: identity(),));
''');
        await rename('a');
        await File('${split.path}/second.dart').writeAsString('''
import 'package:orm/schema.dart';
final m = model('second_table', (id: identity(),));
''');
        final root = File('${split.path}/schema.dart');
        await root.writeAsString('''
${local ? "import 'package:orm/schema.dart';" : ''}
export 'first.dart';
export 'second.dart';
${local ? "final root = model('root_table', (id: identity(),));" : ''}
''');
        final before = await generateSchema(root.path);
        await rename('z');
        final after = await generateSchema(root.path);
        expect(after.snapshotDart, before.snapshotDart);
        expect(after.snapshot.checksum, before.snapshot.checksum);
        expect(after.snapshot.tables.map((table) => table.name), [
          if (local) 'root_table',
          'first_table',
          'second_table',
        ]);
      },
    );
  }

  test(
    'ordinary field names cannot shadow generated callback variables',
    () async {
      await generate(
        'callback_names',
        "final Model entry = model('entries', (row: integer(), row2: text(), value: text(), models: text(), createRow: text(), update: text(), where: integer()), primaryKey: (e) => (e.row, e.where));",
      );
      await writeGeneratedSchema('${fixtures.path}/callback_names.dart');
      final analysis = await Process.run(Platform.resolvedExecutable, [
        'analyze',
        '${fixtures.path}/callback_names.orm.dart',
      ]);
      expect(
        analysis.exitCode,
        0,
        reason: '${analysis.stdout}\n${analysis.stderr}',
      );
    },
  );

  test('all storage families, domain identity, precision, computed and CHECK compile', () async {
    await generate('storage', '''
extension type const EntryId(int value) {
  static const codec = Codec<EntryId>.integer(decode, encode);
  static EntryId decode(Object? value) => EntryId(value as int);
  static int encode(EntryId value) => value.value;
}
enum Status { pending, done }
const statusDefault = Status.pending;
const deleteAction = ReferentialAction.setNull;
final Model entry = model('entries', (
  id: custom(EntryId.codec).identity(),
  parentId: custom(EntryId.codec).nullable(),
  price: integer(bits: 32), quantity: integer(), total: integer().computed('price * quantity'),
  amount: decimal(precision: 12, scale: 2), ratio: real(defaultValue: 1.5),
  big: bigInteger(), day: date(), clock: time(precision: 3),
  local: localDateTime(precision: 3).nullable(), instant: dateTime(precision: 3),
  payload: bytes(), document: json().nullable(),
  status: enumeration(Status.values, defaultValue: statusDefault),
), relations: (e) => (parent: references(e.parentId, () => entry, onDelete: deleteAction),), checks: [check('price >= 0', name: 'positive_price')]);
''');
    await writeGeneratedSchema('${fixtures.path}/storage.dart');
    final result = await generateSchema('${fixtures.path}/storage.dart');
    final table = result.snapshot.tables.single;
    expect(table.columns.first.generated, true);
    expect(
      table.columns.map((c) => c.codec.sqlType).toSet(),
      containsAll([
        'integer',
        'decimal',
        'real',
        'bigint',
        'date',
        'time',
        'local_datetime',
        'instant',
        'blob',
        'json',
        'text',
      ]),
    );
    expect(table.columns.firstWhere((c) => c.name == 'price').integerBits, 32);
    expect(
      table.columns.firstWhere((c) => c.name == 'amount').decimalPrecision,
      12,
    );
    expect(
      table.columns.firstWhere((c) => c.name == 'clock').temporalPrecision,
      3,
    );
    expect(table.checks.single.name, 'positive_price');
    expect(table.foreignKeys.single.onDelete, 'SET NULL');
    expect(result.snapshotDart, contains("'pending'"));
    final analysis = await Process.run(Platform.resolvedExecutable, [
      'analyze',
      '${fixtures.path}/storage.orm.dart',
    ]);
    expect(
      analysis.exitCode,
      0,
      reason: '${analysis.stdout}\n${analysis.stderr}',
    );
  });

  test('distinct imported domain types with equal names do not create ambiguous exports', () async {
    for (final name in ['first', 'second']) {
      await File('${fixtures.path}/$name.dart').writeAsString('''
import 'package:orm/schema.dart';
final class Email(final String value);
const codec = Codec<Email>.text(decode, encode);
Email decode(Object? value) => Email(value as String);
String encode(Email value) => value.value;
''');
    }
    await generate('domains', '''
import 'first.dart' as first;
import 'second.dart' as second;
final Model contact = model('contacts', (id: identity(), primary: custom(first.codec), secondary: custom(second.codec)));
''');
    await writeGeneratedSchema('${fixtures.path}/domains.dart');
    final analysis = await Process.run(Platform.resolvedExecutable, [
      'analyze',
      '${fixtures.path}/domains.orm.dart',
    ]);
    expect(
      analysis.exitCode,
      0,
      reason: '${analysis.stdout}\n${analysis.stderr}',
    );
  });

  test(
    'nullable configuration arguments have the same meaning as omission',
    () async {
      final omitted = await generate(
        'omitted_options',
        "final Model person = model('people', (id: identity(), name: text()));",
      );
      final explicit = await generate('null_options', '''
const String? absent = null;
final Model person = model('people', (
  id: identity(name: absent),
  name: text(name: null, defaultValue: null, defaultSql: absent, clientDefault: null),
), indexes: null, primaryKey: null, checks: null, relations: null, uniqueKeys: null);
''');
      expect(explicit.snapshotDart, omitted.snapshotDart);
    },
  );

  test('codec const aliases preserve reference identity; different encoders do not', () async {
    const source = '''
extension type const PersonId(int value) {}
PersonId decode(Object? value) => PersonId(value as int);
int encode(PersonId id) => id.value;
int shifted(PersonId id) => id.value + 1;
const original = Codec<PersonId>.integer(decode, encode);
const alias = original;
const different = Codec<PersonId>.integer(decode, shifted);
final Model person = model('people', (id: custom(original).identity(),));
final Model note = model('notes', (id: identity(), ownerId: custom(alias).nullable()), relations: (n) => (owner: references(n.ownerId, () => person),));
''';
    final result = await generate('codec_alias', source);
    expect(result.snapshot.tables.last.foreignKeys.single.target, 'people');
    await expectLater(
      generate(
        'codec_different',
        source.replaceFirst('custom(alias)', 'custom(different)'),
      ),
      throwsA(
        isA<GenerationException>().having(
          (e) => e.code,
          'code',
          'SCHEMA.REFERENCE',
        ),
      ),
    );
  });

  final invalid = <String, (String, String)>{
    'wrong_identity': (
      "final Model entry = model('entries', (id: text().identity(),));",
      'KEY',
    ),
    'non_column': (
      "final Model person = model('people', (id: identity(), name: 'oops'));",
      'COLUMN',
    ),
    'positional': (
      "final Model person = model('people', (identity(), text()));",
      'FIELDS',
    ),
    'empty': ("final Model person = model('people', ());", 'FIELDS'),
    'empty_check_name': (
      "final entry = model('entries', (id: identity(),), checks: [check('id > 0', name: '')]);",
      'CHECK',
    ),
    'only_computed': (
      "final entry = model('entries', (total: integer().computed('1'),));",
      'COLUMN',
    ),
    'key_nullable': (
      "final Model person = model('people', (id: integer().nullable(),), primaryKey: (p) => p.id);",
      'KEY',
    ),
    'key_duplicate': (
      "final Model person = model('people', (id: integer(),), primaryKey: (p) => (p.id, p.id));",
      'KEY',
    ),
    'key_identity': (
      "final Model person = model('people', (id: identity(),), primaryKey: (p) => p.id);",
      'KEY',
    ),
    'block': (
      "final Model person = model('people', (id: identity(),), indexes: (p) { return [index(p.id, name: 'id')]; });",
      'SELECTOR',
    ),
    'duplicate_column': (
      "final Model person = model('people', (id: integer(name: 'same'), name: text(name: 'same')));",
      'DUPLICATE',
    ),
    'defaults': (
      "final Model person = model('people', (id: identity(), name: text(defaultValue: 'a', defaultSql: \"'b'\")));",
      'DEFAULT',
    ),
    'factory': (
      "ColumnDefinition<int> make() => integer(); final Model person = model('people', (id: make(),));",
      'COLUMN',
    ),
    'nested': ("final models = [model('people', (id: identity(),))];", 'MODEL'),
    'function': (
      "Model make() => model('people', (id: identity(),));",
      'MODEL',
    ),
    'set_null': (
      "final Model person = model('people', (id: identity(), manager: integer()), relations: (p) => (boss: references(p.manager, () => person, onDelete: .setNull),));",
      'REFERENCE',
    ),
    'target_type': (
      "final Model person = model('people', (id: identity(), manager: text()), relations: (p) => (boss: references(p.manager, () => person),));",
      'REFERENCE',
    ),
    'target_no_key': (
      "final Model person = model('people', (id: integer(), manager: integer()), relations: (p) => (boss: references(p.manager, () => person),));",
      'REFERENCE',
    ),
    'relation_collision': (
      "final Model person = model('people', (id: identity(), manager: integer()), relations: (p) => (id: references(p.manager, () => person),));",
      'NAME',
    ),
    'nullable_twice': (
      "final Model person = model('people', (id: integer().nullable().nullable(),));",
      'DUPLICATE',
    ),
    'generated_name': (
      "final Model table = model('tables', (id: identity(),));",
      'MODEL',
    ),
    'enum_labels': (
      "enum Status { a,b } final Model job = model('jobs', (status: enumeration(Status.values, labels: {Status.a: 'x', Status.b: 'x'}),));",
      'ENUM',
    ),
  };
  for (final entry in invalid.entries) {
    test(
      'rejects ${entry.key} with a source location and diagnostic code',
      () async {
        await expectLater(
          generate(entry.key, entry.value.$1),
          throwsA(
            isA<GenerationException>()
                .having((e) => e.code, 'code', 'SCHEMA.${entry.value.$2}')
                .having((e) => e.line, 'line', greaterThan(0))
                .having((e) => e.column, 'column', greaterThan(0))
                .having(
                  (e) => e.source?.path,
                  'source',
                  endsWith('${entry.key}.dart'),
                ),
          ),
        );
      },
    );
  }
}
