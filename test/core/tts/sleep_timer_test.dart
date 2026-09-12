import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/tts/tts_manager.dart';

// Pins the sleep timer contract: duration arming, nightly clock rollover,
// disarmed modes, and the user-facing status lines.
void main() {
  final now = DateTime(2026, 9, 12, 20, 0); // 20:00 local.

  group('computeSleepFireTime', () {
    test('off and unknown modes never fire', () {
      expect(
        computeSleepFireTime(
          mode: 'off',
          minutes: 30,
          hour: 21,
          minute: 0,
          now: now,
        ),
        isNull,
      );
      expect(
        computeSleepFireTime(
          mode: 'banana',
          minutes: 30,
          hour: 21,
          minute: 0,
          now: now,
        ),
        isNull,
      );
    });

    test('duration fires N minutes out, rejects non-positive', () {
      expect(
        computeSleepFireTime(
          mode: 'duration',
          minutes: 30,
          hour: 0,
          minute: 0,
          now: now,
        ),
        DateTime(2026, 9, 12, 20, 30),
      );
      expect(
        computeSleepFireTime(
          mode: 'duration',
          minutes: 0,
          hour: 0,
          minute: 0,
          now: now,
        ),
        isNull,
      );
    });

    test('clock later today fires today', () {
      expect(
        computeSleepFireTime(
          mode: 'clock',
          minutes: 0,
          hour: 21,
          minute: 30,
          now: now,
        ),
        DateTime(2026, 9, 12, 21, 30),
      );
    });

    test('clock already passed rolls to tomorrow (nightly recurrence)', () {
      expect(
        computeSleepFireTime(
          mode: 'clock',
          minutes: 0,
          hour: 7,
          minute: 0,
          now: now,
        ),
        DateTime(2026, 9, 13, 7, 0),
      );
    });

    test('clock exactly now rolls to tomorrow (must be strictly after)', () {
      expect(
        computeSleepFireTime(
          mode: 'clock',
          minutes: 0,
          hour: 20,
          minute: 0,
          now: now,
        ),
        DateTime(2026, 9, 13, 20, 0),
      );
    });
  });

  group('describeSleepTimer', () {
    test('off', () {
      expect(
        describeSleepTimer(
          mode: 'off',
          minutes: 30,
          hour: 21,
          minute: 0,
          endsAt: null,
          now: now,
        ),
        'Off',
      );
    });

    test('duration disarmed shows the setting', () {
      expect(
        describeSleepTimer(
          mode: 'duration',
          minutes: 45,
          hour: 0,
          minute: 0,
          endsAt: null,
          now: now,
        ),
        'In 45 min',
      );
    });

    test('duration armed shows remaining, rounded up', () {
      expect(
        describeSleepTimer(
          mode: 'duration',
          minutes: 30,
          hour: 0,
          minute: 0,
          endsAt: DateTime(2026, 9, 12, 20, 22, 30),
          now: now,
        ),
        'Stops in 23 min',
      );
    });

    test('clock shows daily time, plus remaining when armed', () {
      expect(
        describeSleepTimer(
          mode: 'clock',
          minutes: 0,
          hour: 21,
          minute: 0,
          endsAt: null,
          now: now,
        ),
        'Daily at 21:00',
      );
      expect(
        describeSleepTimer(
          mode: 'clock',
          minutes: 0,
          hour: 21,
          minute: 0,
          endsAt: DateTime(2026, 9, 12, 21, 0),
          now: now,
        ),
        'Daily at 21:00 · stops in 1h 0m',
      );
    });
  });
}
