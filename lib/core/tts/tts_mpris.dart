import 'dart:io';

import 'package:anni_mpris_service/anni_mpris_service.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../core/utils/logger.dart';

const _tag = 'MPRIS';

/// MPRIS media controls for Linux.
/// Shows play/pause/skip in system media widget and keyboard media keys.
class TtsMpris {
  static MPRISService? _service;
  static bool _initialized = false;
  static String? _artworkPath;

  static Function()? onPlay;
  static Function()? onPause;
  static Function()? onStop;
  static Function()? onNext;
  static Function()? onPrevious;
  static void Function(LoopStatus loopStatus)? onLoopChange;

  static Future<void> init() async {
    if (_initialized) return;
    if (!Platform.isLinux) return;

    try {
      _service = _TtsMPRISService();
      _initialized = true;
      Log.ok(_tag, 'MPRIS initialized');
    } catch (e) {
      Log.e(_tag, 'Failed to init MPRIS', e);
    }
  }

  /// Download cover image to temp file for MPRIS artwork.
  static Future<void> setCoverArt(String? coverUrl) async {
    if (coverUrl == null || coverUrl.isEmpty) {
      _artworkPath = null;
      return;
    }
    try {
      final tempDir = await getTemporaryDirectory();
      final filePath = p.join(tempDir.path, 'tts_cover.jpg');
      final file = File(filePath);

      final exists = await file.exists();
      final hasContent = exists && await file.length() > 100;
      if (!hasContent) {
        final response = await http.get(Uri.parse(coverUrl)).timeout(
          const Duration(seconds: 10),
          onTimeout: () => http.Response('', 408),
        );
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          await file.writeAsBytes(response.bodyBytes);
          Log.ok(_tag, 'Cover downloaded: ${response.bodyBytes.length} bytes');
        } else {
          Log.w(_tag, 'Cover download failed: ${response.statusCode}');
          _artworkPath = null;
          return;
        }
      }
      _artworkPath = 'file://$filePath';
    } catch (e) {
      Log.e(_tag, 'Failed to download cover art', e);
      _artworkPath = null;
    }
  }

  static void updateState({
    required String title,
    required String artist,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
  }) {
    if (_service == null) return;
    try {
      // The anni_mpris_service Metadata setter is gated behind supportLoopStatus
      // which is false by default — so setting metadata silently does nothing.
      // We must use emitPropertiesChanged directly to actually send the update.
      final meta = Metadata(
        trackId: '/org/mpris/MediaPlayer2/Track0',
        trackTitle: title,
        trackArtist: [artist],
        trackLength: duration,
        artUrl: _artworkPath,
      );
      _service!.emitPropertiesChanged(
        'org.mpris.MediaPlayer2.Player',
        changedProperties: {
          'Metadata': meta.toValue(),
        },
      );
      _service!.playbackStatus = isPlaying ? PlaybackStatus.playing : PlaybackStatus.paused;
      _service!.playbackRate = 1.0;
    } catch (e) {
      Log.e(_tag, 'Failed to update MPRIS state', e);
    }
  }

  static void hide() {
    if (_service == null) return;
    try {
      _service!.playbackStatus = PlaybackStatus.stopped;
    } catch (_) {}
  }

  static void dispose() {
    hide();
    _service = null;
    _initialized = false;
    _artworkPath = null;
  }
}

class _TtsMPRISService extends MPRISService {
  _TtsMPRISService()
      : super(
          'NovelDock',
          identity: 'NovelDock TTS',
          canPlay: true,
          canPause: true,
          canGoPrevious: true,
          canGoNext: true,
          canSeek: false,
        );

  @override
  Future<void> onPlay() async => TtsMpris.onPlay?.call();

  @override
  Future<void> onPause() async => TtsMpris.onPause?.call();

  @override
  Future<void> onStop() async => TtsMpris.onStop?.call();

  @override
  Future<void> onNext() async => TtsMpris.onNext?.call();

  @override
  Future<void> onPrevious() async => TtsMpris.onPrevious?.call();

  @override
  Future<void> onPlayPause() async {
    if (playbackStatus == PlaybackStatus.playing) {
      TtsMpris.onPause?.call();
    } else {
      TtsMpris.onPlay?.call();
    }
  }

  @override
  Future<void> onSeek(int offset) async {}

  @override
  Future<void> onSetPosition(String trackId, int position) async {}

  @override
  Future<void> onLoopStatus(LoopStatus loopStatus) async {
    TtsMpris.onLoopChange?.call(loopStatus);
  }

  @override
  Future<void> onShuffle(bool shuffle) async {}
}
