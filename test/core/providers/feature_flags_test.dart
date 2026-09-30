import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/providers/engine.dart';

// Pins the filters-aware POST search flag: providers whose searchConfig
// declares (query, page, filters) advertise searchConfigFilters (see
// register() in assets/providers/provider_helpers.js). Old providers
// without the key must default to false so the app never sends filters
// into a search path that ignores them.
void main() {
  group('ProviderFeatureFlags.searchConfigFilters', () {
    test('defaults to false', () {
      expect(const ProviderFeatureFlags().searchConfigFilters, isFalse);
    });

    test('missing key defaults to false', () {
      expect(
        ProviderFeatureFlags.fromJson(const {}).searchConfigFilters,
        isFalse,
      );
    });

    test('reads true when the provider opts in', () {
      expect(
        ProviderFeatureFlags.fromJson(const {
          'searchConfigFilters': true,
        }).searchConfigFilters,
        isTrue,
      );
    });
  });
}
