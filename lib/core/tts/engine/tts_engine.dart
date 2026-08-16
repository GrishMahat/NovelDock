import 'dart:typed_data';

/// A voice offered by a [TtsEngine].
class TtsEngineVoice {
  final String id;
  final String name;
  final String locale;
  final String? gender;

  const TtsEngineVoice({
    required this.id,
    required this.name,
    required this.locale,
    this.gender,
  });
}

/// One event emitted by [TtsEngine.synthesize].
sealed class TtsSynthesisEvent {
  const TtsSynthesisEvent();
}

/// A chunk of MP3 audio bytes.
class TtsAudioBytes extends TtsSynthesisEvent {
  final Uint8List bytes;

  const TtsAudioBytes(this.bytes);
}

/// A word boundary within the current turn. Timings are absolute to the turn
/// start (already compensated across internal frames) in milliseconds.
class TtsWordBoundary extends TtsSynthesisEvent {
  final String word;
  final Duration offset;
  final Duration duration;

  const TtsWordBoundary({
    required this.word,
    required this.offset,
    required this.duration,
  });
}

/// An error during synthesis.
class TtsSynthesisError extends TtsSynthesisEvent {
  final Object error;
  final bool fatal;

  const TtsSynthesisError(this.error, {this.fatal = false});
}

/// The turn finished cleanly and no more events will follow.
class TtsTurnEnd extends TtsSynthesisEvent {
  const TtsTurnEnd();
}

/// One text-to-speech engine. Implementations are self-contained: voices,
/// synthesis, and engine-specific state (sockets, tokens) live inside the
/// engine; the rest of the app only speaks this interface.
abstract class TtsEngine {
  String get id;
  String get displayName;
  bool get supportsWordBoundaries;
  bool get requiresNetwork;

  /// Loads the engine's voice list.
  Future<List<TtsEngineVoice>> getVoices();

  /// Warms up caches / connectivity. Safe to call multiple times.
  Future<void> init();

  /// Releases engine resources (sockets, tokens). The engine can be reused
  /// after [reopen]. Safe to call when idle.
  Future<void> close();

  /// Re-opens the engine after [close]. Idempotent; no-op for stateless
  /// engines.
  void reopen();

  /// Drops any engine-side persistent session/socket so the next synthesis
  /// turn reconnects fresh, without disabling the engine (retry/backoff stay
  /// enabled). Used by stall recovery when a session is suspected of being
  /// wedged. No-op for engines without a persistent session.
  void invalidateSession() {}

  /// Synthesizes [text] as one turn.
  ///
  /// [rate] and [pitch] are engine-style strings (`'+10%'`, `'+0Hz'`). The
  /// stream emits [TtsAudioBytes], [TtsWordBoundary] (if supported), and ends
  /// with [TtsTurnEnd]; on failure it ends with [TtsSynthesisError] (fatal on
  /// network-level failures, retryable otherwise).
  Stream<TtsSynthesisEvent> synthesize(
    String text, {
    required String voiceId,
    required String rate,
    required String pitch,
    String? locale,
  });
}
