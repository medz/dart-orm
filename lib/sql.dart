/// Typed SQL construction and result shaping, independent of connection runtimes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'driver.dart';
import 'schema_model.dart';
export 'driver.dart';
export 'schema_model.dart';

part 'src/sql_context.dart';
part 'src/temporal_sql.dart';
part 'src/decimal_sql.dart';
part 'src/decimal_division.dart';
part 'src/decimal_average.dart';
part 'src/sql.dart';
part 'src/named_sql.dart';
part 'src/selection.dart';
part 'src/table.dart';
part 'src/query.dart';
part 'src/plan.dart';
part 'src/mutation.dart';
part 'src/relation.dart';
part 'src/batch.dart';
part 'src/advanced.dart';
part 'src/cte.dart';
part 'src/cursor.dart';
part 'src/union.dart';
part 'src/query_reads.dart';
part 'src/query_stream.dart';
