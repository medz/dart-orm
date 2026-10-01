import 'package:path/path.dart' as p;

/// One recursive model source root, shared by file discovery and build assets.
/// Source directories never determine physical database namespaces.
final class SchemaLayout {
  final String root;
  final bool directory;
  final p.Context _paths;

  SchemaLayout(String input, {required this.directory, p.Context? paths})
    : _paths = paths ?? p.context,
      root = stem(input, paths: paths);

  static String stem(String input, {p.Context? paths}) {
    paths ??= p.context;
    final normalized = paths.normalize(input);
    return normalized.endsWith('.dart')
        ? paths.withoutExtension(normalized)
        : normalized;
  }

  String get file => '$root.dart';
  String get output => '$root.orm.dart';

  static bool declaration(String path) =>
      path.endsWith('.dart') &&
      !path.endsWith('.orm.dart') &&
      !path.endsWith('.snapshot.dart');

  bool includes(String path) {
    path = _paths.normalize(path);
    if (path == file) return true;
    return directory && _paths.isWithin(root, path) && declaration(path);
  }
}
