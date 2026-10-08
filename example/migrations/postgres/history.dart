import 'package:orm/database.dart';
import 'package:orm/migration.dart';

import 'v001_initial.dart' as initial;

/// Static, immutable history for postgresql only.
final history = MigrationHistory(
  engine: Engine.postgresql,
  migrations: [initial.migration],
);
