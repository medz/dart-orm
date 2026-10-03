@Tags(['sqlite'])
library;

import 'dart:io';

import 'package:test/test.dart';

import '../tool/src/build_fixture.dart';

void main() {
  test(
    'generated projection declarations work in independent libraries and AOT',
    () async {
      final fixture = await BuildFixture.create(
        ormPath: Directory.current.path,
      );
      try {
        await fixture.write('build.yaml', '''
targets:
  \$default:
    builders:
      orm:orm:
        enabled: true
        generate_for:
${_sources.keys.map((name) => '          - lib/$name.dart').join('\n')}
''');
        await fixture.write('analysis_options.yaml', '''
analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
''');
        for (final entry in _sources.entries) {
          await fixture.write('lib/${entry.key}.dart', entry.value);
        }
        await fixture.write('bin/projections.dart', _consumer);
        await fixture.run(['run', 'build_runner', 'build']);
        await fixture.run(['analyze']);
        expect(
          (await fixture.run(['run', 'orm_build_fixture:projections'])).output,
          contains('generated-projection-declarations-ok'),
        );
        await fixture.run([
          'build',
          'cli',
          '--target',
          'bin/projections.dart',
          '--output',
          'deployment',
        ]);
        final aot = await Process.run(
          '${fixture.directory.path}/deployment/bundle/bin/projections',
          [],
          workingDirectory: fixture.directory.path,
        );
        expect(aot.exitCode, 0, reason: '${aot.stdout}\n${aot.stderr}');
        expect(aot.stdout, contains('generated-projection-declarations-ok'));
      } finally {
        await fixture.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

const _sources = {
  'schema': '''
import 'package:orm/schema.dart';
@Model(table: 'notes')
final class Note({
  @Id() required final int id,
  required final int fields,
  required final String earlier,
  required final String later,
  required final String layers,
});
''',
  'record': '''
import 'package:orm/schema.dart';
/// A named record projection.
@Projection()
typedef Card = ({int id, String label});
''',
  'factory': '''
import 'package:orm/schema.dart';
/** A projection decoded through its public factory. */
@Projection()
abstract class Card {
  factory Card({required int id, required String label}) = _Card;
  int get id;
  String get label;
}
final class _Card implements Card {
  const _Card({required this.id, required this.label});
  @override final int id;
  @override final String label;
}
''',
  'wide': '''
import 'package:orm/schema.dart';
@Projection()
final class Card({
  required final int f1, required final int f2,
  required final int f3, required final int f4,
  required final int f5, required final int f6,
  required final int f7, required final int f8,
});
''',
  'names': '''
import 'package:orm/schema.dart';
@Projection()
final class Card({
  required final String fields, required final String result,
  required final String values, required final String left,
  required final String right, required final String v0,
  required final String orm_projection,
});
''',
  'type_name': '''
import 'package:orm/schema.dart' as schema;
@schema.Projection()
final class Projection({required final int id});
''',
};

const _consumer = r'''
import 'package:orm/orm.dart';
import 'package:orm/sql.dart';
import 'package:orm/sqlite.dart';
import '../lib/schema.orm.dart';
import '../lib/record.orm.dart' as rec;
import '../lib/factory.orm.dart' as fac;
import '../lib/wide.orm.dart' as wide;
import '../lib/names.orm.dart' as names;
import '../lib/type_name.orm.dart' as named;
import '../lib/record.snapshot.dart' as rec_snapshot;
import '../lib/factory.snapshot.dart' as fac_snapshot;
import '../lib/wide.snapshot.dart' as wide_snapshot;
import '../lib/names.snapshot.dart' as names_snapshot;
import '../lib/type_name.snapshot.dart' as named_snapshot;

void check(bool value, String label) { if (!value) throw StateError(label); }
Future<void> main() async {
  for (final snapshot in [rec_snapshot.schema, fac_snapshot.schema, wide_snapshot.schema, names_snapshot.schema, named_snapshot.schema]) {
    check(snapshot.tables.isEmpty, 'projection-only library has no physical tables');
  }
  final db = Database.fromSql(await sqlite(const SqliteOptions.memory()));
  try {
    await db.sql.raw(Sql('CREATE TABLE notes (id INTEGER PRIMARY KEY, fields INTEGER NOT NULL, earlier TEXT NOT NULL, later TEXT NOT NULL, layers TEXT NOT NULL)'));
    await db.note.insertMany([
      noteInsert(id: 1, fields: 11, earlier: 'first', later: 'after', layers: 'one'),
      noteInsert(id: 2, fields: 22, earlier: 'second', later: 'last', layers: 'two'),
    ]);
    final record = db.note.select((n) => rec.card.sql(id: n.id, label: n.earlier));
    final first = await record.asCte('cards').where((c) => c.id.eq(.value(1))).single();
    check(first == (id: 1, label: 'first'), 'named record CTE');
    check((await record.unionAll(record).get()).length == 4, 'named record set operation');
    final recordOrdinary = await db.note.byId(2).select((n) => rec.card(id: n.id, label: n.earlier)).single();
    check(recordOrdinary == (id: 2, label: 'second'), 'named record selection');

    final factory = db.note.select((n) => fac.card.sql(id: n.id, label: n.earlier));
    final second = await factory.asCte('factory_cards').where((c) => c.id.eq(.value(2))).single();
    check(second.id == 2 && second.label == 'second', 'abstract factory CTE');
    final ordinary = await db.note.byId(1).select((n) => fac.card(id: n.id, label: n.earlier)).single();
    check(ordinary.id == 1 && ordinary.label == 'first', 'abstract factory selection');

    final repeated = db.note.select((n) => wide.card.sql(f1: n.id, f2: n.id, f3: n.id, f4: n.id, f5: n.id, f6: n.id, f7: n.id, f8: n.id));
    final eight = await repeated.asCte('wide_cards').where((c) => c.f8.eq(.value(2))).single();
    check([eight.f1, eight.f2, eight.f3, eight.f4, eight.f5, eight.f6, eight.f7, eight.f8].every((v) => v == 2), 'wide projection retains repeated expressions in every slot');

    final namedFields = db.note.byId(1).select((n) => names.card.sql(fields: n.earlier, result: n.later, values: n.layers, left: n.earlier, right: n.later, v0: n.layers, orm_projection: n.earlier));
    final fields = await namedFields.asCte('named_cards').where((c) => c.fields.eq(.value('first'))).single();
    check(fields.fields == 'first' && fields.result == 'after' && fields.values == 'one' && fields.left == 'first' && fields.right == 'after' && fields.v0 == 'one' && fields.orm_projection == 'first', 'projection field names remain distinct');
    final dto = await db.note.byId(1).select((n) => named.projection.sql(id: n.id)).asCte('type_name').single();
    check(dto.id == 1, 'DTO named Projection');
    await db.note.byId(1).patch(fields: 33, earlier: 'changed', later: 'end', layers: 'three');
    final model = await db.note.byId(1).single();
    check(model.fields == 33 && model.earlier == 'changed' && model.later == 'end' && model.layers == 'three', 'model field names survive generation and writes');
    print('generated-projection-declarations-ok');
  } finally { await db.close(); }
}
''';
