import 'package:meta/meta.dart';

abstract class Database {
  const Database({
    @mustBeConst required this.package,
    @mustBeConst required this.identifier,
  });

  @protected
  final String package;

  @protected
  final String identifier;

  @mustCallSuper
  Map<String, Object?> toJson() => {
    'package': package,
    'identifier': identifier,
  };
}
