import 'package:orm/schema.dart';

final note = model('notes', (
  id: identity(),
  body: text(),
  createdAt: dateTime(),
));
