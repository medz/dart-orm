import '../../driver.dart';

typedef OpenedSqlite = ({
  SqlConnection connection,
  Capabilities capabilities,
  int version,
  Future<void> Function() close,
});
