import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_edge_tts/flutter_edge_tts.dart';

import '../../utils/logger.dart';
import 'tts_engine.dart';

const _tag = 'EdgeEngine';

/// [TtsEngine] backed by the persistent [EdgeTtsSession] from our fork of
/// `flutter_edge_tts` (GrishMahat/flutter_edge_tts, git dep pinned by tag).
///
/// One session (one WebSocket) is reused across turns; text is auto-split
/// into sequential SSML frames by the session and word-boundary offsets are
/// compensated across frames. The session does not reconnect on its own, so
/// this engine reconnects (fresh connection = fresh `Sec-MS-GEC` token) and
/// retries the turn with exponential backoff before failing fatally.
class EdgeTtsEngine implements TtsEngine {
  EdgeTtsSession? _session;
  String? _sessionVoice;
  String? _sessionLocale;
  int _consecutiveFailures = 0;
  bool _closed = false;

  static const Duration _initialBackoff = Duration(milliseconds: 500);
  static const Duration _maxBackoff = Duration(seconds: 10);
  static const int _maxAttempts = 3;

  /// Inactivity limit for one synthesis turn (no audio/boundary/end events).
  /// The edge-tts WebSocket can stall silently mid-turn (no error, no
  /// bytes); without this the `await for` hangs forever and playback dies
  /// with no recovery signal. Long enough for cold reconnects (20s) plus
  /// first-byte latency.
  static const Duration _turnIdleTimeout = Duration(seconds: 30);

  @override
  String get id => 'edge';

  @override
  String get displayName => 'Microsoft Edge TTS';

  @override
  bool get supportsWordBoundaries => true;

  @override
  bool get requiresNetwork => true;

  bool get isConnected => _session?.isConnected ?? false;

  @override
  Future<void> init() async {}

  /// Re-opens the engine after [close]. Idempotent.
  @override
  void reopen() {
    _closed = false;
  }

  @override
  Future<List<TtsEngineVoice>> getVoices() async {
    final tts = FlutterEdgeTts(
      voice: 'en-US-BrianMultilingualNeural',
      outputFormat: EdgeTtsOutputFormat.audio24Khz96KbitrateMonoMp3,
    );
    try {
      final voices = await tts.getVoices();
      return voices
          .map((v) => TtsEngineVoice(
                id: v.shortName,
                name: '${v.shortName} (${v.gender})',
                locale: v.locale,
                gender: v.gender,
              ))
          .toList();
    } on Object catch (e) {
      Log.e(_tag, 'Failed to get voices', e);
      return [];
    }
  }

  /// Returns a connected session for [voiceId], creating or replacing it when
  /// the voice (or locale) changes.
  Future<EdgeTtsSession> _ensureSession({
    required String voiceId,
    String? locale,
  }) async {
    final session = _session;
    final voiceChanged = voiceId != _sessionVoice || locale != _sessionLocale;
    if (session != null && session.isConnected && !voiceChanged) {
      return session;
    }
    await session?.close();
    _session = null;
    final fresh = EdgeTtsSession(
      voice: voiceId,
      voiceLocale: locale,
      enableWordBoundary: true,
    );
    await fresh.connect();
    _session = fresh;
    _sessionVoice = voiceId;
    _sessionLocale = locale;
    return fresh;
  }

  Duration _nextBackoff() {
    final exponent = math.max(0, _consecutiveFailures - 1);
    final multiplier = math.pow(2, exponent).toInt();
    return Duration(
      milliseconds:
          math.min(_initialBackoff.inMilliseconds * multiplier, _maxBackoff.inMilliseconds),
    );
  }

  void _disposeSession() {
    final session = _session;
    _session = null;
    _sessionVoice = null;
    _sessionLocale = null;
    if (session != null) {
      unawaited(session.close());
    }
  }

  @override
  Stream<TtsSynthesisEvent> synthesize(
    String text, {
    required String voiceId,
    required String rate,
    required String pitch,
    String? locale,
  }) async* {
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final session = await _ensureSession(voiceId: voiceId, locale: locale);

        // Per-event inactivity timeout: a turn that emits nothing for 30s is
        // dead even if the socket looks open. This turns a silent stall into
        // a retryable failure (and finally a fatal error).
        final turn = session.synthesize(
          text,
          prosody: EdgeTtsProsody(rate: rate, pitch: pitch, volume: '100'),
        ).timeout(_turnIdleTimeout);

        await for (final event in turn) {
          if (event is EdgeTtsAudioChunkEvent) {
            yield TtsAudioBytes(event.chunk);
          } else if (event is EdgeTtsMetadataEvent) {
            for (final item in event.metadata.items) {
              if (item.type != 'WordBoundary') continue;
              final data = item.data;
              final word = data.text?.text ?? '';
              yield TtsWordBoundary(
                word: word,
                offset: Duration(microseconds: data.offset ~/ 10),
                duration: Duration(microseconds: data.duration ~/ 10),
              );
            }
          }
        }

        // The session closes the turn stream both on a clean `turn.end` and
        // on socket failure (without an error event); a still-open socket is
        // the only signal that the turn ended cleanly.
        if (!session.isConnected) {
          throw StateError('Socket closed mid-turn');
        }
        _consecutiveFailures = 0;
        yield const TtsTurnEnd();
        return;
      } on Object catch (e) {
        Log.w(_tag, 'Synthesis attempt $attempt failed: $e');
        if (_closed) {
          _disposeSession();
          yield TtsSynthesisError(e, fatal: true);
          return;
        }
        _consecutiveFailures++;
        if (attempt < _maxAttempts) {
          final delay = _nextBackoff();
          Log.i(_tag, 'Reconnecting in ${delay.inMilliseconds}ms');
          _disposeSession();
          await Future<void>.delayed(delay);
        } else {
          _disposeSession();
          yield TtsSynthesisError(e, fatal: true);
          return;
        }
      }
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    final session = _session;
    _session = null;
    _sessionVoice = null;
    _sessionLocale = null;
    await session?.close();
  }
}
