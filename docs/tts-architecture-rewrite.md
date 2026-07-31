# TTS Architecture Rewrite — Plan

Status: **draft** · Last updated: 2026-07-31 (v2 — fork-integrated)

## Goals

- Stream synthesized audio directly from the Edge TTS WebSocket into a player — **no temp files, no per-chunk players**
- One persistent WebSocket per TTS session (send chunk texts over time on one connection)
- Smart, paragraph-aligned chunking with duration targets (soft limits)
- Library-based media controls (audio_service + anni_mpris_service); delete hand-rolled notification code
- Engine abstraction: add an engine = write one file
- **Less code overall**

## Non-goals (post-V1)

- Google/system TTS + ElevenLabs engines (abstraction designed for them now, implemented later)
- Settings model overhaul (current reader_tts_tab stays as-is)

## Decisions (confirmed with user)

| Topic | Decision |
|---|---|
| Player | just_audio everywhere; `just_audio_media_kit` backend on Linux/Windows; Android/iOS use just_audio native (ExoPlayer/AVPlayer) — no libmpv on Android |
| Media controller | audio_service (mobile) + anni_mpris_service (Linux) |
| WebSocket | **Our fork** (`GrishMahat/flutter_edge_tts`) — `EdgeTtsSession` already implements the persistent client; live-tested end-to-end. **No app-side protocol code.** |
| Dependency | git dependency pinned to fork tag `v0.0.3`; upgrade = tag on the fork + bump `ref` in pubspec — never `ref: main` (a broken main commit must not break the app) |
| Prefetch | Look-ahead 4–6 chunks, configurable variable (`ttsPrefetchWindow`, default 4) |
| Chunking | Paragraph-aligned, duration-based with soft limits (12–15s target, 20s soft max, 1800–2000 char hard max); split order: sentence → comma/clause → hard char |
| Settings | Not changed now (post-V1) |

---

## Part 1: What's wrong today (with receipts)

| Problem | Where | Detail |
|---|---|---|
| **Temp-file stage** | `lib/core/tts/microsoft_tts_provider.dart:191-193` | Each chunk's bytes are written to `tts_chunk_$i.mp3`, then `Player.open(Media('file://...'))` plays the file. Adds disk I/O, a full MP3 write+read roundtrip, and per-chunk file management (`_cleanupTempFiles`). |
| **One player per chunk** | `microsoft_tts_provider.dart:210-259` | New media_kit `Player()` per chunk, disposed after. No gapless continuity, heavy native objects churned constantly. |
| **One WebSocket per chunk** | `microsoft_tts_provider.dart:81-86` | `FlutterEdgeTts(...)` constructed per chunk → package opens a new socket per `synthesizeStream` call and closes it at `turn.end`. Chunk-to-chunk overhead = full TLS handshake + token exchange each time. |
| **Look-ahead of 10, buffered fully** | `microsoft_tts_provider.dart:138` `_lookAheadCount = 10` | Each `_SynthResult` holds complete `audioBytes` in memory; 10 chunks × ~100KB+ all retained. |
| **50ms polling for word highlight** | `microsoft_tts_provider.dart:227-247` | `player.state.position` polled every 50ms, binary-search over word timings. Jittery, CPU-wasteful — metadata already gives exact timing. |
| **Audio starts late** | `microsoft_tts_provider.dart:97-134` | A chunk only plays after its *entire* stream is collected into `BytesBuilder` and written to disk — no first-bytes-latency. |
| **Stub media controller** | `lib/core/tts/background_audio_handler.dart:76` | `seek()` is empty; position is *extrapolated* from chunk index (`tts_manager.dart:157-159`), not real. |
| **Duplicate notification systems** | `tts_notification.dart` + `background_audio_handler.dart` | Two Android notification stacks updated in parallel (`tts_manager.dart:149-178`). |
| **Dead HTML path** | `html_chunker.dart`, `tts_highlighter.dart`, `tts_manager.dart:220` | `startFromHtml` is never called anywhere (only its definition). `HtmlChunker`/`TtsHighlighter` serve the pre-markdown reader; `md_renderer.dart:391` does live RichText highlighting now. |
| **`updateMediaInfo` fakes position** | `tts_manager.dart:157-159` | `Duration(seconds: totalDuration × chunkIndex / totalChunks)` — fake progress in lock-screen. |
| **Voice picker spawns its own provider** | `lib/features/settings/pages/reader/reader_tts_tab.dart:159` | `_VoicePickerSheetState` creates a private `MicrosoftTtsProvider` for samples — engine bypass in UI. |
| **Android libmpv** | `lib/main.dart:24`, `pubspec.yaml:77-79` | `MediaKit.ensureInitialized()` with only `media_kit_libs_linux` — **`media_kit_libs_android_audio` is missing from pubspec**, which caused `Cannot find libmpv.so` on device. |

