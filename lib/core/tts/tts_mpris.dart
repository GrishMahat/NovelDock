import 'dart:io';

import 'package:anni_mpris_service/anni_mpris_service.dart';
import 'package:dbus/dbus.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/utils/logger.dart';

const _tag = 'MPRIS';

/// MPRIS media controls for Linux.
///
/// Shows play/pause/skip in the system media widget and handles keyboard
/// media keys.
class TtsMpris {
  static MPRISService? _service;
  static bool _initialized = false;
  static Future<void>? _initializationFuture;

  static String? _artworkPath;
  static String? _artworkUrl;
  static Future<String?>? _artworkFuture;

  static Function()? onPlay;
  static Function()? onPause;
  static Function()? onStop;
  static Function()? onNext;
  static Function()? onPrevious;
  static void Function(LoopStatus loopStatus)? onLoopChange;

  static Future<void> init() async {
    if (_initialized || !Platform.isLinux) return;
    final existing = _initializationFuture;
    if (existing != null) return existing;

    final future = _initialize();
    _initializationFuture = future;
    try {
      await future;
    } finally {
      if (identical(_initializationFuture, future)) {
        _initializationFuture = null;
      }
    }
  }

  static Future<void> _initialize() async {
    try {
      final service = _TtsMPRISService();
      _service = service;
      _initialized = true;
      Log.ok(_tag, 'MPRIS initialized');
    } catch (e) {
      _service = null;
      _initialized = false;
      Log.e(_tag, 'Failed to init MPRIS', e);
    }
  }

  /// Download cover image to the temporary directory for MPRIS artwork.
  ///
  /// The same URL is reused without another download. A different cover URL
  /// replaces the cached artwork file.
  static Future<String?> cacheCoverArt(String? coverUrl) async {
    final normalizedUrl = coverUrl?.trim();

    if (normalizedUrl == null || normalizedUrl.isEmpty) {
      _artworkPath = null;
      _artworkUrl = null;
      return null;
    }

    final existingFuture = _artworkFuture;
    if (existingFuture != null && _artworkUrl == normalizedUrl) {
      return existingFuture;
    }

    if (_artworkUrl == normalizedUrl &&
        _artworkPath != null &&
        await File(
          Uri.parse(_artworkPath!.replaceFirst('file://', '')).path,
        ).exists()) {
      return _artworkPath;
    }

    final future = _downloadCoverArt(normalizedUrl);
    _artworkFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_artworkFuture, future)) _artworkFuture = null;
    }
  }

  static Future<String?> _downloadCoverArt(String normalizedUrl) async {
    try {
      final uri = Uri.tryParse(normalizedUrl);

      if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
        Log.w(_tag, 'Invalid cover URL: $normalizedUrl');

        _artworkPath = null;
        _artworkUrl = null;
        return null;
      }

      final tempDir = await getTemporaryDirectory();

      final filePath = p.join(tempDir.path, 'tts_cover.jpg');

      final file = File(filePath);

      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        Log.w(
          _tag,
          'Cover download failed: '
          '${response.statusCode}',
        );

        _artworkPath = null;
        _artworkUrl = null;
        return null;
      }

      await file.writeAsBytes(response.bodyBytes, flush: true);

      _artworkPath = Uri.file(file.path).toString();

      _artworkUrl = normalizedUrl;

      Log.ok(
        _tag,
        'Cover downloaded: '
        '${response.bodyBytes.length} bytes',
      );
      return _artworkPath;
    } on http.ClientException catch (e) {
      Log.e(_tag, 'Cover request failed', e);

      _artworkPath = null;
      _artworkUrl = null;
      return null;
    } on FormatException catch (e) {
      Log.e(_tag, 'Invalid cover URL: $normalizedUrl', e);

      _artworkPath = null;
      _artworkUrl = null;
      return null;
    } catch (e) {
      Log.e(_tag, 'Failed to download cover art', e);

      _artworkPath = null;
      _artworkUrl = null;
      return null;
    }
  }

  static Future<void> setCoverArt(String? coverUrl) async {
    await cacheCoverArt(coverUrl);
  }

  static void updateState({
    required String title,
    required String artist,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
  }) {
    final service = _service;

    if (service == null) return;

    try {
      final metadata = Metadata(
        trackId: '/org/mpris/MediaPlayer2/Track0',
        trackTitle: title,
        trackArtist: [artist],
        trackLength: duration,
        artUrl: _artworkPath,
      );

      final safePosition = position < Duration.zero ? Duration.zero : position;

      service.emitPropertiesChanged(
        'org.mpris.MediaPlayer2.Player',
        changedProperties: {
          'Metadata': metadata.toValue(),

          // MPRIS Position is a signed 64-bit integer representing
          // microseconds. changedProperties requires DBusValue instances.
          'Position': DBusInt64(safePosition.inMicroseconds),
        },
      );

      service.playbackStatus = isPlaying
          ? PlaybackStatus.playing
          : PlaybackStatus.paused;

      service.playbackRate = 1.0;
    } catch (e) {
      Log.e(_tag, 'Failed to update MPRIS state', e);
    }
  }

  static void hide() {
    final service = _service;

    if (service == null) return;

    try {
      service.playbackStatus = PlaybackStatus.stopped;
    } catch (e) {
      Log.w(_tag, 'Failed to hide MPRIS player: $e');
    }
  }

  static void dispose() {
    hide();

    _service = null;
    _initialized = false;
    _initializationFuture = null;
    _artworkFuture = null;

    _artworkPath = null;
    _artworkUrl = null;

    onPlay = null;
    onPause = null;
    onStop = null;
    onNext = null;
    onPrevious = null;
    onLoopChange = null;
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
  Future<void> onPlay() async {
    TtsMpris.onPlay?.call();
  }

  @override
  Future<void> onPause() async {
    TtsMpris.onPause?.call();
  }

  @override
  Future<void> onStop() async {
    TtsMpris.onStop?.call();
  }

  @override
  Future<void> onNext() async {
    TtsMpris.onNext?.call();
  }

  @override
  Future<void> onPrevious() async {
    TtsMpris.onPrevious?.call();
  }

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
