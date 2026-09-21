import 'dart:typed_data' show Uint8List;

import '../../values.dart'
    show Codec, Decimal, LocalDate, LocalDateTime, LocalTime, SqlJson;
import 'model.dart' show ComputedStorage;

/// Database behavior when a referenced row is deleted.
enum ReferentialAction {
  /// Rejects deletion while referencing rows exist.
  restrict,

  /// Deletes rows that reference the deleted row.
  cascade,

  /// Sets referencing columns to SQL NULL; those columns must be nullable.
  setNull,

  /// Assigns the referencing columns' database defaults when supported.
  setDefault,

  /// Uses the database's NO ACTION constraint semantics.
  noAction,
}

/// One source definition for a physical table and its generated immutable row.
///
/// Create declarations with [model]; this type has no public constructor.
/// Use `final Model employee = model(...)` to break type inference cycles in
/// self references or mutually related models. Other declarations can infer
/// their type with `final employee = model(...)`.
/// Model identity belongs to the declaration, independently of Record equality.
final class Model {
  /// Explicit physical table name, independent of the Dart declaration name.
  final String table;

  /// Column declarations. Runtime Record access does not provide field discovery;
  /// generation reads the original named fields and their source order.
  final Record fields;

  const Model._(this.table, this.fields);
}

/// Defines a model using named column declarations and local constraints.
///
/// Declare a public `final employee = model('employees', (...))`. The named
/// Record's shape supplies the types in local key, index and relation selectors.
/// Add an explicit [Model] type to break self-reference or mutual-reference
/// inference cycles; selector field types are preserved in either form.
///
/// Select keys with a direct column or an ordered positional Record of columns.
/// Selectors must be arrow expressions. [relations] returns a named Record of
/// [references]/[referencedBy] declarations; other collections are literal lists.
/// Every field of [fields] must be a column declaration, checked by generation.
/// Callbacks are not executed and do not register mutable runtime metadata.
/// Generate and import the client to query typed rows.
Model model<S extends Record>(
  String table,
  S fields, {
  Object Function(S)? primaryKey,
  List<Object> Function(S)? uniqueKeys,
  List<IndexDefinition> Function(S)? indexes,
  Record Function(S)? relations,
  List<CheckDefinition>? checks,
}) => Model._(table, fields);

/// Typed source syntax for a stored column, interpreted by static generation.
///
/// Helpers such as [integer] and [text] provide the Dart value type. This object
/// does not encode values, execute SQL or expose runtime constraint metadata.
final class ColumnDefinition<T> {
  const ColumnDefinition._();

  /// Permits SQL NULL and generates a nullable Dart field.
  /// [clientDefault] may return null and runs only for omitted insert values.
  ColumnDefinition<T?> nullable({T? Function()? clientDefault}) =>
      ColumnDefinition<T?>._();

  /// Uses an integer-storage domain codec as a database-generated primary key.
  /// The column must be non-nullable and be the table's only primary-key field.
  ColumnDefinition<T> identity() => this;

  /// Computes the value in the database and excludes it from generated writes.
  /// Expressions are trusted SQL using physical column names, never parameters.
  /// Computed columns cannot also declare identity or insert defaults.
  ColumnDefinition<T> computed(
    String expression, {
    String? sqlite,
    String? postgres,
    String? mysql,
    String? mariadb,
    ComputedStorage storage = ComputedStorage.stored,
  }) => this;
}

/// A generated integer primary key. It may not be nullable or part of a
/// composite key. Omitted insert values are supplied by the database.
ColumnDefinition<int> identity({String? name}) => const ColumnDefinition._();

/// A signed integer column.
///
/// [name] fixes the physical column name; otherwise snake_case is derived from
/// the Record field. [defaultSql] is trusted database SQL. [clientDefault] runs
/// only for omitted insert values and may coexist with a database default.
ColumnDefinition<int> integer({
  String? name,
  bool unique = false,
  int? defaultValue,
  String? defaultSql,
  int Function()? clientDefault,
  int? bits,
}) => const ColumnDefinition._();

