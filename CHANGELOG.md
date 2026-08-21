# Changelog

All notable changes to NovelDock are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com); versions aim for SemVer.

## Unreleased

### Fixed

- TTS skip forward/backward did nothing or killed playback: the restart pipeline refused to run because teardown flags were set in the wrong order. Rapid presses now accumulate into a single target, the synth session stays alive between skips, and skipping while paused re-positions silently instead of blaring audio
- Reading position was wiped on every novel reopen: saving chapter history deleted the stored resume anchor first. Anchors now survive across novels and app restarts in continuous mode
- Anchor restore could land at the top of long chapters or blank the screen entirely; restore now probes built content stepwise and settles on the nearest valid paragraph if the exact one no longer exists
- Novel detail chapter list flashed its skeleton on every rebuild because the stream was recreated each build
- Crash when reopening a novel in the same session (Riverpod self-dependency in the resume path)

### Changed

- Removed the dead Tracking placeholder from novel detail actions
- Cover image opens a pinch-zoom fullscreen viewer on tap

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
