import 'package:orm/schema.dart';

int labelCalls = 0;
String nextLabel() => 'label-${++labelCalls}';

// Mixins are optional. Ordinary DTOs can continue declaring their own fields.
mixin SharedFields {
  @Id(generated: true)
  int id = 0;

  @Column(name: 'display_label')
  @ClientDefault(nextLabel)
  String label = '';

  @DatabaseDefault(true)
  bool active = false;

  String? note;

  @Ignore()
  final String local = 'local';

  String describe() => '$id: $label';
}

@Model()
final class Memo with SharedFields {
  final String title;

  Memo({
    required int id,
    required this.title,
    String label = 'constructor',
    bool active = false,
    String? note = 'guest',
  }) {
    this.id = id;
    this.label = label;
    this.active = active;
    this.note = note;
  }
}

@Model()
final class Task with SharedFields {
  @Relation(target: Memo, name: 'memo', inverse: 'tasks', onDelete: .cascade)
  final int memoId;
  final String title;

  Task({
    required int id,
    required this.memoId,
    required this.title,
    String label = 'constructor',
    bool active = false,
    String? note = 'guest',
  }) {
    this.id = id;
    this.label = label;
    this.active = active;
    this.note = note;
  }
}
