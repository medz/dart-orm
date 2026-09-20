import 'package:sqlite3/common.dart' as native;

import '../../driver.dart';

import 'decimal.dart';
import 'temporal.dart';

void registerSqliteFunctions(native.CommonDatabase db) {
  registerDecimalFunctions(db);
  registerTemporalFunctions(db);
}

List<Object?> sqliteParameters(List<Object?> parameters) => [
  for (final parameter in parameters)
    parameter is SqlReal ? _RealParameter(parameter.value) : parameter,
];

final class _RealParameter(final double value)
    implements native.CustomStatementParameter {
  @override
  void applyTo(native.CommonPreparedStatement statement, int index) =>
      statement.raw.bindDouble(index, value);
}