---

## Part 2: Edge TTS protocol — implemented in our fork (zero app-side protocol code)

We are **not** using the official Azure Speech SDK, and **not** the published pub.dev
`flutter_edge_tts` package. We run **our own fork** of `Moosphan/flutter_edge_tts`:
`GrishMahat/flutter_edge_tts`, pinned as a git dependency **by tag** (`v0.0.3`), never by
branch. The fork is MIT, self-contained, and carries no third-party attribution that could
drag in other license terms (the upstream Python implementation was consulted as reference
only; no references to it remain anywhere in the fork).

The fork already contains the complete persistent-socket client (`EdgeTtsSession`),
**live-tested**: one socket for many turns, multi-frame turns, word/sentence boundary
metadata with offset compensation, and SRT/VTT subtitle output. The protocol details below
are kept for debugging only — the app never builds a socket, token, or frame by hand.

### Fork versioning workflow

```
edit fork → flutter test (fork) → git tag v0.0.4 && git push origin v0.0.4
app: pubspec.yaml ref: v0.0.3 → v0.0.4 → flutter pub get
```

`pubspec.lock` pins the tag's `resolved-ref` (commit SHA), so builds are reproducible.

### New fork APIs (v0.0.3)

All exported from `package:flutter_edge_tts/flutter_edge_tts.dart`.

**`EdgeTtsSession` — the persistent client** (`lib/src/edge_tts_session.dart`)

```dart
final session = EdgeTtsSession(
  voice: 'en-US-BrianMultilingualNeural',
  outputFormat: EdgeTtsOutputFormat.audio24Khz96KbitrateMonoMp3,
  enableWordBoundary: true,
  connectionTimeout: const Duration(seconds: 20),
);
await session.connect();                 // opens socket + sends speech.config (idempotent; regenerates Sec-MS-GEC)
session.isConnected;                     // true while socket is open
final stream = session.synthesize(text); // one turn: audio chunks + boundary events; socket stays open
await session.close();                   // idempotent
```

- Text > 4096 escaped bytes is **auto-split** into sequential SSML frames on the same socket
  (`EdgeTtsUtils.splitTextByByteLength`); word-boundary offsets are **compensated** across
  frames (CBR byte→tick math) so timings stay aligned with the audio.
- Boundary text is unescaped (`&lt;3` → `<3`).
- **No auto-reconnect**: on socket error the active turn's stream fails; the app must
  `connect()` again (fresh connection = fresh token) and re-synthesize the chunk.
- Extra entry points for custom framing: `synthesizeSsml(ssml)` and
  `synthesizeSsmlParts(List<String> ssmlParts)` (applies compensation/unescape to any
  multi-frame turn — useful for future chunking variants).
- Events: `EdgeTtsAudioChunkEvent`, `EdgeTtsMetadataEvent` (items: `WordBoundary`/
  `SentenceBoundary` with `offset`/`duration` in 100 ns ticks, `text`).

**`EdgeTtsUtils`** — `xmlEscape`, `xmlUnescape`, `splitTextByByteLength(text, bytes)`
(space/newline-preferring, UTF-8-safe, entity-safe). Public for advanced use (custom
chunkers that must respect the 4096-byte cap).

**`EdgeTtsSubMaker` — subtitles from metadata** (`lib/src/submaker/edge_tts_submaker.dart`)

```dart
final submaker = EdgeTtsSubMaker();            // word boundaries only, or sentence boundaries only
await for (final event in session.synthesize(text)) {
  if (event is EdgeTtsMetadataEvent) {
    for (final item in event.metadata.items) submaker.feed(item);
  }
}
final srt = submaker.srt;                      // ready-to-write SRT
final vtt = submaker.vtt;                      // with WEBVTT header
```

