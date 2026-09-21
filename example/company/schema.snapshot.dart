// Generated physical schema. Keep historical copies with their migration.
import 'package:orm/migrate.dart';

final schema = SchemaSnapshot([
  TableSchema(
    "departments",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("name", Codecs.text),
    ],
    primaryKey: ["id"],
    uniqueKeys: [
      ["name"],
    ],
  ),
  TableSchema(
    "employees",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("name", Codecs.text),
      Column("email", Codecs.text),
      Column("active", Codecs.boolean, defaultSql: "true"),
      Column("created_at", Codecs.dateTime),
      Column("department_id", Codecs.integer),
      Column("manager_id", Codecs.integer.nullable(), nullable: true),
    ],
    primaryKey: ["id"],
    uniqueKeys: [
      ["email"],
    ],
    indexes: [
      IndexSchema("employees_department_id", [
        "department_id",
        "id",
      ], unique: false),
      IndexSchema("employees_manager_id", ["manager_id", "id"], unique: false),
    ],
    foreignKeys: [
      ForeignKey(
        ["department_id"],
        "departments",
        ["id"],
        onDelete: "RESTRICT",
      ),
      ForeignKey(["manager_id"], "employees", ["id"], onDelete: "SET NULL"),
    ],
  ),
  TableSchema(
    "projects",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("name", Codecs.text),
      Column("status", Codecs.text, defaultSql: "'draft'"),
      Column("created_at", Codecs.dateTime),
      Column("owner_id", Codecs.integer),
    ],
    primaryKey: ["id"],

    indexes: [
      IndexSchema("projects_owner_id", ["owner_id", "id"], unique: false),
    ],
    foreignKeys: [
      ForeignKey(["owner_id"], "employees", ["id"], onDelete: "RESTRICT"),
    ],
  ),
  TableSchema(
    "project_members",
    columns: [
      Column("project_id", Codecs.integer),
      Column("employee_id", Codecs.integer),
      Column("role", Codecs.text, defaultSql: "'member'"),
      Column("joined_at", Codecs.dateTime),
    ],
    primaryKey: ["project_id", "employee_id"],

    indexes: [
      IndexSchema("project_members_employee_project", [
        "employee_id",
        "project_id",
      ], unique: false),
    ],
    foreignKeys: [
      ForeignKey(["project_id"], "projects", ["id"], onDelete: "CASCADE"),
      ForeignKey(["employee_id"], "employees", ["id"], onDelete: "CASCADE"),
    ],
  ),
]);
