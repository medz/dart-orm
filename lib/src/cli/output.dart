import 'dart:convert';
import 'dart:io';

final class CliOutput(final bool json) {
  void report(Map<String, Object?> value) {
    if (json) {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(value));
    } else {
      for (final entry in value.entries) {
        stdout.writeln(
          '${entry.key}: ${entry.value is String ? entry.value : jsonEncode(entry.value)}',
        );
      }
    }
  }

  void error(String message, int code) {
    stderr.writeln(
      json ? jsonEncode({'error': message, 'exitCode': code}) : message,
    );
    exitCode = code;
  }
}
