import 'package:orm/sqlite.dart';

import 'queries.queries.dart';

Future<void> main() async {
  final db = await sqlite(const SqliteOptions.memory());
  try {
    await db.execute(
      SqlCommand('CREATE TABLE posts (author TEXT, points INTEGER)'),
    );
    await db.execute(
      SqlCommand("INSERT INTO posts VALUES ('a', 1), ('a', 3), ('b', 7)"),
    );
    final rows = await db
        .authorStats(minimum: 0)
        .orderBy((r) => [r.author.asc()])
        .stream()
        .toList();
    if (rows.length != 2 || rows.first.points != 4 || rows.last.author != 'b') {
      throw StateError('Named SQL stream or parameters differ');
    }
    final expected = (
      value: "' :value ; --",
      at: DateTime.utc(2024, 1, 1, 0, 0, 0, 0, 1),
      amount: Decimal.parse('12345678901234567890.00000001'),
      day: LocalDate.parse('0001-01-01 BC'),
    );
    final actual = await db
        .echo(
          value: expected.value,
          at: expected.at,
          amount: expected.amount,
          day: expected.day,
        )
        .single();
    if ((
          value: actual.value,
          at: actual.at,
          amount: actual.amount,
          day: actual.day,
        ) !=
        expected) {
      throw StateError('Named SQL codecs differ');
    }
    await db.transaction((tx) async {
      await tx.execute(SqlCommand("INSERT INTO posts VALUES ('a', 2)"));
      if ((await tx.authorStats(minimum: 0, author: 'a').single()).points !=
          6) {
        throw StateError('Named SQL escaped its transaction');
      }
    });
    print(
      'Named SQL parameters, rows, native codecs, streaming and transactions verified.',
    );
  } finally {
    await db.close();
  }
}
