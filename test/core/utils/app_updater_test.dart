import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/utils/app_updater.dart';

void main() {
  group('AppUpdater.isNewerVersion', () {
    test('newer patch/minor/major detected', () {
      expect(AppUpdater.isNewerVersion('0.1.3', 'v0.1.4'), isTrue);
      expect(AppUpdater.isNewerVersion('0.1.3', 'v0.2.0'), isTrue);
      expect(AppUpdater.isNewerVersion('0.1.3', 'v1.0.0'), isTrue);
    });

    test('same or older is not newer', () {
      expect(AppUpdater.isNewerVersion('0.1.3', 'v0.1.3'), isFalse);
      expect(AppUpdater.isNewerVersion('0.2.0', 'v0.1.9'), isFalse);
      expect(AppUpdater.isNewerVersion('1.0.0', 'v0.9.9'), isFalse);
    });

    test('release outranks same-core pre-release', () {
      expect(AppUpdater.isNewerVersion('0.1.3-beta', 'v0.1.3'), isTrue);
      expect(AppUpdater.isNewerVersion('0.1.3', 'v0.1.3-beta'), isFalse);
    });

    test('newer pre-release core still counts', () {
      expect(AppUpdater.isNewerVersion('0.1.3', 'v0.1.4-beta'), isTrue);
    });

    test('tolerates missing v prefix and uneven parts', () {
      expect(AppUpdater.isNewerVersion('0.1', 'v0.1.1'), isTrue);
      expect(AppUpdater.isNewerVersion('0.1.3', '0.1.3'), isFalse);
    });
  });
}