Also `composeSrt(List<EdgeTtsSubtitle>)` / `composeVtt(...)` for direct composition
(sort + reindex + skip invalid cues). 

### Endpoint (built per connection)

```
wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1
  ?TrustedClientToken=6A5AA1D4EAFF4E9FB37E23D68491D6F4
  &Sec-MS-GEC=<32 hex>
  &Sec-MS-GEC-Version=1-143.0.3650.75
  &ConnectionId=<32 hex>
```

### Sec-MS-GEC

`SHA256hex("${windowsTicks}${trustedClientToken}").toUpperCase()` where
`windowsTicks = ((unixSeconds + 11644473600) - ((unixSeconds + 11644473600) % 300)) × 10^7`
(ticks rounded down to 5-minute window).

### Upgrade request headers

- Browser UA: `Mozilla/5.0 ... Edg/143.0.0.0`
- `Origin: chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold`
- `Cookie: muid=<32 hex upper>`
- `Sec-WebSocket-Extensions: permessage-deflate; client_max_window_bits`

Dart: raw `HttpClient.openUrl` → `WebSocket.fromUpgradedSocket`. Keep `socket.pingInterval = 30s` keepalive.

### Frame 1 — `speech.config` (once per connection, JSON payload)

```
X-Timestamp:Sat Jan 01 2026 12:00:00 GMT+0000 (Coordinated Universal Time)\r\n
Content-Type:application/json; charset=utf-8\r\n
Path:speech.config\r\n\r\n
{"context":{"synthesis":{"audio":{"metadataoptions":{
  "sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"true"},
  "outputFormat":"audio-24khz-96kbitrate-mono-mp3"}}}}
```

**`wordBoundaryEnabled: true` is the key flag** — it gives exact word timings.

### Frame 2..N — one `ssml` per chunk

```
X-RequestId:<32 hex>\r\n
Content-Type:application/ssml+xml\r\n
X-Timestamp:<...>Z\r\n
Path:ssml\r\n\r\n
<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xmlns:mstts="https://www.w3.org/2001/mstts" xml:lang="en-US">
  <voice name="en-US-BrianMultilingualNeural">
    <prosody pitch="+0Hz" rate="+10%" volume="100">escaped text</prosody>
  </voice>
</speak>
```

- Text is XML-escaped (`& < > " '`).
- Prosody mapping (kept from current code, `microsoft_tts_provider.dart:88-91`): `rate = ±(speed-1)*100%`, `pitch = ±(pitch-1)*50%`.

### Server → client frames (text and binary interleaved; one listener)

- `Path:turn.start` / `Path:response` — ignore (log)
- **audio**: binary frame with `Path:audio\r\n` prefix + raw MP3 bytes → strip prefix, forward to player
- `Path:audio.metadata` — JSON after `\r\n\r\n`:
  `{"Metadata":[{"Type":"WordBoundary","Data":{"Offset":...,"Duration":...,"text":{"Text":"...","Length":...,"BoundaryType":"WordBoundary"}}}]}`
  - **Offset/Duration in 100-nanosecond ticks, relative to turn start** → `ms = ticks / 10000`
- `Path:turn.end` — turn finished

### The persistent model

After `turn.end` the socket stays alive. Send next chunk's `ssml` on the same socket; parse interleaved turns. Sequential turns (one in flight) — pipelining multiple ssml before turn.end is risky. Removes per-chunk TLS/token overhead entirely.

### Reconnect policy

On socket close/error → exponential backoff (0.5s → 1s → 2s → 4s, cap 10s), resend `speech.config`, re-send pending chunk. Mid-chunk turn failure → re-synthesize that chunk from the start.

### Audio format

Keep `audio-24khz-96kbitrate-mono-mp3`. MP3 frames are self-synchronizing, so consecutive chunks concatenate cleanly in one stream.

### Fallback insurance

Keep `flutter_edge_tts` in pubspec — its `synthesizeStream()` (per-chunk socket, still no temp files) is a ready fallback if Microsoft rotates the token/Sec-MS-GEC scheme (it has before).

---

## Part 3: Engine abstraction — the "one file per engine" contract

New: `lib/core/tts/engine/tts_engine.dart`

