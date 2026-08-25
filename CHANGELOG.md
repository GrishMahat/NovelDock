# Changelog

All notable changes to NovelDock are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com); versions aim for SemVer.

## Unreleased

### Added

- Pluggable TTS engines: pick between Microsoft voices and on-device system voices (Android) in Reader settings. The voice list, sample previews, and playback all follow the active engine; the choice persists and falls back to Microsoft voices where system TTS is unavailable
- Download reconciliation: opening Downloads or a novel detail verifies download records against the files actually on disk

### Fixed

- TTS skip forward/backward did nothing or killed playback: the restart pipeline refused to run because teardown flags were set in the wrong order. Rapid presses now accumulate into a single target, the synth session stays alive between skips, and skipping while paused re-positions silently instead of blaring audio
- Reading position was wiped on every novel reopen: saving chapter history deleted the stored resume anchor first. Anchors now survive across novels and app restarts in continuous mode
- Anchor restore could land at the top of long chapters or blank the screen entirely; restore now probes built content stepwise and settles on the nearest valid paragraph if the exact one no longer exists
- Novel detail chapter list flashed its skeleton on every rebuild because the stream was recreated each build
- Crash when reopening a novel in the same session (Riverpod self-dependency in the resume path)
- Empty states drew their title in the background color, rendering it invisible
- Status chips used hardcoded green/red that ignored the app accent and lost contrast in dark mode
- Chapters kept their "downloaded" badge after their .md file was deleted outside the app; opening one now clears the stale flag, refetches from the source instead of erroring, and orphaned download files are cleaned up automatically
- Screen could sleep mid-chapter while reading; the display now stays awake until the reader closes
- Reader's initial load showed a bare spinner; it now shows a prose-shaped skeleton tinted to the active reader theme
- Chapter load failures offered only a low-emphasis text link; Retry is now a proper button styled for the reader theme
- TTS voice samples always played Microsoft audio regardless of the selected engine; previews now use whichever engine is active

### Changed

- Removed the dead Tracking placeholder from novel detail actions
- Cover image opens a pinch-zoom fullscreen viewer on tap
- UI polish pass: every screen now draws text sizes, spacing, radii, and colors from the shared theme tokens; hardcoded values were replaced with theme roles across library, browse, search results, downloads, history, import, logs, provider management, settings, and reader surfaces
- Bottom sheets take their shape and drag handle from the app theme; duplicate hand-drawn handles removed everywhere
- Library long-press and novel detail share one unified status picker (choose a status and Save, or Remove from library)
- TTS mini player, reader theme swatches, and font picker follow your chosen accent color instead of the default blue seed
- Copy tightening: "Wi-Fi Only" recased, the download concurrency row is now labeled "Parallel downloads"
- Added DESIGN.md recording the design contract: accent rules, Sora/Literata type scale, spacing/radius/motion tokens, and the reader palette exemption

## 0.1.0-beta - 2026-08-21

First public beta. Android APK plus Linux desktop packages, built and signed automatically by CI on every release tag.

### Added

- Multi-source browsing through installable JavaScript provider extensions, with a catalog for installing and updating them
- Library with status tabs (Reading, On Hold, Plan to Read, Completed, Dropped), grid/list/compact views, and per-tab filtering
- Reader with continuous and paged modes, five themes (dark, light, sepia, green, blue), adjustable typography, bionic reading
- Reading-position memory down to the content block, persisted while scrolling and restored on reopen
- Chapter tracking that marks chapters read when you advance or scroll past them
- Text-to-speech with paragraph highlighting, auto-advance across chapters, background playback, MPRIS media keys on Linux
- Download queue for offline reading
- Bookmarks and reading history
- Local EPUB and PDF import
- Backup and restore
- Linux desktop build: portable tarball, .deb, and .rpm packages with desktop entry
- CI: format check, analyzer, tests on every push; signed release builds on tags

### Fixed

- TTS chunker dropped separator whitespace when splitting long paragraphs, producing run-together words ("word wordword") and drifting highlight offsets
- Chunk word offsets were computed against the chunk itself instead of the paragraph, always reporting zero

### Changed

- Desktop navigation rail hosts Downloads next to Settings; screens own their headers
- Each screen renders a consistent header (title, search slot, contextual actions) with its tab strip underneath