/// A text column.
///
/// [name] fixes the physical column name; otherwise snake_case is derived from
/// the Record field. [defaultSql] is trusted database SQL. [clientDefault] runs
/// only for omitted insert values and may coexist with a database default.
ColumnDefinition<String> text({
  String? name,
  bool unique = false,
  String? defaultValue,
  String? defaultSql,
  String Function()? clientDefault,
}) => const ColumnDefinition._();

/// A boolean column.
///
/// [name] fixes the physical column name; otherwise snake_case is derived from
/// the Record field. [defaultSql] is trusted database SQL. [clientDefault] runs
/// only for omitted insert values and may coexist with a database default.
ColumnDefinition<bool> boolean({
  String? name,
  bool unique = false,
  bool? defaultValue,
  String? defaultSql,
  bool Function()? clientDefault,
}) => const ColumnDefinition._();

/// A floating-point column.
///
/// [name] fixes the physical column name; otherwise snake_case is derived from
/// the Record field. [defaultSql] is trusted database SQL. [clientDefault] runs
/// only for omitted insert values and may coexist with a database default.
ColumnDefinition<double> real({
  String? name,
  bool unique = false,
  double? defaultValue,
  String? defaultSql,
  double Function()? clientDefault,
}) => const ColumnDefinition._();

/// An exact large integer column.
///
/// [name] fixes the physical column name; otherwise snake_case is derived from
/// the Record field. [defaultSql] is trusted database SQL. [clientDefault] runs
/// only for omitted insert values and may coexist with a database default.
ColumnDefinition<BigInt> bigInteger({
  String? name,
  bool unique = false,
  String? defaultSql,
  BigInt Function()? clientDefault,
}) => const ColumnDefinition._();

/// An exact decimal column.
///
/// [name] fixes the physical column name; otherwise snake_case is derived from
/// the Record field. [defaultSql] is trusted database SQL. [clientDefault] runs
/// only for omitted insert values and may coexist with a database default.
ColumnDefinition<Decimal> decimal({
  String? name,
  bool unique = false,
  String? defaultSql,
  Decimal Function()? clientDefault,
  int? precision,
  int? scale,
}) => const ColumnDefinition._();

/// A UTC instant column.
///
/// [name] fixes the physical column name; otherwise snake_case is derived from
/// the Record field. [defaultSql] is trusted database SQL. [clientDefault] runs
/// only for omitted insert values and may coexist with a database default.
ColumnDefinition<DateTime> dateTime({
  String? name,
  bool unique = false,
  String? defaultSql,
  DateTime Function()? clientDefault,
  int? precision,
}) => const ColumnDefinition._();

/// A calendar date without a timezone.
///
/// [name] fixes the physical column name; otherwise snake_case is derived from
/// the Record field. [defaultSql] is trusted database SQL. [clientDefault] runs
/// only for omitted insert values and may coexist with a database default.
ColumnDefinition<LocalDate> date({
  String? name,
  bool unique = false,
  String? defaultSql,
  LocalDate Function()? clientDefault,
}) => const ColumnDefinition._();

/// A wall-clock time without a timezone.
///
/// [name] fixes the physical column name; otherwise snake_case is derived from
/// the Record field. [defaultSql] is trusted database SQL. [clientDefault] runs
/// only for omitted insert values and may coexist with a database default.
ColumnDefinition<LocalTime> time({
  String? name,
  bool unique = false,
  String? defaultSql,
  LocalTime Function()? clientDefault,
  int? precision,
}) => const ColumnDefinition._();

/// A local timestamp without a timezone.
///
/// [name] fixes the physical column name; otherwise snake_case is derived from
/// the Record field. [defaultSql] is trusted database SQL. [clientDefault] runs
/// only for omitted insert values and may coexist with a database default.
ColumnDefinition<LocalDateTime> localDateTime({
  String? name,
  bool unique = false,
  String? defaultSql,
  LocalDateTime Function()? clientDefault,
  int? precision,
}) => const ColumnDefinition._();

/// A binary column.
///
/// [name] fixes the physical column name; otherwise snake_case is derived from
/// the Record field. [defaultSql] is trusted database SQL. [clientDefault] runs
/// only for omitted insert values and may coexist with a database default.
ColumnDefinition<Uint8List> bytes({
  String? name,
  bool unique = false,
  String? defaultSql,
  Uint8List Function()? clientDefault,
}) => const ColumnDefinition._();

