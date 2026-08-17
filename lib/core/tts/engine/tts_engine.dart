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

  @override
  String toString() {
    return 'TtsEngineVoice('
        'id: $id, '
        'name: $name, '
        'locale: $locale, '
        'gender: $gender'
        ')';
  }
}

/// One event emitted by [TtsEngine.synthesize].
sealed class TtsSynthesisEvent {
  const TtsSynthesisEvent();
}

/// A chunk of encoded audio bytes.
///
/// The controller expects these bytes to belong to the current synthesis
/// turn and appends them in the order received.
class TtsAudioBytes extends TtsSynthesisEvent {
  final Uint8List bytes;

  const TtsAudioBytes(this.bytes);

  bool get isEmpty => bytes.isEmpty;
}

/// A word boundary within the current synthesis turn.
///
/// [offset] is relative to the beginning of this turn, not the overall
/// chapter. The playback controller converts it into paragraph-level
/// highlighting information.
class TtsWordBoundary extends TtsSynthesisEvent {
  final String word;
  final Duration offset;
  final Duration duration;

  const TtsWordBoundary({
    required this.word,
    required this.offset,
    required this.duration,
  }) : assert(
         offset >= Duration.zero,
         'Word-boundary offset cannot be negative.',
       ),
       assert(
         duration >= Duration.zero,
         'Word-boundary duration cannot be negative.',
       );
}

/// An error during synthesis.
///
/// A fatal error indicates that retrying the current engine session is not
/// expected to succeed. A non-fatal error may be recoverable by the caller,
/// but implementations should still normally terminate the affected stream
/// rather than continue emitting an unrelated partial turn.
class TtsSynthesisError extends TtsSynthesisEvent {
  final Object error;
  final bool fatal;

  const TtsSynthesisError(this.error, {this.fatal = false});
}

/// Indicates that a synthesis turn completed successfully.
///
/// A successful turn should emit exactly one [TtsTurnEnd] after all audio and
/// boundary events for that turn.
class TtsTurnEnd extends TtsSynthesisEvent {
  const TtsTurnEnd();
}

/// One text-to-speech engine.
///
/// Implementations are self-contained. Voice discovery, synthesis, network
/// sessions, authentication, retry policy, and engine-specific state remain
/// inside the implementation.
///
/// The rest of the application interacts only through this interface.
abstract class TtsEngine {
  String get id;

  String get displayName;

  /// Whether this engine can emit [TtsWordBoundary] events.
  bool get supportsWordBoundaries;

  /// Whether synthesis requires an active network connection.
  bool get requiresNetwork;

  /// Loads the engine's available voices.
  ///
  /// Implementations may cache the result.
  Future<List<TtsEngineVoice>> getVoices();

  /// Initializes/warm-ups the engine.
  ///
  /// Safe to call multiple times.
  Future<void> init();

  /// Releases resources owned by the current engine session.
  ///
  /// This may close sockets, HTTP sessions, tokens, or other temporary
  /// resources. The engine object itself remains reusable through [reopen].
  ///
  /// Safe to call while idle.
  Future<void> close();

  /// Reopens the engine after [close].
  ///
  /// Stateless engines should treat this as a no-op.
  ///
  /// This method is intentionally synchronous because reopening an engine
  /// represents invalidating local state, not waiting for network work.
  void reopen();

  /// Invalidates a persistent network/session connection.
  ///
  /// The next synthesis operation should establish a fresh session as needed.
  /// Retry/backoff policy remains owned by the engine.
  ///
  /// Stateless engines should leave the default implementation unchanged.
  void invalidateSession() {}

  /// Synthesizes [text] as one complete turn.
  ///
  /// A normal successful stream should:
  ///
  /// 1. emit zero or more [TtsAudioBytes] events,
  /// 2. emit zero or more [TtsWordBoundary] events,
  /// 3. emit exactly one [TtsTurnEnd].
  ///
  /// On failure it should emit [TtsSynthesisError] and terminate the stream.
  ///
  /// [rate] and [pitch] use engine-style strings such as `+10%` and `+0Hz`.
  Stream<TtsSynthesisEvent> synthesize(
    String text, {
    required String voiceId,
    required String rate,
    required String pitch,
    String? locale,
  });
}
