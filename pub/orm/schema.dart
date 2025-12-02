import 'package:orm_schema/src/schema/annotations/model.dart';
import 'package:orm_schema/src/schema/annotations/schema.dart';

const public = Schema('public');

@public
@Model()
abstract interface class User {
  @Unique()
  String get id;
}

@Model()
abstract interface class Profile {
  String get id;
}
