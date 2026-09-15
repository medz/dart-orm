part of '../../sqlite.dart';

void _registerTemporals(native.Database db) {
  void register<T extends Comparable<T>>(
    String kind,
    T? Function(String) parse,
  ) {
    db.createCollation(
      name: 'orm_${kind}_v1',
      function: (a, b) {
        // A collation cannot report a SQL error through FFI. Invalid external
        // text sorts after valid values; typed decoding rejects it.
        if (a == b) return 0;
        if (a == null) return -1;
        if (b == null) return 1;
        final left = parse(a), right = parse(b);
        if (left != null && right != null) return left.compareTo(right);
        if (left != null) return -1;
        if (right != null) return 1;
        return a.compareTo(b);
      },
    );
  }

  register('date', LocalDate.tryParse);
  register('time', LocalTime.tryParse);
  register('local_datetime', LocalDateTime.tryParse);
}