/// A JSON document; its content can itself be JSON null.
///
/// [name] fixes the physical column name; otherwise snake_case is derived from
/// the Record field. [defaultSql] is trusted database SQL. [clientDefault] runs
/// only for omitted insert values and may coexist with a database default.
ColumnDefinition<SqlJson> json({
  String? name,
  bool unique = false,
  String? defaultSql,
  SqlJson Function()? clientDefault,
}) => const ColumnDefinition._();

/// An enum stored as text. Pass `Status.values`; optional [labels] maps every
/// constant to a distinct stable storage label without annotations.
/// [defaultValue] is encoded into a database default during generation.
ColumnDefinition<E> enumeration<E extends Enum>(
  List<E> values, {
  String? name,
  bool unique = false,
  Map<E, String>? labels,
  E? defaultValue,
  String? defaultSql,
  E Function()? clientDefault,
}) => ColumnDefinition<E>._();

/// A domain value with a public const codec. Generation reads its storage tag
/// and references its encode/decode functions without executing them.
/// [bits] constrains integer storage to 16, 32 or 64 bits. [precision] and
/// [scale] configure decimal storage; temporal storage accepts [precision]
/// from 0 to 6. These options describe storage, independently of the Dart type.
ColumnDefinition<T> custom<T>(
  Codec<T> codec, {
  String? name,
  bool unique = false,
  String? defaultSql,
  T Function()? clientDefault,
  int? bits,
  int? precision,
  int? scale,
}) => ColumnDefinition<T>._();

/// An index declaration for the `indexes` selector of [model].
final class IndexDefinition {
  const IndexDefinition._();
}

/// Selects a direct column or an ordered positional Record of columns.
/// The physical [name] is explicit and does not depend on local variable names.
IndexDefinition index(
  Object columns, {
  required String name,
  bool unique = false,
}) => const IndexDefinition._();

/// A relationship in the named Record returned by the `relations` selector
/// of [model].
/// Its Record field name becomes the generated query navigation name.
final class ReferenceDefinition {
  const ReferenceDefinition._();
}

/// Declares a foreign key and forward navigation on the current model.
///
/// [columns] selects a local column or a positional Record in target primary-key
/// order. A named Record instead maps target field names to local columns, e.g.
/// `(tenantId: m.tenantId, code: m.teamCode)`. Generation validates target names,
/// value types, codecs and uniqueness, and orders the mapping by the target key.
/// Named mappings do not provide Dart completion for target fields.
///
/// [target] must name a model, e.g. `() => employee`; generation never invokes it.
/// The relation's name comes from its enclosing Record field, e.g.
/// `relations: (e) => (manager: references(e.managerId, () => employee),)`.
/// [constraint] false creates read-only navigation without a database foreign
/// key. It does not infer uniqueness or add an index.
ReferenceDefinition references(
  Object columns,
  Model Function() target, {
  ReferentialAction onDelete = ReferentialAction.restrict,
  bool constraint = true,
}) => const ReferenceDefinition._();

/// Declares reverse navigation on the current model, without another foreign key.
///
/// [target] must name a model, e.g. `() => employee`, with a forward [references]
/// declaration pointing to the current model. Generation requires one matching
/// reference; no match or ambiguity is an error, never a naming heuristic.
///
/// When several references exist, [on] maps target foreign-key field names to
/// local columns, e.g. `referencedBy(() => post, on: (authorId: u.id))`.
/// This also supports composite keys. Mapping names are checked by generation;
/// local columns retain native Dart types and completion. A reverse of a
/// read-only forward reference is also read-only. Callbacks are never invoked.
ReferenceDefinition referencedBy(Model Function() target, {Record? on}) =>
    const ReferenceDefinition._();

/// A trusted database CHECK declaration for the `checks` argument of [model].
final class CheckDefinition {
  const CheckDefinition._();
}

/// Declares a CHECK using physical column names. The database evaluates
/// the trusted SQL expression. Dialect overrides are explicit. Use a stable
/// [name], or `name: null` to preserve an unnamed imported constraint.
CheckDefinition check(
  String expression, {
  required String? name,
  String? sqlite,
  String? postgres,
  String? mysql,
  String? mariadb,
}) => const CheckDefinition._();
