/// Development-time source generation and migration file operations.
/// Application code imports a generated client and a database entrypoint.
library;

export 'src/generate.dart'
    show
        GenerationException,
        GeneratedSchema,
        generateSchema,
        writeGeneratedSchema,
        GeneratedQueries,
        generateQueries,
        writeGeneratedQueries,
        checkGeneratedQueries,
        checkSqlQueries,
        ImportedSchema,
        SchemaImportIssue,
        importSchema,
        writeMigrationRegistry,
        writeMigration,
        recordMigration;
