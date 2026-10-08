import 'package:orm/database.dart';
import 'package:orm/migration.dart';

import 'v001_initial.dart' as initial;

/// Static, immutable history for sqlite only.
final history = MigrationHistory(
  engine: Engine.sqlite,
  migrations: [initial.migration],
);
