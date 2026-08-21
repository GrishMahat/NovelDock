# Changelog

All notable changes to NovelDock are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com); versions aim for SemVer.

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
