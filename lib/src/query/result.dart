import '../../driver.dart';

/// Required result labels and typed decoding, independent of physical tables.
/// Compositions are validated at construction. Mapping callbacks run once per
/// actual row, never while compiling or binding empty results.
sealed class ResultShape<R> {
  const ResultShape._();

  /// Required labels and codecs. Extra SQL columns are ignored.
  List<ResultColumn<Object?>> get columns;
  R Function(List<Object?>) _bind(Map<String, int> indices);

  /// Resolves labels before reading any rows, including an empty result.
  /// Missing or duplicate required labels fail with `SQL.RESULT`.
  R Function(List<Object?>) bind(List<String> labels) {
    final indices = <String, int>{};
    for (final (index, label) in labels.indexed) {
      indices[label] = indices.containsKey(label) ? -1 : index;
    }
    for (final column in columns) {
      if ((indices[column.name] ?? -1) < 0) {
        throw OrmException(
          'SQL.RESULT',
          'Expected one result column named ${column.name}.',
        );
      }
    }
    return _bind(indices);
  }

  /// Converts decoded values into a record or application model.
  ResultShape<T> map<T>(T Function(R) mapper) => _MappedResult(this, mapper);
}

/// One result label and its storage/domain codec, with no write constraints.
final class ResultColumn<T> extends ResultShape<T> {
  /// Exact SQL result label, case sensitive.
  final String name;

  /// Decodes this result; it does not prove SQL nullability or expression type.
  final Codec<T> codec;

  /// Declares one nonempty SQL result label.
  ResultColumn(this.name, this.codec) : super._() {
    if (name.isEmpty || name.contains('\u0000')) {
      throw ArgumentError.value(name, 'name', 'Invalid result label');
    }
  }

  /// Accepts SQL NULL without changing the original codec or physical schema.
  ResultColumn<T?> nullable() => ResultColumn(name, codec.nullable());

  @override
  List<ResultColumn<Object?>> get columns => [this];

  @override
  T Function(List<Object?>) _bind(Map<String, int> indices) {
    final index = indices[name]!;
    return (row) {
      if (index >= row.length) {
        throw OrmException(
          'SQL.RESULT',
          'Missing value for result column $name.',
        );
      }
      final value = row[index];
      if (value == null && !codec.acceptsNull) {
        throw OrmException(
          'SQL.RESULT',
          'Unexpected SQL NULL in result column $name.',
        );
      }
      return codec.decode(value);
    };
  }
}

final class _MappedResult<A, R> extends ResultShape<R> {
  final ResultShape<A> source;
  final R Function(A) mapper;
  const _MappedResult(this.source, this.mapper) : super._();
  @override
  List<ResultColumn<Object?>> get columns => source.columns;
  @override
  R Function(List<Object?>) _bind(Map<String, int> indices) {
    final read = source._bind(indices);
    return (row) => mapper(read(row));
  }
}

final class _CombinedResult<R> extends ResultShape<R> {
  final List<ResultShape<Object?>> sources;
  final R Function(List<Object?>) Function(
    List<Object? Function(List<Object?>)>,
  )
  combine;
  @override
  final List<ResultColumn<Object?>> columns;
  _CombinedResult(this.sources, this.combine)
    : columns = _columns(sources),
      super._();
  static List<ResultColumn<Object?>> _columns(
    List<ResultShape<Object?>> sources,
  ) {
    final columns = <String, ResultColumn<Object?>>{};
    for (final source in sources) {
      for (final column in source.columns) {
        final previous = columns[column.name];
        if (previous != null && !previous.codec.sameStorageAs(column.codec)) {
          throw OrmException(
            'SQL.RESULT',
            'Conflicting codecs for result label ${column.name}.',
          );
        }
        columns[column.name] = column;
      }
    }
    return List.unmodifiable(columns.values);
  }

  @override
  R Function(List<Object?>) _bind(Map<String, int> indices) =>
      combine([for (final source in sources) source._bind(indices)]);
}

/// Combines 2 typed result descriptions, including nested result shapes.
extension Result2<A, B> on (ResultShape<A>, ResultShape<B>) {
  /// Maps decoded values once per actual row.
  ResultShape<R> map<R>(R Function(A, B) mapper) => _CombinedResult(
    [$1, $2],
    (read) =>
        (row) => mapper(read[0](row) as A, read[1](row) as B),
  );
}

/// Combines 3 typed result descriptions, including nested result shapes.
extension Result3<A, B, C> on (ResultShape<A>, ResultShape<B>, ResultShape<C>) {
  /// Maps decoded values once per actual row.
  ResultShape<R> map<R>(R Function(A, B, C) mapper) => _CombinedResult(
    [$1, $2, $3],
    (read) =>
        (row) =>
            mapper(read[0](row) as A, read[1](row) as B, read[2](row) as C),
  );
}

/// Combines 4 typed result descriptions, including nested result shapes.
extension Result4<A, B, C, D>
    on (ResultShape<A>, ResultShape<B>, ResultShape<C>, ResultShape<D>) {
  /// Maps decoded values once per actual row.
  ResultShape<R> map<R>(R Function(A, B, C, D) mapper) => _CombinedResult(
    [$1, $2, $3, $4],
    (read) =>
        (row) => mapper(
          read[0](row) as A,
          read[1](row) as B,
          read[2](row) as C,
          read[3](row) as D,
        ),
  );
}

/// Combines 5 typed result descriptions, including nested result shapes.
extension Result5<A, B, C, D, E>
    on
        (
          ResultShape<A>,
          ResultShape<B>,
          ResultShape<C>,
          ResultShape<D>,
          ResultShape<E>,
        ) {
  /// Maps decoded values once per actual row.
  ResultShape<R> map<R>(R Function(A, B, C, D, E) mapper) => _CombinedResult(
    [$1, $2, $3, $4, $5],
    (read) =>
        (row) => mapper(
          read[0](row) as A,
          read[1](row) as B,
          read[2](row) as C,
          read[3](row) as D,
          read[4](row) as E,
        ),
  );
}

/// Combines 6 typed result descriptions, including nested result shapes.
extension Result6<A, B, C, D, E, F>
    on
        (
          ResultShape<A>,
          ResultShape<B>,
          ResultShape<C>,
          ResultShape<D>,
          ResultShape<E>,
          ResultShape<F>,
        ) {
  /// Maps decoded values once per actual row.
  ResultShape<R> map<R>(R Function(A, B, C, D, E, F) mapper) => _CombinedResult(
    [$1, $2, $3, $4, $5, $6],
    (read) =>
        (row) => mapper(
          read[0](row) as A,
          read[1](row) as B,
          read[2](row) as C,
          read[3](row) as D,
          read[4](row) as E,
          read[5](row) as F,
        ),
  );
}
