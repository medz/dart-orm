import 'package:orm/schema.dart';

typedef AuthorStats = ({String author, int postCount, int points});
final authorStats = sqlQuery<AuthorStats, ({int minimum, String? author})>(
  sqlite: 'stats.sqlite.sql',
  postgres: 'stats.postgres.sql',
);

typedef Echo = ({String value, DateTime at, Decimal amount, LocalDate day});
final echo = sqlQuery<Echo, Echo>(sqlite: 'echo.sql', postgres: 'echo.sql');

typedef Constant = ({int n});
final constant = sqlQuery<Constant, ()>(
  sqlite: 'constant.sql',
  postgres: 'constant.sql',
);
final postgresOnly = sqlQuery<Constant, ()>(postgres: 'constant.sql');