```dart
class TtsEngineVoice {
  final String id;        // 'en-US-BrianMultilingualNeural'
  final String name;      // display
  final String locale;    // 'en-US'
  final String? gender;
}

sealed class TtsSynthesisEvent {}
class TtsAudioBytes extends TtsSynthesisEvent { final Uint8List bytes; }
class TtsWordBoundary extends TtsSynthesisEvent { final String word; final Duration offset; final Duration duration; }  // normalized to ms
class TtsSynthesisError extends TtsSynthesisEvent { final Object error; final bool fatal; }
class TtsTurnEnd extends TtsSynthesisEvent {}

abstract class TtsEngine {
  String get id;                     // 'edge'
  String get displayName;            // 'Microsoft Edge TTS'
  bool get supportsWordBoundaries;   // edge: true
  bool get requiresNetwork;          // edge: true (system TTS: false)
  Future<List<TtsEngineVoice>> getVoices();
  Future<void> init();               // warm caches, connectivity check
  Stream<TtsSynthesisEvent> synthesize(
    String text, {
    required String voiceId,
    required String rate,        // '+10%'
    required String pitch,       // '+0Hz'
    String? locale,
  });
}
```

### Post-V1 engines

- **Google/system TTS**: `requiresNetwork=false`, `supportsWordBoundaries=false` → controller falls back to estimated pacing; voices from platform channel.
- **ElevenLabs**: HTTP POST streaming (`response.bodyBytes`), `supportsWordBoundaries=false`, own voice list + API key setting.
- One file implements the interface + registers in engine registry provider (`ttsEnginesProvider`, SharedPreferences key `tts_engine`, default `edge`). Everything downstream never touches engine internals.

### `EdgeTtsEngine` (new `engine/edge_tts_engine.dart`)

A **thin adapter — a wrapper is still needed, but only for lifecycle, not protocol**:

- Owns one `EdgeTtsSession` per engine instance (constructor with `enableWordBoundary:
  true`), `connect()` lazily on first synthesis.
