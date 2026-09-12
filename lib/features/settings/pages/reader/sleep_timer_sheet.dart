import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/tts/tts_manager.dart';
import '../../../../theme/tokens.dart';

/// Sleep timer picker: stop TTS after N minutes, or daily at a clock time.
/// Clock mode recurs every night (re-armed on every firing); duration mode
/// fires once. Survives pause/stop; only a mode change or a fired duration
/// timer clears it.
Future<void> showSleepTimerSheet(BuildContext context, WidgetRef ref) async {
  final notifier = ref.read(ttsManagerProvider.notifier);
  final current = ref.read(ttsManagerProvider);

  const durations = [15, 30, 45, 60, 90];

  final selected = current.sleepTimerMode == sleepTimerDuration
      ? 'duration:${current.sleepMinutes}'
      : current.sleepTimerMode;

  void pick(BuildContext sheetContext, String? value) {
    if (value == null) return;
    if (value == sleepTimerOff) {
      unawaited(notifier.setSleepTimer(mode: sleepTimerOff));
      Navigator.of(sheetContext).pop();
      return;
    }
    if (value.startsWith('duration:')) {
      final minutes = int.tryParse(value.substring('duration:'.length)) ?? 30;
      unawaited(
        notifier.setSleepTimer(mode: sleepTimerDuration, minutes: minutes),
      );
      Navigator.of(sheetContext).pop();
    }
  }

  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Text(
                  'Sleep timer',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Stops playback when the time comes. '
                  'A clock time repeats every night.',
                ),
              ),
              RadioGroup<String>(
                groupValue: selected,
                onChanged: (value) => pick(sheetContext, value),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const RadioListTile<String>(
                      title: Text('Off'),
                      value: sleepTimerOff,
                    ),
                    for (final minutes in durations)
                      RadioListTile<String>(
                        title: Text('In $minutes minutes'),
                        value: 'duration:$minutes',
                      ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(
                  current.sleepTimerMode == sleepTimerClock
                      ? 'At ${_twoDigits(current.sleepHour)}:${_twoDigits(current.sleepMinute)} (daily)'
                      : 'At a time…',
                ),
                trailing: current.sleepTimerMode == sleepTimerClock
                    ? const Icon(Icons.check)
                    : null,
                onTap: () async {
                  final picked = await showTimePicker(
                    context: sheetContext,
                    initialTime: TimeOfDay(
                      hour: current.sleepHour,
                      minute: current.sleepMinute,
                    ),
                  );
                  if (picked != null) {
                    await notifier.setSleepTimer(
                      mode: sleepTimerClock,
                      hour: picked.hour,
                      minute: picked.minute,
                    );
                  }
                  if (sheetContext.mounted) {
                    Navigator.of(sheetContext).pop();
                  }
                },
              ),
              const SizedBox(height: Insets.md),
            ],
          ),
        ),
      );
    },
  );
}

String _twoDigits(int v) => v.toString().padLeft(2, '0');
