import '../../schema_model.dart';
import 'exception.dart';

bool isMysqlDialect(SqlDialect dialect) =>
    dialect == SqlDialect.mysql || dialect == SqlDialect.mariadb;

// Database members and public execution extensions must not collide with getters.
const databaseMembers = {
  'sql',
  'raw',
  'query',
  'streamSql',
  'watchSql',
  'driver',
  'onQuery',
  'onAcquire',
  'onDecode',
  'capabilities',
  'dialect',
  'inTransaction',
  'inSession',
  'table',
  'registerSchema',
  'invalidate',
  'execute',
  'session',
  'discard',
  'transaction',
  'savepoint',
  'close',
  'checkActive',
  'run',
  'executeOn',
  'executeCommand',
  'atomic',
  'streamRows',
  'observeDecode',
  'markFailed',
  'hashCode',
  'runtimeType',
  'noSuchMethod',
  'toString',
};

// Names referenced without a prefix in generated clients.
const generatedTypeNames = {
  'Column',
  'Codecs',
  'TableSchema',
  'Fields',
  'Table',
  'Query',
  'QueryContext',
  'TableSet',
  'Change',
  'Relation',
  'IndexSchema',
  'ForeignKey',
  'ComputedColumn',
  'ComputedStorage',
  'CheckSchema',
  'String',
  'int',
  'double',
  'bool',
  'DateTime',
  'List',
  'Map',
  'Set',
  'Object',
  'Record',
  'Future',
  'BigInt',
  'Decimal',
  'LocalDate',
  'LocalTime',
  'LocalDateTime',
  'SqlJson',
  'Uint8List',
  'Expr',
  'Codec',
  'Sql',
  'SqlQuery',
  'SqlValue',
  'ResultShape',
  'ResultColumn',
  'SqlDialect',
};

final class ModelField {
  final String name;
  final String column;
  final String type;
  final String codec;
  final String storage;
  final bool nullable;
  final bool id;
  final bool generated;
  final bool unique;
  final String? defaultSql;
  final String? clientDefault;
  final ComputedColumn? computed;
  final int? integerBits;
  final int? decimalPrecision;
  final int? decimalScale;
  final int? temporalPrecision;
  const ModelField({
    required this.name,
    required this.column,
    required this.type,
    required this.codec,
    required this.storage,
    required this.nullable,
    this.id = false,
    this.generated = false,
    this.unique = false,
    this.defaultSql,
    this.clientDefault,
    this.computed,
    this.integerBits,
    this.decimalPrecision,
    this.decimalScale,
    this.temporalPrecision,
  });
  Column<Object?> snapshot() {
    final Codec<Object?> physical = switch (storage) {
      'integer' => Codecs.integer,
      'bigint' => Codecs.bigint,
      'decimal' => Codecs.decimal,
      'text' => Codecs.text,
      'real' => Codecs.real,
      'boolean' => Codecs.boolean,
      'instant' => Codecs.dateTime,
      'date' => Codecs.date,
      'time' => Codecs.time,
      'local_datetime' => Codecs.localDateTime,
      'blob' => Codecs.bytes,
      'json' => Codecs.json,
      _ => throw GenerationException('Unknown storage type $storage.'),
    };
    return Column<Object?>(
      column,
      nullable ? physical.nullable() : physical,
      nullable: nullable,
      generated: generated,
      defaultSql: defaultSql,
      computed: computed,
      integerBits: integerBits,
      decimalPrecision: decimalPrecision,
      decimalScale: decimalScale,
      temporalPrecision: temporalPrecision,
    );
  }
}

final class ModelEntity {
  final String name;
  final String table;
  final String row;
  final String? namespace;
  final bool grouped;
  String get binding => grouped ? '${namespace}_$name' : name;
  String get identity => namespace == null ? table : '$namespace.$table';
  final List<ModelField> fields;

  List<String> primaryKey;
  final List<List<String>> uniqueKeys;
  final List<ModelIndex> indexes = [];
  final List<ModelRelation> edges = [];
  final List<CheckSchema> checks = [];
  ModelEntity(
    this.name,
    this.table,
    this.row,
    this.fields, {
    this.namespace,
    this.grouped = false,
  }) : primaryKey = [
         for (final f in fields)
           if (f.id) f.name,
       ],
       uniqueKeys = [
         for (final f in fields)
           if (f.unique) [f.name],
       ];
  String get symbol => row;
  String get fieldsType => '${symbol}Fields';
  String get setType => '${symbol}TableSet';
  String get rowType => row;
  ModelField field(String name) => fields.firstWhere(
    (f) => f.name == name,
    orElse: () => throw GenerationException('$this has no field $name.'),
  );
  List<String> columns(List<String> keys) => [
    for (final key in keys) field(key).column,
  ];
  TableSchema snapshot() => TableSchema(
    table,
    namespace: namespace,
    columns: [for (final f in fields) f.snapshot()],
    primaryKey: columns(primaryKey),
    uniqueKeys: [for (final key in uniqueKeys) columns(key)],
    indexes: [
      for (final i in indexes)
        IndexSchema(i.name, columns(i.keys), unique: i.unique),
    ],
    foreignKeys: [
      for (final edge in edges)
        if (edge.isForeignKey)
          ForeignKey(
            columns(edge.parentKeys),
            edge.target.table,
            edge.target.columns(edge.childKeys),
            onDelete: edge.onDelete!,
            targetNamespace: edge.target.namespace,
          ),
    ],
    checks: checks,
  );
  @override
  String toString() => name;
}

final class ModelIndex(
  final String name,
  final List<String> keys,
  final bool unique,
);

/// Keys follow query navigation: [parentKeys] belong to the declaring model and
/// [childKeys] to [target], independently of the physical foreign-key direction.
final class ModelRelation(
  final String name,
  final ModelEntity target,
  final List<String> parentKeys,
  final List<String> childKeys,
  final String? onDelete, {
  final bool inverse = false,
}) {
  bool get isForeignKey => !inverse && onDelete != null;
}

String columnSymbol(ModelEntity entity, ModelField field) =>
    '_${entity.binding}${field.name[0].toUpperCase()}${field.name.substring(1)}';
