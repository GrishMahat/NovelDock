import 'dart:async';

import 'package:audio_service/audio_service.dart';

/// Handles background audio playback and media notification controls.
///
/// Actual TTS playback is owned by [TtsPlaybackController]/just_audio.
/// This handler exposes playback state to Android's foreground notification,
/// lock-screen controls, and media buttons.
class BackgroundAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  /// Callbacks wired by TtsManager.
  FutureOr<void> Function()? onPlay;
  FutureOr<void> Function()? onPause;
  FutureOr<void> Function()? onStop;
  FutureOr<void> Function()? onSkipNext;
  FutureOr<void> Function()? onSkipPrevious;
  FutureOr<void> Function(Duration position)? onSeek;
  FutureOr<void> Function()? onSeekForward;
  FutureOr<void> Function()? onSeekBackward;

  bool _stopping = false;

  BackgroundAudioHandler() {
    _setIdleState();
  }

  void updateMediaInfo({
    required String title,
    required String artist,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
    String? artUri,
  }) {
    final safeDuration = duration < Duration.zero ? Duration.zero : duration;

    final safePosition = position < Duration.zero
        ? Duration.zero
        : safeDuration > Duration.zero && position > safeDuration
        ? safeDuration
        : position;

    mediaItem.add(
      MediaItem(
        id: 'tts',
        title: title,
        artist: artist,
        duration: safeDuration,
        artUri: artUri == null ? null : Uri.tryParse(artUri),
      ),
    );

    playbackState.add(
      playbackState.value.copyWith(
        controls: <MediaControl>[
          MediaControl.skipToPrevious,
          if (isPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const <MediaAction>{
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        processingState: AudioProcessingState.ready,
        playing: isPlaying,
        updatePosition: safePosition,
        speed: 1.0,
      ),
    );
  }

  Future<void> _invoke(FutureOr<void> Function()? callback) async {
    if (callback == null) return;
    await callback();
  }

  Future<void> _invokePosition(
    FutureOr<void> Function(Duration position)? callback,
    Duration position,
  ) async {
    if (callback == null) return;
    await callback(position);
  }

  @override
  Future<void> play() async {
    await _invoke(onPlay);
  }

  @override
  Future<void> pause() async {
    await _invoke(onPause);
  }

  @override
  Future<void> stop() async {
    if (_stopping) return;

    _stopping = true;

    try {
      await _invoke(onStop);
    } finally {
      dismiss();
      _stopping = false;
    }
  }

  /// Clears notification/media-session state without invoking [onStop].
  Future<void> dismiss() async {
    _setIdleState();
    mediaItem.add(null);

    // BaseAudioHandler.stop() is not awaited here because some versions of
    // audio_service expose the inherited implementation differently to the
    // analyzer. The state above is the actual state we need to publish.
    super.stop();
  }

  void _setIdleState() {
    playbackState.add(
      playbackState.value.copyWith(
        controls: const <MediaControl>[],
        systemActions: const <MediaAction>{},
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: Duration.zero,
        speed: 1.0,
      ),
    );
  }

  @override
  Future<void> seek(Duration position) async {
    await _invokePosition(onSeek, position);
  }

  @override
  Future<void> seekForward(bool begin) async {
    if (!begin) return;
    await _invoke(onSeekForward);
  }

  @override
  Future<void> seekBackward(bool begin) async {
    if (!begin) return;
    await _invoke(onSeekBackward);
  }

  @override
  Future<void> skipToNext() async {
    await _invoke(onSkipNext);
  }

  @override
  Future<void> skipToPrevious() async {
    await _invoke(onSkipPrevious);
  }

  @override
  Future<void> onTaskRemoved() async {
    if (_stopping) return;

    _stopping = true;

    try {
      await _invoke(onStop);
    } finally {
      dismiss();
      _stopping = false;
    }
  }
}

Future<BackgroundAudioHandler> initAudioService() async {
  return AudioService.init<BackgroundAudioHandler>(
    builder: () => BackgroundAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'dev.grish.noveldock.tts',
      androidNotificationChannelName: 'NovelDock TTS',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
}
