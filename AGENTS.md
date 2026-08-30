# NovelDock — agent & contributor guide

Practical map for AI coding agents (and humans) working in this repo. Read this before
changing code; it saves guessing.

## What this is

Flutter app (Android + Linux desktop): an ad-free novel reader/downloader with
installable JavaScript source extensions, TTS read-aloud, and EPUB/PDF import.
State is Riverpod 3 (manual providers, no codegen), persistence is Drift (SQLite).
License: GPL-3.0.

## Repo map — where to find things

| Path | What lives there |
|---|---|
| `lib/core/` | Platform-independent engine: `tts/` (engines, chunker, stream source), `database/` (Drift schema + DAOs), `providers/` (provider registry/engine — the JS extension host), `content/` (loaders), `network/`, `translation/`, `config/` |
| `lib/features/` | Screens, one folder per feature: `browse`, `library`, `reader`, `search`, `novel`, `downloads`, `history`, `import`, `settings`. Screens call into `core`, never the reverse |
| `lib/theme/`, `lib/router/`, `lib/widgets/` | Shared theme tokens, go_router setup, cross-feature widgets |
| `DESIGN.md` | Design contract (accent rules, type scale, spacing/radius/motion tokens). **Read before any UI work** |
| `noveldock-providers/` | Default provider registry data (registry.json + JS provider sources + icons) — not Dart code |
| `tool/provider-test` | CLI harness for testing a provider script without the app |
| `test/` | Unit/widget tests (`test/core/...` mirrors `lib/core`) |
| `integration_test/` | On-device diagnostics, mostly TTS pipeline loop/stall scenarios |
| `CHANGELOG.md` | Keep-a-Changelog format; add entries for user-visible changes |

## Commands (CI runs these — run them locally before handing off)

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .   # CI fails on unformatted code
flutter analyze --fatal-infos                        # CI treats infos as errors
flutter test
```

Drift codegen (after editing `lib/core/database/database.dart` tables/DAOs):
`dart run build_runner build --delete-conflicting-outputs` (config in `build.yaml`).
Generated `*.g.dart` files are excluded from the analyzer — never hand-edit them.

## Conventions & gotchas

- **Analyzer is strict**: CI runs `--fatal-infos`. Style-level lints count.
- **Riverpod 3 manual providers** — no `@riverpod` codegen. Providers that outlive a
  screen must hold a provider-level `Ref`, never a widget-scoped one (background
  fetches/searches must survive navigation; see `lib/core/providers/novel_opener.dart`).
- **Chapter rows are identity**: reading history, bookmarks, downloads, and read flags
  are keyed by chapter row id. Chapter lists must be synced via
  `ChapterDao.syncChaptersForNovel` (URL-diff), never delete-all + re-insert.
- **TTS pipeline is sensitive**: synthesis chunks are sniffed RIFF/WAVE vs MPEG before
  hitting the platform player; Android `play()` must not be awaited (it completes only
  when the playlist ends). If you touch `lib/core/tts/`, run the TTS tests.
- **Locale tags**: Android TTS reports `eng-USA`-style tags while most code uses
  BCP-47 `en-US`; normalization helpers live in the system TTS engine.
- **Git dependencies**: `flutter_edge_tts`, `just_audio_media_kit`, and `flutter_js`
  are maintained as forks (see README) and resolved automatically during `pub get`.
- **Secrets**: `android/key.properties` and `~/noveldock-keys/` hold release signing
  material. Never commit, never delete, never print. Local release builds fall back
  to debug signing when the file is absent — that APK will not pass Play registration.

## Git & releases

- Do not commit or push without an explicit request from the maintainer.
- Stage only files related to the current task; no blanket `git add -A`.
- Commit messages: short imperative summary line.
- Release builds are tag-driven: pushing `vX.Y.Z-beta` triggers the signed-build
  workflow. Never move or delete existing release tags.

