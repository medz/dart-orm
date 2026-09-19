import 'package:orm/migrate.dart';
import 'package:orm/sqlite.dart';

import 'alternate.dart' as alt;
import 'schema.orm.dart';
import 'types.dart';

Future<void> main() async {
  final db = await sqlite(const SqliteOptions.memory());
  try {
    await Migrator(
      db.sql,
    ).apply([Migration.create('0001_initial', appSchema, dialect: db.dialect)]);
    final first = await db.people.create(
      email: const Email('aot@example.com'),
      membership: .pending,
      tags: ['AOT', '类型'],
      location: (city: '成都', zone: 8),
      alternate: const alt.Email('other'),
      details: const SqlJson('scalar'),
    );
    if (first.id.value != 1 ||
        first.email.value != 'aot@example.com' ||
        first.membership != Membership.pending ||
        first.tags.last != '类型' ||
        first.location != (city: '成都', zone: 8) ||
        first.details?.value != 'scalar') {
      throw StateError('Custom value decoding failed');
    }
    await db.notes.create(ownerId: first.id, body: 'relation');
    final email = await db.notes
        .select((n) => n.owner.select((p) => p.email).required())
        .single();
    if (email.value != first.email.value) {
      throw StateError('Custom relation failed');
    }
    final token = db.people.cursorToken((p) => [p.id.cursor(first.id)]);
    final second = await db.people.create(
      email: const Email('second@example.com'),
      membership: .active,
      tags: [],
      alternate: const alt.Email('other'),
      details: const SqlJson(null),
    );
    final rows = await db.people
        .seekToken(token, orderBy: (p) => [p.id.asc()])
        .stream(batchSize: 1)
        .toList();
    if (rows.single.id != second.id ||
        rows.single.details == null ||
        rows.single.details!.value != null) {
      throw StateError('Cursor/JSON presence failed');
    }
    print(
      'Native AOT: extension IDs, custom classes, enums, records, relations, JSON and cursors passed.',
    );
  } finally {
    await db.close();
  }
}
