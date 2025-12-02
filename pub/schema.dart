import 'package:orm/sqlite.dart';

@Fragment()
abstract interface class Timestamps {
  abstract DateTime createdAt;
  abstract DateTime updatedAt;
}

@Model()
abstract interface class User implements Timestamps {
  @ID()
  abstract String id;
  abstract String name;
}
