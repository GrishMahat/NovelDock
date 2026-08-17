import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_edge_tts/flutter_edge_tts.dart';

import '../../utils/logger.dart';
import 'tts_engine.dart';

const _tag = 'EdgeEngine';

/// [TtsEngine] backed by the persistent [EdgeTtsSession].
///
/// One session is reused across synthesis turns while the requested voice and
/// locale remain unchanged. When a session fails or becomes stale, it is
/// replaced with a fresh connection and the current turn is retried with
/// exponential backoff.
class EdgeTtsEngine implements TtsEngine {
  EdgeTtsSession? _session;
  String? _sessionVoice;
  String? _sessionLocale;

  int _consecutiveFailures = 0;

  bool _closed = false;
  bool _disposed = false;

  /// Incremented whenever the active session is invalidated/replaced.
  ///
  /// A synthesis operation captures this generation and must not install a
  /// session or continue retrying if the generation changes underneath it.
  int _sessionGeneration = 0;

  static const Duration _initialBackoff = Duration(milliseconds: 500);

  static const Duration _maxBackoff = Duration(seconds: 10);

  static const int _maxAttempts = 3;

  /// Maximum time between events from one synthesis turn.
  ///
  /// A silent Edge WebSocket can otherwise leave an await-for suspended
  /// forever.
  static const Duration _turnIdleTimeout = Duration(seconds: 30);

  @override
  String get id => 'edge';

  @override
  String get displayName => 'Microsoft Edge TTS';

  @override
  bool get supportsWordBoundaries => true;

  @override
  bool get requiresNetwork => true;

  bool get isConnected =>
      !_closed && !_disposed && (_session?.isConnected ?? false);

  @override
  Future<void> init() async {
    // Connection is lazy. Creating the WebSocket here would make startup
    // depend on network availability and would waste a connection when TTS
    // is never used.
  }

  /// Re-opens the engine after [close].
  ///
  /// The next synthesis turn will create a session lazily.
  @override
  void reopen() {
    if (_disposed) return;

    _closed = false;
  }

  /// Drops the persistent session without permanently closing the engine.
  ///
  /// Used for stall recovery so the next synthesis gets a fresh WebSocket and
  /// fresh Edge session state.
  @override
  void invalidateSession() {
    if (_disposed) return;

    ++_sessionGeneration;
    _consecutiveFailures = 0;

    _detachSession();
  }

  @override
  Future<List<TtsEngineVoice>> getVoices() async {
    if (_disposed) return const [];

    final tts = FlutterEdgeTts(
      voice: 'en-US-BrianMultilingualNeural',
      outputFormat: EdgeTtsOutputFormat.audio24Khz96KbitrateMonoMp3,
    );

    try {
      final voices = await tts.getVoices();

      return voices
          .map(
            (voice) => TtsEngineVoice(
              id: voice.shortName,
              name: '${voice.shortName} (${voice.gender})',
              locale: voice.locale,
              gender: voice.gender,
            ),
          )
          .toList(growable: false);
    } catch (e) {
      Log.e(_tag, 'Failed to get voices', e);
      return const [];
    }
  }

  /// Returns a connected session matching [voiceId]/[locale].
  ///
  /// Session creation is generation-aware so a stale synthesis operation
  /// cannot overwrite a newer session created after an invalidation.
  Future<EdgeTtsSession> _ensureSession({
    required String voiceId,
    String? locale,
    required int generation,
  }) async {
    if (_disposed || _closed) {
      throw StateError('Edge TTS engine is closed');
    }

    if (generation != _sessionGeneration) {
      throw StateError('Edge TTS session generation is stale');
    }

    final existing = _session;

    final voiceChanged = voiceId != _sessionVoice || locale != _sessionLocale;

    if (existing != null && existing.isConnected && !voiceChanged) {
      return existing;
    }

    // Detach the old session first. Its close handshake is intentionally not
    // awaited because a peer can take several seconds to acknowledge it.
    _detachSession();

    if (generation != _sessionGeneration || _closed || _disposed) {
      throw StateError('Edge TTS session was invalidated');
    }

    final fresh = EdgeTtsSession(
      voice: voiceId,
      voiceLocale: locale,
      enableWordBoundary: true,
    );

    try {
      await fresh.connect();
    } catch (e) {
      unawaited(_closeQuietly(fresh));
      rethrow;
    }

    // The caller may have invalidated the engine while connect() was
    // establishing the WebSocket.
    if (generation != _sessionGeneration || _closed || _disposed) {
      unawaited(_closeQuietly(fresh));

      throw StateError('Edge TTS session became stale');
    }

    _session = fresh;
    _sessionVoice = voiceId;
    _sessionLocale = locale;

    return fresh;
  }

