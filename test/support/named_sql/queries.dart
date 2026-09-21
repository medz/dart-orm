import 'package:orm/schema.dart';

final authorStats = sqlQuery(
  result: (author: text(), postCount: integer(), points: integer()),
  parameters: (minimum: integer(), author: text().nullable()),
  sqlite: 'stats.sqlite.sql',
  postgres: 'stats.postgres.sql',
);
final echo = sqlQuery(
  result: (value: text(), at: dateTime(), amount: decimal(), day: date()),
  parameters: (value: text(), at: dateTime(), amount: decimal(), day: date()),
  sqlite: 'echo.sql',
  postgres: 'echo.sql',
);
final constant = sqlQuery(
  result: (n: integer()),
  sqlite: 'constant.sql',
  postgres: 'constant.sql',
);
final postgresOnly = sqlQuery(result: (n: integer()), postgres: 'constant.sql');
