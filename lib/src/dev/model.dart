import 'package:orm/schema.dart';

final class SchemaModel {
  SchemaModel(this.tables, this.selections);
  final List<TableModel> tables;
  final List<SelectionModel> selections;
}

final class TableModel {
  TableModel(this.name, this.dartName, this.fields, this.parameters);
  final String name;
  final String dartName;
  final List<FieldModel> fields;
  final List<ConstructorParameter> parameters;
  String get definitionName => '_${getterName}Definition';
  List<FieldModel> get insertableFields =>
      fields.where((field) => !field.column.identity).toList();
  List<FieldModel> get mutableFields =>
      fields.where((field) => !field.column.primaryKey).toList();
  List<FieldModel> get numericFields => mutableFields
      .where(
        (field) =>
            !field.column.nullable &&
            field.column.references == null &&
            (field.column.type == ScalarType.integer ||
                field.column.type == ScalarType.real),
      )
      .toList();
  List<FieldModel> get uniqueFields => insertableFields
      .where((field) => field.column.unique || field.column.primaryKey)
      .toList();
  FieldModel get primaryKey =>
      fields.singleWhere((field) => field.column.primaryKey);
  String get getterName => name
      .split(RegExp(r'[^a-zA-Z0-9]+'))
      .where((part) => part.isNotEmpty)
      .indexed
      .map(
        (part) => part.$1 == 0
            ? part.$2
            : '${part.$2[0].toUpperCase()}${part.$2.substring(1)}',
      )
      .join();
}

final class FieldModel {
  FieldModel(this.type, this.column);
  final String type;
  final ColumnDefinition column;
  String get name => column.field;
  String get baseType => type.replaceAll('?', '');
}

final class ConstructorParameter {
  ConstructorParameter(this.name, {required this.named});
  final String name;
  final bool named;
}

final class SelectionModel {
  SelectionModel(this.name, this.table, this.fields, this.shape);
  final String name;
  final TableModel table;
  final List<FieldModel> fields;
  final String shape;
}
