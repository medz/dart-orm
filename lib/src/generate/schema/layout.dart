import 'package:path/path.dart' as p;

import '../../../driver.dart' show SqlDialect;
import '../exception.dart';

/// One generation root, shared by file discovery and build assets.
final class SchemaLayout {
  final String root;
  final SqlDialect? dialect;
  final bool directory;

  SchemaLayout(String input, {required this.dialect, required this.directory})
    : root = stem(input) {
    if (directory && dialect == null) {
      throw const GenerationException(
        'Directory generation requires a database engine. Use --database or the project configuration.',
      );
    }
  }

  static String stem(String input) {
    final normalized = p.normalize(input);
    return normalized.endsWith('.dart')
        ? p.withoutExtension(normalized)
        : normalized;
  }

  String get file => '$root.dart';
  String get output => '$root.orm.dart';

  static bool declaration(String path) =>
      path.endsWith('.dart') &&
      !path.endsWith('.orm.dart') &&
      !path.endsWith('.snapshot.dart');

  bool includes(String path) {
    path = p.normalize(path);
    if (path == file) return true;
    if (!directory || !p.isWithin(root, path) || !declaration(path)) {
      return false;
    }
    final parts = p.split(p.relative(path, from: root));
    return parts.length == (dialect == SqlDialect.postgres ? 2 : 1);
  }

  String? namespace(String path) {
    path = p.normalize(path);
    if (directory && !includes(path)) {
      throw GenerationException(
        'Model declared outside the schema layout: $path. '
        'Use ${dialect == SqlDialect.postgres ? '$root/{schema}/*.dart' : '$root/*.dart'}.',
      );
    }
    if (dialect != SqlDialect.postgres) return null;
    if (path == file || !directory) return 'public';
    return p.split(p.relative(path, from: root)).first;
  }
}
