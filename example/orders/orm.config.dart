import 'package:orm/config.dart';

void main() => defineConfig(
  database: .sqlite,
  models: 'models.dart',
  output: 'models.orm.dart',
  migrations: 'migrations',
);
