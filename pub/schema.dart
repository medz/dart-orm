import 'package:orm/sqlite.dart';

@Fragment()
class Timestamps {
  external DateTime createdAt;
  external DateTime updatedAt;
}

@Model()
class User implements Timestamps {
  @ID()
  external String id;
  external String name;
}
