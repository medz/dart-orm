@Tags(['sqlite'])
library;

import 'dart:io';

import 'package:test/test.dart';

import '../tool/src/build_fixture.dart';

void main() {
  test('fresh generated write entrypoints preserve field names across libraries and AOT', () async {
    final fixture = await BuildFixture.create(ormPath: Directory.current.path);
    try {
      await fixture.write('lib/schema.dart', r'''
import 'dart:typed_data';
import 'package:orm/schema.dart';
int samples = 0;
int next() => ++samples;
int byteSamples = 0;
final defaultBytes = Uint8List.fromList([10, 11]);
Uint8List nextBytes() { byteSamples++; return defaultBytes; }
@Model(table: 'blobs')
final class BlobRow({
  @Id(generated: true) required final int id,
  @ClientDefault(nextBytes) required final Uint8List payload,
});
@Model(table: 'notes')
final class Note({
  @Id(generated: true) required final int id,
  required final String title,
  required final String? options,
  required final String? plan,
  required final String? patch,
  required final String? call,
  @ClientDefault(next) required final int stamp,
});
''');
      await fixture.write('lib/change.dart', r'''
import 'package:orm/driver.dart';
import 'package:orm/orm.dart';
import 'schema.orm.dart';
NotePatch edit(String title) => notePatch.overlay([
  notePatch(title: title, options: null),
  notePatch(plan: 'plan field', patch: 'patch field', call: 'call field'),
]);
Future<int> rename(Database<Backend> db, int id, NotePatch input) =>
    db.note.byId(id).update(input);
Future<int> clear(Database<Backend> db, int id) {
  final Future<int> Function({String? options}) patch = db.note.byId(id).patch.call;
  return patch(options: null);
}
''');
      await fixture.write('bin/lifecycle.dart', r'''
import 'dart:typed_data';
import 'package:orm/driver.dart';
import 'package:orm/orm.dart';
import 'package:orm/sql.dart';
import 'package:orm/sqlite.dart';
import 'package:orm/values.dart';
import 'package:orm_build_fixture/schema.dart' show samples;
import 'package:orm_build_fixture/schema.dart' as source;
import '../lib/schema.orm.dart';
import '../lib/change.dart';
void check(bool value, String label) { if (!value) throw StateError(label); }
Future<void> main() async {
  final db = Database.fromSql(await sqlite(const SqliteOptions.memory()));
  try {
    await db.sql.raw(Sql('CREATE TABLE notes (id INTEGER PRIMARY KEY, title TEXT NOT NULL, options TEXT, plan TEXT, patch TEXT, call TEXT, stamp INTEGER NOT NULL)'));
    final row = await db.note.create(title: 'First', options: 'keep');
    check(await db.note.byId(row.id).patch(title: 'Named', options: 'named option') == 1, 'named immediate');
    check(await clear(db, row.id) == 1, 'typed tear-off');
    check(await rename(db, row.id, edit('Composed')) == 1, 'cross-library input');
    final changed = await db.note.byId(row.id).single();
    check(changed.title == 'Composed' && changed.options == null && changed.plan == 'plan field' && changed.patch == 'patch field' && changed.call == 'call field', 'names and overlay');
    final future = db.note.insert(noteInsert(title: 'Second'));
    await future; await future;
    check(await db.note.count() == 2, 'Future does not replay');
    final before = samples;
    final insert = db.note.plan.insert(noteInsert(title: 'Planned'));
    check(samples == before, 'inert plan');
    try {
      await insert.returning().single(options: ExecutionOptions(cancellation: CancellationToken()..cancel()));
      throw StateError('cancellation ignored');
    } on OrmException catch (e) { check(e.code == 'OPERATION.CANCELLED', 'cancel error'); }
    check(samples == before, 'no default on cancel');
    final title = await db.note.byId(row.id).plan.update(notePatch(title: 'Returned')).returning().select((n) => n.title).single();
    check(title == 'Returned', 'advanced returning');
    final prepared = insert.prepare();
    await prepared.execute(); await prepared.execute();
    check(samples == before + 1, 'prepared default frozen');
    check(await db.note.byId(row.id).delete() == 1, 'immediate delete');
    await checkBytes(db);
    print('generated-write-lifecycle-ok');
  } finally { await db.close(); }
}

Future<void> checkBytes(Database<Sqlite> db) async {
  await db.sql.raw(Sql('CREATE TABLE blobs (id INTEGER PRIMARY KEY, payload BLOB NOT NULL)'));
  Future<void> stored(List<List<int>> expected, String label) async {
    final rows = await db.blobRow.orderBy((b) => [b.id.asc()]).get();
    check('${rows.map((r) => r.payload.toList()).toList()}' == '$expected', label);
    await db.blobRow.delete();
  }
  void readOnly(void Function() change) {
    try { change(); } on UnsupportedError { return; }
    throw StateError('compiled byte storage is writable');
  }

  final bytes = Uint8List.fromList([1, 2]);
  final plan = db.blobRow.plan.insert(blobRowInsert(payload: bytes));
  bytes[0] = 3;
  final prepared = plan.prepare();
  final captured = prepared.compile().parameters.single as Uint8List;
  bytes[0] = 4;
  check(captured[0] == 3, 'prepare owns literal bytes');
  check(identical(prepared.compile().parameters.single, captured), 'compilation reuses captured bytes');
  readOnly(() => captured[0] = 99);
  readOnly(() => captured.buffer.asUint8List()[0] = 99);
  readOnly(() => captured.buffer.asByteData().setUint8(0, 99));
  await prepared.execute();
  bytes[0] = 5;
  await prepared.execute();
  await stored([[3, 2], [3, 2]], 'single prepared replay');
  await plan.execute();
  bytes[0] = 6;
  await plan.execute();
  await stored([[5, 2], [6, 2]], 'plan literals prepare at each terminal');

  var expressions = 0;
  final expressionPlan = db.blobRow.plan.insert(blobRowInsert.values(
    payload: .expression((_) { expressions++; return value(bytes, Codecs.bytes); }),
  ));
  check(expressions == 0, 'expression plan is inert');
  final expressionPrepared = expressionPlan.prepare();
  bytes[0] = 7;
  await expressionPrepared.execute();
  await expressionPrepared.execute();
  check(expressions == 1, 'prepared expression only evaluated once');
  await expressionPlan.execute();
  check(expressions == 2, 'plan terminal evaluates expression again');
  await stored([[6, 2], [6, 2], [7, 2]], 'expression bytes freeze');

  final defaultPlan = db.blobRow.plan.insert(blobRowInsert());
  check(source.byteSamples == 0, 'default plan is inert');
  final defaultPrepared = defaultPlan.prepare();
  source.defaultBytes[0] = 12;
  await defaultPrepared.execute();
  await defaultPrepared.execute();
  check(source.byteSamples == 1, 'prepared default only evaluated once');
  await defaultPlan.execute();
  check(source.byteSamples == 2, 'plan terminal evaluates default again');
  await stored([[10, 11], [10, 11], [12, 11]], 'default bytes freeze');

  final batchPlan = db.blobRow.plan.insertMany([
    blobRowInsert(payload: bytes),
    blobRowInsert.values(payload: .expression((_) => value(bytes, Codecs.bytes))),
    blobRowInsert(),
  ]);
  bytes[0] = 20;
  final batch = batchPlan.prepare();
  bytes[0] = 21;
  source.defaultBytes[0] = 13;
  final batchBytes = batch.compile().single.parameters.whereType<Uint8List>().toList();
  check('$batchBytes' == '[[20, 2], [20, 2], [12, 11]]', 'batch parameters captured');
  for (final payload in batchBytes) { readOnly(() => payload[0] = 99); }
  await batch.execute();
  await batch.execute();
  await stored([[20, 2], [20, 2], [12, 11], [20, 2], [20, 2], [12, 11]], 'batch prepared replay');
  await batchPlan.execute();
  await stored([[21, 2], [21, 2], [13, 11]], 'batch plan prepares fresh');

  final row = await db.blobRow.create(payload: bytes);
  final update = db.blobRow.byId(row.id).plan.update(blobRowPatch(payload: bytes)).prepare();
  bytes[0] = 22;
  await update.execute();
  await update.execute();
  await stored([[21, 2]], 'update prepared replay');

  final boundExpression = value(bytes, Codecs.bytes);
  bytes[0] = 23;
  final bound = db.blobRow.plan.insert(blobRowInsert.values(payload: .expression((_) => boundExpression))).prepare();
  await bound.execute();
  await stored([[22, 2]], 'prebuilt expression owns bytes when bound');

  final raw = Sql('SELECT :bytes', parameters: {'bytes': SqlValue(bytes, Codecs.bytes)});
  final rawBytes = raw.compile(db.capabilities).parameters.single as Uint8List;
  bytes[0] = 24;
  check(rawBytes[0] == 23, 'raw value retains its own snapshot');
  check(identical(raw.compile(db.capabilities).parameters.single, rawBytes), 'raw compilation reuses its captured bytes');
  readOnly(() => rawBytes[0] = 99);
}
''');
      await fixture.run(['run', 'build_runner', 'build']);
      await fixture.run(['analyze']);
      expect(
        (await fixture.run(['run', 'orm_build_fixture:lifecycle'])).output,
        contains('generated-write-lifecycle-ok'),
      );
      await fixture.run([
        'build',
        'cli',
        '--target',
        'bin/lifecycle.dart',
        '--output',
        'deployment',
      ]);
      final aot = await Process.run(
        '${fixture.directory.path}/deployment/bundle/bin/lifecycle',
        [],
        workingDirectory: fixture.directory.path,
      );
      expect(aot.exitCode, 0, reason: '${aot.stdout}\n${aot.stderr}');
      expect(aot.stdout, contains('generated-write-lifecycle-ok'));
    } finally {
      await fixture.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
