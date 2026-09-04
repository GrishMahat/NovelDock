# Changelog

All notable changes to NovelDock are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com); versions aim for SemVer.

## Unreleased

### Fixed

- In-app source pages could fail to transfer Cloudflare clearance cookies to chapter requests, and JavaScript challenge probes could remain active after a normal page loaded; cookie capture now follows the current page URL and challenge results are normalized before polling stops
- TTS playback could start at an unexpected speed because the selected speed was not applied before the first audio item; the speed is now set before playback begins
- TTS Stop could take several seconds to respond while audio and synthesis teardown completed; stopping now invalidates playback immediately and bounds cleanup time
- Read-along highlighting could drift or become visually unstable: sentence mode also emphasized a word, paragraph mode could miss its mapped paragraph, and word updates could trigger unnecessary visual work; sentence highlighting is now sentence-only and paragraph identity is mapped explicitly
- TTS auto-scroll could snap abruptly or repeatedly animate the same paragraph; scrolling now uses guarded smooth animations, with an optional setting to lock manual scrolling while listening
- Android cold start could remain on the splash screen for several seconds because download-service initialization was triggered during app startup; downloads no longer start a background service while the app is launching
- Android emitted a `flutter_background_service_android` main-isolate error and could start the foreground download service more than once; the unstable background-service integration was removed and download processing now stays in the app process
- Download notifications could race their initialization and be dropped or posted before the notification channel was ready; initialization is now shared, idempotent, and awaited before notifications are shown
- Library loading performed one database query per saved novel for each status tab; library streams now use a joined query, reducing database work during the first screen load

### Changed

- The in-app source browser now supports Android, iOS, Linux, Windows, and web through the cross-platform WebView implementation
- Startup no longer eagerly initializes notifications, media playback libraries, provider assets, or application paths; those resources initialize when their features are first used instead of delaying launch
- Android no longer explicitly opts out of Impeller, removing the deprecated renderer configuration and its startup warning
- The Android download queue no longer depends on `flutter_background_service`; queued downloads continue in the app process while the app is active. Background downloading while the app is closed will be revisited in a future version

### Known issues

- The upgraded HTTP/2 adapter can mishandle informational responses such as `103 Early Hints` on some servers, reporting a false response and then failing when the final response arrives. This is an upstream bug already tracked in an issue with a pull request under review; a future dependency update may resolve it

## 0.1.2-beta - 2026-08-30

### Added

- Reader settings sheet now has Reading and Listen tabs: engine, speed, pitch, language, voice, highlight granularity, auto-scroll, and auto-advance are all adjustable without leaving the book; future surfaces like translation can join as additional tabs
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
- Novel detail claimed "0 chapters" while the chapter list was still being fetched in the background; the skeleton now stays up until the fetch actually finishes, and a genuine empty result shows a "Check for chapters" action instead of a false zero count
- TTS auto-scroll and auto-advance toggles vanished from Settings during the reader settings rework; both now live in the Listen tab of Reader settings and in the in-reader sheet, backed by one shared language and voice picker implementation
- On-device TTS died seconds after starting ("Playback stalled"): device voices synthesize WAV while the playback pipeline labeled every chunk as MP3, so ExoPlayer treated the data as invalid, "finished" the playlist instantly, and burned all stall-restart attempts into a fatal error. Chunk payloads are now sniffed (RIFF/WAVE vs MPEG) and served with the matching content type
- Picking a device voice did nothing even when a voice was selected: Android reports TTS locales as `eng-USA`-style tags and flutter_tts's setVoice demands an exact match, but the app was sending `en-US`. Voice selection now resolves each discovered voice's original Android locale tag, so the chosen Google/device voice is actually applied during synthesis
- Device voices didn't appear when searching for "English (US)" in the voice picker for the same locale-format reason; picker locales are now normalized to `en-US`/`ru-RU` BCP-47 form (with 3-letter language and region codes mapped) so search and filtering match what users type
- Refreshing a novel destroyed per-chapter state: the chapter list was rebuilt by deleting every row and re-inserting, churning autoincrement ids, orphaning everything keyed by chapter id (reading history, download queue, bookmarks), and resetting read/TTS-read/downloaded flags. Chapter sync now diffs by URL — new chapters are inserted, existing ones keep their row and state in place, vanished ones are removed
- Reopening a novel clobbered refreshed metadata with stale search-listing data because the opener always re-fetched details in the background; the background re-fetch now runs only for new novels or ones with no chapters yet (the explicit Refresh action still always does)
- Searching immediately after a cold start silently queried zero providers: the enabled-providers set defaults to empty until the database load finishes, so an early search saw nothing. Searches now wait for the initial provider load to complete
- Re-adding a provider registry could create duplicate list entries when two different URLs normalize to the same registry id

### Changed

- Download notifications rebuilt: one grouped notification per novel instead of parallel downloads overwriting a single slot, a real progress bar (it previously sat at 0% forever), an ongoing flag so active downloads can't be swiped away by accident, a Cancel action button that routes into the download queue, failed-chapter counts in the body, and a tappable completion notice
- The background download service no longer mirrors every progress update into its own foreground-service notification, which duplicated the progress notification verbatim; it stays as a quiet status strip and disappears once the queue drains
- TTS player controls rebuilt as a proper media cluster on both surfaces: skips recede, play/pause becomes the single filled focal control (live accent in the top mini player, reader text tint in the floating reader pill), and stop sits behind a hairline with a quiet treatment instead of reading as a mystery gray square; rounded icon set and an inset, rounded progress line throughout
- Background novel fetches rebuilt around a session-scoped fetch-state provider: novel detail shows live fetching/refreshing progress instead of a skeleton flash or a false "0 chapters", and a fetch survives the screen that started it being disposed (provider-level Ref instead of widget-scoped)
- Download pipeline consolidated: the separate download manager was folded into the download provider, and notification Cancel actions wire directly into the download queue
- Registry additions run on a ProviderContainer, so adding a registry by URL survives the management page being closed mid-flight
- Provider instance loading centralized behind a single provider-instance provider instead of ad-hoc caching inside each loader
- Regression tests added for chapter sync, system TTS locale resolution, and the TTS stream source
- Removed the dead Tracking placeholder from novel detail actions
- Cover image opens a pinch-zoom fullscreen viewer on tap
- UI polish pass: every screen now draws text sizes, spacing, radii, and colors from the shared theme tokens; hardcoded values were replaced with theme roles across library, browse, search results, downloads, history, import, logs, provider management, settings, and reader surfaces
- Bottom sheets take their shape and drag handle from the app theme; duplicate hand-drawn handles removed everywhere
- Library long-press and novel detail share one unified status picker (choose a status and Save, or Remove from library)
- TTS mini player, reader theme swatches, and font picker follow your chosen accent color instead of the default blue seed
- Copy tightening: "Wi-Fi Only" recased, the download concurrency row is now labeled "Parallel downloads"
- Added DESIGN.md recording the design contract: accent rules, Sora/Literata type scale, spacing/radius/motion tokens, and the reader palette exemption

### Known issues

- **Android may be a little bit buggy right now.** The Android build is an early preview: on-device TTS, background downloads/notifications, and cold-start provider loading have had the most churn in this cycle and haven't been shaken out across many devices yet. Expect rough edges on Android specifically; desktop builds are more settled. If you hit something broken on Android, it's probably us, not you — please report it with the device and Android version.

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
