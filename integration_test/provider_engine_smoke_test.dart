import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:noveldock/core/providers/engine.dart';

/// On-device smoke for the caged provider runtime (see AUDIT.md P0-3).
/// The host `flutter test` runner cannot load libquickjs, so this runs here:
/// it exercises the exact construction used by ProviderEngine.loadProvider
/// (no fetch/XHR, promise handling) plus load/dispose lifecycle on a
/// synthetic provider source.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const syntheticSource = '''
var module = { exports: {} };
module.exports = {
  ping: function() { return "pong"; },
  add: function(a, b) { return a + b; }
};
''';

  testWidgets('provider loads, evaluates, and disposes', (tester) async {
    final engine = ProviderEngine();
    try {
      final instance = await engine.loadProvider(syntheticSource);
      expect(await instance.call('ping', []), 'pong');
      expect(await instance.call('add', [2, 3]), 5);

      // No network capability inside provider JS.
      expect(
        instance.runtime.evaluate('typeof fetch').stringResult,
        'undefined',
      );
      expect(
        instance.runtime.evaluate('typeof XMLHttpRequest').stringResult,
        'undefined',
      );

      engine.disposeRuntime(instance);
    } finally {
      engine.dispose();
    }
  });
}