  Duration _nextBackoff() {
    final exponent = math.max(0, _consecutiveFailures - 1);

    final multiplier = math.pow(2, exponent).toInt();

    return Duration(
      milliseconds: math.min(
        _initialBackoff.inMilliseconds * multiplier,
        _maxBackoff.inMilliseconds,
      ),
    );
  }

  void _detachSession() {
    final session = _session;

    _session = null;
    _sessionVoice = null;
    _sessionLocale = null;

    if (session != null) {
      unawaited(_closeQuietly(session));
    }
  }

  Future<void> _closeQuietly(EdgeTtsSession session) async {
    try {
      await session.close();
    } catch (e) {
      Log.w(_tag, 'Edge session close failed: $e');
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
    if (_disposed || _closed) {
      yield TtsSynthesisError(
        StateError('Edge TTS engine is closed'),
        fatal: true,
      );
      return;
    }

    if (text.trim().isEmpty) {
      yield TtsSynthesisError(
        StateError('Cannot synthesize empty text'),
        fatal: false,
      );
      return;
    }

    final generation = _sessionGeneration;

    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      if (_disposed || _closed || generation != _sessionGeneration) {
        yield TtsSynthesisError(
          StateError('Edge TTS synthesis was invalidated'),
          fatal: true,
        );
        return;
      }

      try {
        final session = await _ensureSession(
          voiceId: voiceId,
          locale: locale,
          generation: generation,
        );

        if (_disposed || _closed || generation != _sessionGeneration) {
          return;
        }

        final prosody = EdgeTtsProsody(rate: rate, pitch: pitch, volume: '100');

        // Timeout applies between events, turning a silent/stuck socket into
        // a normal retry path.
        final turn = session
            .synthesize(text, prosody: prosody)
            .timeout(_turnIdleTimeout);

        var sawAudio = false;

        await for (final event in turn) {
          if (_disposed || _closed || generation != _sessionGeneration) {
            return;
          }

          if (event is EdgeTtsAudioChunkEvent) {
            if (event.chunk.isEmpty) {
              continue;
            }

            sawAudio = true;

            yield TtsAudioBytes(event.chunk);
            continue;
          }

          if (event is EdgeTtsMetadataEvent) {
            for (final item in event.metadata.items) {
              if (item.type != 'WordBoundary') {
                continue;
              }

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

        // A clean stream termination is considered a successful turn. The
        // Edge session may close its WebSocket immediately after turn.end,
        // so requiring isConnected here would cause needless re-synthesis.
        //
        // However, a completely empty turn is not useful audio and should
        // not be accepted as success.
        if (!sawAudio) {
          throw StateError('Edge TTS returned no audio');
        }

        _consecutiveFailures = 0;

        yield const TtsTurnEnd();
        return;
      } on Object catch (e) {
        if (_disposed || _closed || generation != _sessionGeneration) {
          yield TtsSynthesisError(e, fatal: true);
          return;
        }

        Log.w(_tag, 'Synthesis attempt $attempt failed: $e');

        _consecutiveFailures++;

        // Always detach the failed session before retrying. Reusing a socket
        // that just timed out or emitted an error is exactly how a dead
        // session becomes a very determined dead session.
        _detachSession();

        if (attempt >= _maxAttempts) {
          yield TtsSynthesisError(e, fatal: true);
          return;
        }

        final delay = _nextBackoff();

        Log.i(
          _tag,
          'Retrying Edge TTS in '
          '${delay.inMilliseconds}ms',
        );

        await Future<void>.delayed(delay);

        if (_disposed || _closed || generation != _sessionGeneration) {
          yield TtsSynthesisError(
            StateError('Edge TTS retry was invalidated'),
            fatal: true,
          );
          return;
        }
      }
    }
  }

  @override
  Future<void> close() async {
    if (_disposed) return;

    _closed = true;
    ++_sessionGeneration;

    _consecutiveFailures = 0;

    final session = _session;

    _session = null;
    _sessionVoice = null;
    _sessionLocale = null;

    if (session != null) {
      // Do not wait for the WebSocket close handshake.
      unawaited(_closeQuietly(session));
    }
  }

  /// Permanently disposes the engine.
  ///
  /// The interface does not currently expose a separate dispose method, but
  /// keeping this available makes ownership explicit for callers that own the
  /// engine instance directly.
  Future<void> dispose() async {
    if (_disposed) return;

    _disposed = true;
    _closed = true;
    ++_sessionGeneration;

    _consecutiveFailures = 0;

    final session = _session;

    _session = null;
    _sessionVoice = null;
    _sessionLocale = null;

    if (session != null) {
      unawaited(_closeQuietly(session));
    }
  }
}
