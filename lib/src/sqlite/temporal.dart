part of 'functions.dart';

void _registerTemporals(native.CommonDatabase db) {
  db.createFunction(
    functionName: 'orm_instant_v1',
    argumentCount: const native.AllowedArgumentCount(1),
    deterministic: true,
    directOnly: false,
    function: (args) => args[0] == null
        ? null
        : Codecs.dateTime.encode(Codecs.dateTime.decode(args[0])),
  );
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
  register<DateTime>('instant', (text) {
    try {
      return Codecs.dateTime.decode(text);
    } on FormatException {
      return null;
    }
  });
}
