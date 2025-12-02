import 'package:meta/meta_meta.dart';

@Target({TargetKind.classType})
class Model {
  final String? table;

  const Model({this.table});
}
