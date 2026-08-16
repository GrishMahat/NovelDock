import 'package:audio_service/audio_service.dart';

/// Handles background audio playback and media notification controls via audio_service.
///
/// On Android this runs a foreground service, keeping audio alive when the
/// screen is off. It also provides lock screen / notification media controls.
///
/// Actual audio playback is handled by the TTS player (just_audio); this
/// handler only manages the notification/state that audio_service exposes.
class BackgroundAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  /// Callbacks wired from TtsManager.
  void Function()? onPlay;
  void Function()? onPause;
  void Function()? onStop;
  void Function()? onSkipNext;
  void Function()? onSkipPrevious;
  void Function(Duration position)? onSeek;
  void Function()? onSeekForward;
  void Function()? onSeekBackward;

  BackgroundAudioHandler() {
    // Forward media button actions to callbacks
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
    ));
  }

  /// Update the media notification with current TTS state.
  void updateMediaInfo({
    required String title,
    required String artist,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
  }) {
    mediaItem.add(MediaItem(
      id: 'tts',
      title: title,
      artist: artist,
      duration: duration,
    ));

    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (isPlaying) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      processingState: AudioProcessingState.ready,
      playing: isPlaying,
      updatePosition: position,
      speed: 1.0,
    ));
  }

  @override
  Future<void> play() async => onPlay?.call();

  @override
  Future<void> pause() async => onPause?.call();

  @override
  Future<void> stop() async {
    onStop?.call();
    await dismiss();
  }

  /// Clears the notification/state without invoking [onStop]. Used for
  /// app-internal calls: the manager's own stop() already runs the teardown,
  /// and calling back into it here would re-enter stop() forever.
  Future<void> dismiss() async {
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async => onSeek?.call(position);

  @override
  Future<void> seekForward(bool begin) async => onSeekForward?.call();

  @override
  Future<void> seekBackward(bool begin) async => onSeekBackward?.call();

  @override
  Future<void> onTaskRemoved() async => onStop?.call();
}

/// Initializes audio_service and returns the handler.
Future<BackgroundAudioHandler> initAudioService() async {
  return await AudioService.init<BackgroundAudioHandler>(
    builder: () => BackgroundAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'dev.grish.noveldock.tts',
      androidNotificationChannelName: 'NovelDock TTS',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
}
