import 'package:orm/schema.dart';

typedef Note = ({@Id.generated() int id, String body, DateTime createdAt});
final notes = entity<Note>(table: 'notes');
