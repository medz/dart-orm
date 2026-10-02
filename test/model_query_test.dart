@Tags(['sqlite'])
library;

import 'package:test/test.dart';

import 'support/api_shape/scenarios.dart';

void main() {
  test('model queries compose named relations, typed writes and explicit preparation', () async {
    final checked = await runModelQueryScenarios();
    expect(checked, hasLength(35));
  });
}
