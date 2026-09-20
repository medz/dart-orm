import '../../driver.dart';

final class OpenSqliteCursor(final SqlCommand command) {}

final class FetchSqliteCursor(final int cursor, final int count) {}

final class CloseSqliteCursor(final int cursor) {}
