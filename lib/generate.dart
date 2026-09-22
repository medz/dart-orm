/// Source generation, catalog import and reviewed migration files.
///
/// Use [generateSchema] for an in-memory result or [writeGeneratedSchema] to
/// update the client and physical snapshot.
/// These development tools analyze Dart source; applications import their
/// generated client and a database entrypoint instead.
///
/// {@category Tooling}
/// {@canonicalFor exception.GenerationException}
/// {@canonicalFor schema.GeneratedSchema}
/// {@canonicalFor schema.generateSchema}
/// {@canonicalFor schema.writeGeneratedSchema}
/// {@canonicalFor import.ImportedSchema}
/// {@canonicalFor import.SchemaImportIssue}
/// {@canonicalFor import.importSchema}
/// {@canonicalFor migrations.writeMigrationRegistry}
/// {@canonicalFor migrations.writeMigration}
/// {@canonicalFor migrations.recordMigration}
library;

export 'src/generate/exception.dart' show GenerationException;
export 'src/generate/schema.dart'
    show GeneratedSchema, generateSchema, writeGeneratedSchema;
export 'src/generate/import.dart'
    show ImportedSchema, SchemaImportIssue, importSchema;
export 'src/generate/migrations.dart'
    show writeMigrationRegistry, writeMigration, recordMigration;
