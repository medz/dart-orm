import 'package:orm/migrate.dart';
import 'package:orm/sqlite.dart';

import 'schema.orm.dart';

Future<void> main() async {
  final db = await sqlite(const SqliteOptions.memory());
  try {
    await Migrator(
      db,
    ).apply([Migration.create('0001_initial', appSchema, dialect: db.dialect)]);
    final first = await db.samples.create(
      small: 32767,
      medium: 2147483647,
      large: 9007199254740993,
    );
    await db.samples.create(
      small: 32767,
      medium: 2147483647,
      large: -9007199254740993,
    );
    final sums = await db.samples
        .select((s) => (s.small.sum(), s.medium.sum(), s.large.sum()).row)
        .single();
    if (sums != (65534, 4294967294, 0)) {
      throw StateError('Integer sums were narrowed');
    }
    await db.owners.create(id: 1, sampleId: first.id);
    if (await db.owners
            .select((o) => o.sample.select((s) => s.small).required())
            .single() !=
        32767) {
      throw StateError('Relation lost integer width');
    }
    var rejected = false;
    try {
      await db.samples.create(small: 32768, medium: 0, large: 0);
    } on SqlFailure {
      rejected = true;
    }
    if (!rejected) throw StateError('Narrow integer accepted overflow');
    final verification = await verifySchema(db, SchemaSnapshot(appSchema));
    if (!verification.matches) {
      throw StateError(verification.differences.join('\n'));
    }
    print(
      'Native AOT: signed integer widths, wider aggregate results, relations, overflow rejection and catalog verification passed.',
    );
  } finally {
    await db.close();
  }
}