- **Reconnect + re-synthesize** on failed turns: the session does *not* auto-reconnect
  (`EdgeTtsSession` throws/fails the turn's stream) — the engine backs off
  (0.5s → 1s → 2s → 4s, cap 10s), calls `connect()` (fresh `Sec-MS-GEC` token), and
  re-sends the chunk.
- Sequential turn queue (one synthesis in flight per session — the session's
  `_busy`/turn-end mechanism already enforces this).
- Voices: `FlutterEdgeTts.getVoices()` (HTTP `voices/list`; still in the fork).
- Fallback path (if Microsoft rotates the token scheme): wrap
  `FlutterEdgeTts.synthesizeStream` per chunk — no temp files, per-chunk socket.
- Converts stream events: audio bytes → `TtsAudioBytes`, boundary items → `TtsWordBoundary`
  (ticks → ms), turn end → `TtsTurnEnd`, socket error → `TtsSynthesisError(fatal: true)`.
- `synthesizeSsmlParts`/`EdgeTtsSubMaker` are not needed by the controller (boundary
  events carry everything); they're there for advanced use.

---

## Part 4: Smart chunker

New `lib/core/tts/chunker.dart` (replaces `TtsTextChunker` in `html_chunker.dart`; HTML parts deleted).

```dart
class TtsChunk {
  final int index;                // flat index in chunk list
  final int paragraphIndex;       // display paragraph (scroll/highlight sync)
  final int startOffset;          // char offset in paragraph plain text
  final int endOffset;
  final int paragraphWordOffset;  // word index of chunk start inside paragraph
  final int sentenceCount;
  final int estimatedDurationMs;  // length / charsPerSec / speed
  final String text;
}
```

**Input**: `List<String>` paragraphs — exactly what `reader_screen.dart:217-222` already builds from `MDParser.parse` (no HTML anywhere).

**Per-paragraph algorithm**:

1. Whole paragraph ≤ `targetMs` → one chunk.
2. Else split at **sentence boundaries** (`(?<=[.!?])\s+`, plus CJK `。！？`), greedily pack sentences until `softMaxMs` (20s).
3. Any single sentence > soft max → split at **clause boundaries** (`(?<=[,;:—–-])\s+` + CJK `、，；：`).
4. Last resort: **hard character split** at `hardMaxChars` (1800–2000), breaking only at the last space (never mid-word).

**Constants** (all tunable): `targetMs = 12–15s`, `softMaxMs = 20s`, `hardMaxChars = 1800–2000`, `charsPerSecond = 15` (matches current heuristic, `tts_manager.dart:243`). `estimatedDurationMs = text.length / charsPerSecond / speed × 1000` — per-engine rate override later.

**Consistency rule**: chunk boundaries land on sentence boundaries, so `md_renderer`'s `_findSentenceRange` (splits on `.!?` at `md_renderer.dart:406`) stays in sync — highlighted sentence == chunk content being spoken.

---

## Part 5: Streaming pipeline — `TtsPlaybackController`

New `lib/core/tts/controller.dart`. The heart of the rewrite.

**State**: chunk list, playhead index, prefetch window (`ttsPrefetchWindow`, default **4**, max 6), pending synth queue, word-metadata table per chunk, engine session, player, stall state.

**Loop**:

```
chunk N playing ──► on completion: emit onChunkCompleted(N+1)
                ──► synthesize N+1 .. N+prefetchWindow (engine, sequential turns, one socket)
                ──► audio bytes appended to TtsStreamSource; word boundaries stored per chunk
                ──► window slides; oldest synthesized chunks' buffers released
```

**Buffering model** (`tts_stream_source.dart`, new): `TtsStreamSource extends StreamAudioSource` wrapping a `StreamController<Uint8List>`; `request()` returns `sourceLength: null, contentLength: null` — **critical**: fixed lengths break dynamic streams ("Content size exceeds specified contentLength"). API: `addBytes()`, `closeStream()`.

**Pause/resume**: `player.pause()`/`play()` only — pipe keeps filling up to the prefetch window (bounded). Socket stays open.

**Stop**: close stream source, cancel in-flight synth, close socket, dispose player, clear buffers. Idempotent.

**Skip (forward/backward)**:

- *Default:* reuse the socket — send new `ssml`, ignore/drain the aborted turn's audio frames without feeding the player.
- *Fallback:* if Edge misbehaves on mid-turn switch, close + reconnect (≈1s).
- Previous-button semantics: first press restarts current chunk; second press goes to previous chunk.

**Network stall** (30s dropout scenario): audio in the player keeps playing as buffer drains → just_audio reports `buffering`/position stalls → controller waits `stallTimeout` (3–5s) → marks reconnecting → closes socket, backs off, re-synthesizes the stalled chunk → on first bytes, clears error and continues. 4–6 chunks × 12–20s ≈ 1–2 minutes of offline playtime, without 10-chunk memory bloat.

**Word highlighting**: chunk-relative time = `player.position − chunkStartTime` (accumulated chunk durations); word = last boundary with `offset ≤ elapsed`; fallback pacing (chars/rate) when `supportsWordBoundaries=false`. No polling — event-driven from metadata; 100–200ms ticker in fallback mode only.

---

## Part 6: Player layer

New `lib/core/tts/tts_player.dart`, thin wrapper around **one** `just_audio` `AudioPlayer` per session:

- `setAudioSource(TtsStreamSource)`, `play/pause/stop`, `positionStream`, `processingStateStream` (buffering detection), `setSpeed`.
- **Platform init** (`lib/main.dart:22-28`): replace `MediaKit.ensureInitialized()` with `JustAudioMediaKit.ensureInitialized(linux: true, windows: true)`. Android/iOS use just_audio native backends — no `media_kit_libs_android_audio`, no libmpv on Android. Keep `media_kit_libs_linux` + `media_kit_native_event_loop`.
- **Android manifest**: add `android:usesCleartextTraffic="true"` (or network-security-config permitting `127.0.0.1`) — required by just_audio's localhost HTTP proxy for `StreamAudioSource`. Not currently set (verified).
- Direct media_kit usage disappears (only `microsoft_tts_provider.dart` imports it).

---

## Part 7: Media controller layer

- **`background_audio_handler.dart`** — refactor, don't delete: keep `onPlay/onPause/onStop/onSkip*` wiring; **real** `seek()` (seek within current chunk via metadata; out-of-range = chunk skip); `updateMediaInfo` fed from real `positionStream`.
- **`tts_notification.dart`** — **delete**: audio_service's media notification (already wired at `tts_manager.dart:169-177`) replaces the `flutter_local_notifications` custom one.
- **`tts_mpris.dart`** — keep as-is (thin adapter over `anni_mpris_service`); remove duplicated `setCoverArt` download (share one cached cover path with audio_service).

---

## Part 8: `TtsManager` rewrite

- **State shape unchanged** (`TtsManagerState`, `tts_manager.dart:14-86`) — `md_renderer`, `reader_controls`, `reader_content_view`, `reader_screen` compile and behave identically.
- `startFromParagraphs(paragraphs, ...)` → chunker → controller → player. Notifications/media updates driven by controller events (chunk start, word, completion).
- Delete `startFromHtml` (dead), `_chunkTexts`/`_ttsChunks` double bookkeeping (chunker owns chunks; manager only tracks state).
- `getVoices()` and voice sample playback route through the active engine (`reader_tts_tab.dart:159`'s private `MicrosoftTtsProvider` becomes a shared `TtsPlayer` instance).
- **Auto-advance stays in the reader** (`reader_screen.dart:236`) — needs chapter loading/navigation which is UI territory; the controller just emits `onCompleted`.

---

## Part 9: File-by-file change list

### New

| File | Content |
|---|---|
| `lib/core/tts/engine/tts_engine.dart` | interface, voices, events (Part 3) |
| `lib/core/tts/engine/edge_tts_engine.dart` | thin `EdgeTtsSession` adapter: lifecycle, reconnect backoff, voices, fallback (Part 3) |
| `lib/core/tts/chunker.dart` | `TtsChunk` + split algorithm (Part 4) |
| `lib/core/tts/tts_stream_source.dart` | `StreamAudioSource` impl (Part 5) |
| `lib/core/tts/tts_player.dart` | just_audio wrapper (Part 6) |
| `lib/core/tts/controller.dart` | `TtsPlaybackController` (Part 5) |

### Modified

| File | Change |
|---|---|
| `lib/core/tts/tts_manager.dart` | use controller+engine; delete HTML path; real positions |
| `lib/core/tts/background_audio_handler.dart` | real seek/position, keep wiring |
| `lib/core/tts/tts_mpris.dart` | drop duplicated cover download |
| `lib/main.dart` | `JustAudioMediaKit.ensureInitialized`, remove direct `MediaKit` init |
| `pubspec.yaml` | + `just_audio ^0.10.6`, + `just_audio_media_kit ^2.1.0`; `flutter_edge_tts` → **git dep on fork, `ref: v0.0.3`** (fallback path lives inside the fork); keep `audio_service`, `anni_mpris_service`, `media_kit_libs_linux` |
| `android/.../AndroidManifest.xml` | `usesCleartextTraffic="true"` |
| `lib/features/settings/pages/reader/reader_tts_tab.dart` | sample playback via engine player |

### Deleted

`microsoft_tts_provider.dart`, `tts_notification.dart`, `tts_highlighter.dart`, `html_chunker.dart`, `startFromHtml`.

### Net LOC

Current TTS stack ≈ 1,300 lines → target ≈ 900–1,000 (engine 250 + controller 300 + chunker 150 + player/stream 120 + handler 80 + manager 250). The win is structural (no files, no per-chunk players, no duplicate notifications).

---

## Part 10: Verification

1. **Linux desktop**: TTS plays from live stream (kill network mid-play → audio continues from buffer → pause+reconnect state → resumes); MPRIS controls work; word highlight tracks exactly; no temp files.
2. **Android (connected Redmi)**: no `libmpv.so` error in logcat; playback via ExoPlayer; lock-screen/notification controls with real position; cleartext proxy works.
3. **Regression**: pause/resume, skip fwd/back (restart-chunk semantics), speed/pitch changes, auto-scroll ceiling, auto-advance, voice picker samples, highlight modes (paragraph/sentence/word).
4. **Stall**: airplane-mode test for 30s → buffer plays out → reconnects → resumes; 60s+ outage → clean error state, no crash.

---

## Open questions (implementation-time)

1. Skip mid-turn: socket reuse first, reconnect fallback — OK?
2. Prefetch window default 4 — OK?
