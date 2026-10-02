import 'dart:io';

import 'src/conditional_default_consumer.dart';

/// Runs the focused fresh-consumer acceptance without the other browser suites.
Future<void> main(List<String> arguments) async {
  if (arguments.any((argument) => argument != '--wasm')) {
    throw ArgumentError('Use --wasm for the Dart WASM consumer.');
  }
  await verifyConditionalDefaultsChrome(
    wasm: arguments.contains('--wasm'),
    chrome:
        Platform.environment['CHROME_EXECUTABLE'] ??
        '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  );
}
