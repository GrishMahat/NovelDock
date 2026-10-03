# Changelog

All notable changes to NovelDock are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com); versions aim for SemVer.

## Unreleased

### Added

- Browse and in-source search results are cached. Opening a source's Popular or Latest tab used to be a cold network fetch plus HTML parse every single time; a repeat visit inside 30 minutes now renders from cache with no network round trip at all, and a stale entry still renders immediately while it refreshes behind the content. Cached pages are dropped when a source is updated or removed, since new provider code can change what a result page contains
- Settings → General → Storage: browse cache size and entry count, with a "Clear browse cache" action
- Chapter list: long-press a chapter for a row menu with "Mark earlier as read" and "Select from here down". Marks everything before the chapter you picked as read in one tap, for when you move a novel to another source that carries more chapters
- Downloads screen: completed downloads can now be removed one at a time, with a confirmation. Previously a finished download could only be cleared by wiping every completed entry at once
- Downloads screen: "Clear completed" deletes the saved files, not just the queue rows

### Changed

- Dependencies updated to their latest releases, including across major versions: `go_router` 17 → 18, `flex_color_scheme` 8 → 9, `shimmer` 3 → 4, `cached_network_image` 3 → 4, `file_picker` 12 → 13, `tray_manager` 0.5 → 0.7. App behaviour and appearance are unchanged; this is to pick up upstream fixes and stay on supported versions. The three forked git dependencies (`flutter_js`, `flutter_edge_tts`, `just_audio_media_kit`) stay pinned at their exact refs
- Linux TTS tray updated for the `tray_manager` 0.7 API. Same behaviour: the icon appears when playback starts, Pause/Resume tracks playback state, and it disappears when playback stops
- Novel detail: the dead "Soon" button is gone; library membership and the source page moved up beside the cover as inline actions
- Novel detail: chapter rows support selection. Long-press opens the row menu, or use "Select chapters" from the overflow. Bulk download, bookmark, mark read and mark unread apply to the picked chapters from a bottom action bar
- Novel detail: chapter sort moved into the chapter list header, where it belongs, instead of a second app bar icon
- Catalog tab lists only sources you have not installed; installed sources live in the Installed tab. The same source used to appear in both lists with two different toggle affordances
- Catalog: tapping a row installs or uninstalls it. Details moved to an explicit trailing button. Previously the row opened an info sheet while the switch beside it did the install, which made the switch feel like the only real control
- Mobile layout now adapts on its own terms instead of inheriting desktop metrics. Layout decisions moved from the `isDesktop` boolean to real width tiers (`compact` / `medium` / `expanded`), so a narrow desktop window and a large phone resolve to the same sensible layout
- Browse and search results: grid column counts are fixed per width tier and cards use a fixed height. Previously the count flipped between 2 and 3 columns across a 33dp width range, which put 120dp-wide cards with cropped covers on most phones
- Library grid: 3 covers per row on phones, shared column count with Browse so the two screens no longer disagree on the same device
- Browse catalog rows are ~35% shorter (72dp to 48dp) and show more sources per screen
- Chapter list rows are denser, with read state shown as a leading rule instead of an "Available" label
- Settings rows are denser with a single-line summary
- Browse opens in list view on phones and grid view on desktop (still toggleable)
- Reader settings are now per form factor: phones default to 16px text, 1.5 line height and 16dp margins, desktop keeps 17px / 1.6 / 24dp. Reader font and margin sliders are capped to ranges that keep the text measure readable on a phone, so desktop tuning no longer carries over
- Reader chapter breaks take less vertical space on phones
- UI text now uses lining figures. Literata defaulted to old-style figures, which put "Chapter 1" and "Chapter 2" at different heights and made chapter numbers read as borrowed glyphs

### Fixed

- App start no longer runs the full-library download reconcile immediately. It swept every novel's files in the first post-frame callback, blocking startup; it now starts after a short delay
- Browse "Installed" sources were unreachable below the fold on phones: the grid was a non-scrolling shrinkWrap column inside a bounded viewport, so any source past the first screenful could not be scrolled to. It was hidden on desktop only because the sources fit
- Large system font sizes no longer overflow the fixed-height grids and pills; text scale is clamped app-wide while still honoring large-text accessibility up to 1.3x
- The novel detail overflow menu no longer overflows by ~150px at every screen width. Popup items were a `Row` with no flexible child, so the label could not shrink to the popup route's clamped width

## 0.1.5-beta - 2026-09-30

### Added

- Filter-aware POST search: providers whose searchConfig declares (query, page, filters) now receive active search filters instead of the app skipping POST search when filters are set; WuxiaWorld 1.1.0 opts in (status/genre/sort flow into SearchNovels)

### Fixed

- Failed chapter refreshes no longer wipe stored chapters: an empty or truncated chapter-API walk (HTTP error, exception, page cap) skips the sync when the novel already has chapters instead of deleting them plus their history/queue/bookmarks/anchors; only a walk that reaches a true end-of-list signal may delete
- Chapter URLs with trailing slashes no longer silently disable the chapter-API fallback (book id is the last non-empty path segment minus extension/query/fragment)
- Reader Retry on a failed chapter actually refetches instead of no-oping on the cached error
- Re-importing the same EPUB/PDF reuses the novel row and preserves chapter identity, so history/bookmarks/downloads survive instead of being orphaned by replace-inserts
- Library status mix-up: the library sheet and novel detail screen now read membership status from the Library row instead of the novel's provider metadata (Ongoing/Completed); detail screen shows real membership with the current status pre-selected
- Backup/restore now round-trips library membership (status/order/anchors) and read/TTS progress, not just novels — restored novels reappear in the Library tab
- "Confirm before exit" setting is now honored: first back press on a top-level tab shows "Press back again to exit", second exits
- "Show NSFW Sources" off now actually hides 18+ extensions in Browse (Installed + Catalog), not just badges them; "Startup Tab" notes it needs a restart
- Provider `getOrderBys` no longer throws on JS-shaped maps (entry-wise string normalization); missing provider functions are logged at load instead of failing silently later
- Translation, TTS paragraphs, and annotation quotes share one paragraph-text rule (formatted runs flattened, not dropped) and one ordinal map, so read-aloud, highlights, and translation agree on paragraph identity
- Deleted dead surface: unused `render_seam.dart`, `postSearch`/`postBrowse` aliases
- Background 30-minute chapter sync no longer wipes stored chapters when the provider returns an empty list
- Bookmark adds and history restore are idempotent: reader double-taps and backup re-imports no longer stack duplicates
- Download reconciliation now clears corrupt downloaded flags with no file path, not just missing files
- Shared CoverImage handles local EPUB covers (file paths) everywhere — history, novel detail, library list/grid — instead of Image.network throwing on paths

## 0.1.4-beta - 2026-09-15

### Added

- Sleep timer for read-aloud: stop after 15/30/45/60/90 minutes or daily at a clock time (repeats every night, survives pause/stop, persists across restarts), from the Listen tab or reader settings Playback section
- Reader highlights: long-press any paragraph to highlight it or attach a note, reviewed per novel on its detail page, exportable as Markdown, and included in backups
- E-ink reader theme (pure black on white) with all reader motion disabled
- Clear site data in General settings (scraper cookies + in-app browser sessions)
- Auto-download the next chapters of Reading novels on Wi-Fi (Off/1/3/5/10 in Download settings)
- Cover monograms: novels without covers get a title-initial tile instead of a generic icon
- Reader "Show author notes" toggle (Display section, on by default like the original): hides translator author-note blocks when off; applies to online, EPUB, and newly downloaded chapters
- Chapter body images now send the scraper cookie jar (Cloudflare clearance cookies) so images on protected hosts load instead of failing; resolved per chapter at load time for online and downloaded chapters
- Novel detail chapter list gains status filter chips (All / Downloaded / Bookmarked / Read / Unread) with a match count and one-tap clear, mirroring the original's filter popup
- Library pull-to-refresh: swipe down re-fetches every novel on the current tab sequentially with a progress bar and a refreshed-count snackbar
- Reader volume-key scrolling (Android): opt-out setting (on by default, like the original) turns volume buttons into page turns via a thin MainActivity bridge; volume behaves normally everywhere else
- In-app update check: silent GitHub-releases poll once per launch (dialog + releases link only when newer), plus a manual "Check for updates" row in About
- Share/deep-link/shortcut intents end to end (Android): shared EPUB/PDF files actually arrive in Import now (the intent plumbing existed but nothing ever delivered the path); browser novel links for installed sources open the novel detail screen; `noveldock://` scheme backs static launcher shortcuts (Library, Browse, History, Downloads)
- Tests: full DAO CRUD suite (novel, library, history, downloads, bookmarks, settings, progress, provider cache), preprocessor + image-header + updater + deep-link-matching + chapter-sort + window-title unit tests, and widget tests for library, novel-detail filters/sort/loading states, and reader image headers (229 tests total)
- Novel detail sort is now Normal / Chapter number / Latest first — the alphabetic sorts are gone (lexicographic order put "Chapter 10" before "Chapter 2"). Number mode parses real chapter numbers so it works even on newest-first or jumbled listings; per-chapter upload dates would be ideal for the third mode but providers don't supply them, so it reverses provider order
- Search results rank by relevance within each provider row (exact > prefix > substring > token overlap > typo-tolerant similarity, ~50 lines, no dependencies); provider grouping is preserved
- Rating format setting (General): Stars (★ 4.3), 10-point (8.5), or 100-point (85) for the raw 0–1000 provider scores — the old bare "★ 850" is gone
- Remove Bloat toggle (reader Display section, on by default): translator/editor credit stripping is now optional instead of always-on
- Desktop title bar follows navigation ("NovelDock — Library/Browse/Reader/…")
- Linux system-tray icon for background TTS: appears while speaking with Show, Pause/Resume, and Stop playback actions; degrades silently without an indicator daemon
- Tray fix: the Linux native side only implements destroy/setIcon/setContextMenu, so the tooltip call threw MissingPluginException and aborted the menu setup — tooltip dropped on Linux and each tray step is now independently guarded

### Fixed

- One HTML intake pipeline again: the reader, EPUB loader, and download queue each ran a different preprocessor (two regex duplicates plus a dead DOM one nobody called, and downloads skipped cleaning entirely). All three now share `HtmlPreprocessor.clean` + `Html2Md.convert`, so downloaded chapters render identically to online ones. Side effects, all toward the original app's behavior: translator/editor credit blocks and ad chrome are now stripped everywhere, lazy-load images resolve, and `<center>`/`<font>` unwrapping no longer drops bare text. The dead `chapter_intake.dart` duplicate is deleted
- EPUB `keepCss` was a no-op: the HTML parser files `<style>`/`<link>` under `<head>` but only body HTML was returned, so embedded CSS never survived. Head styles are now re-attached when `keepCss` is set
- The chapter-level bookmark flag was write-only (`toggleBookmark` had zero callers), so nothing could ever show it. Adding a positioned bookmark now flags the chapter and deleting the last one clears it, which the new Bookmarked filter reads
- Share intents were half-wired: manifest filters and the `/import?file=` route existed, but no native code ever populated the path, so shares silently did nothing. MainActivity now copies shared content URIs to cache and forwards them (plus deep links and shortcut taps) over an intent channel
- Opening a novel with no cached chapters flashed a bogus "No chapters available" before anything loaded (the empty state won while the fetch was still idle, and detail screens opened from library/history never triggered a fetch at all). The detail screen now auto-fetches once when empty, shows the skeleton for idle-but-unstarted loads, and only shows the empty message after a fetch genuinely returns nothing; local imports are exempt. Also fixed `_refreshNovel` leaking the loading flag on its early return, which stuck the skeleton on forever
- Source pages no longer spin forever when the network is dead: they fail fast offline with the cause (no connection, timeout, server status) and a Retry button instead of an endless spinner
- Background chapter sync could delete surviving chapters (and their read/download/bookmark state) by passing only new URLs to the replace-semantics sync; it now sends the full server list. Stale deletes also clean up dependent history, queue, bookmark, and anchor rows in the same transaction instead of stranding them
- Re-importing an EPUB deleted and re-inserted every chapter, churning row ids and orphaning history/bookmarks/downloads; imports now diff-sync by URL like online refreshes
- Provider runtimes leaked on every load and registry update; invalidated instances now dispose their native JS context, and background syncs reuse the shared cached instance
- Provider JS ran with network access (fetch/XHR); runtimes are now network-less pure parsers (verified on-device), and invalidated instances dispose their native context instead of leaking. A heap cap and execution watchdog were attempted but the bundled native bridge exports neither symbol (verified on-device); isolate execution remains future work
- Registries were trusted blindly: remote fetches are now https-only, registry file paths are validated against directory escape, cached JS is hash-pinned at sync and verified on load, duplicate provider ids resolve deterministically (first-added registry wins, logged), and adding the same repo twice via different URL spellings is rejected
- Restoring a backup adopted its embedded source registries silently; the importer now lists them and asks before restoring (dismissal aborts the import)
- Restoring history/bookmarks/downloads reused source-database row ids that are meaningless in the target database, writing dangling rows; v2 backups carry novel/chapter URLs and the importer remaps them, skipping unresolvable rows with a count instead of corrupting (v1 files import novels/settings only)
- The in-app browser donated every site cookie (including login sessions) to the scraper jar; only Cloudflare clearance cookies (`cf_clearance`, `__cf_bm`) cross over now
- The download notification Cancel button did nothing (response handler was never registered); tapping Cancel now cancels the novel's downloads
- Queues interrupted by a killed app never resumed until the Downloads screen opened; stuck rows requeue and drain once per launch, after the first frame
- Download progress sat at 0% for whole transfers; per-chapter progress now reports in 10% steps to the queue tile and the notification, and cancelling aborts mid-transfer instead of at the next checkpoint
- Bulk downloads enqueued chapter-by-chapter with a progress recompute per chapter; ranges and select-all now batch in one pass
- Wi-Fi loss mid-queue failed every remaining task; the gate is rechecked per claim and the rest defer
- Tapping Listen while other audio played silently did nothing; a new request now steals cleanly after teardown. Skipping while paused no longer blips audio (muted transition)
- Voice previews synthesized through the live playback engine session; previews now use a dedicated engine instance that is closed with the picker
- Removed Paged reading mode, which silently broke resume anchors, bookmarks, and TTS follow; removed reader settings that were shown but never read (selectable text, clock/battery, orientation, scroll choice); Keep Screen On is now honored instead of unconditional
- Per-chapter load failures were dead ends with raw exception text; they now show a human message with Retry, and loading chapters shimmer instead of flashing a spinner
- Chapter links looked tappable but did nothing; they now open externally. Unrendered Word highlight mode removed from the options
- Screen-reader gaps: chapter turns and resume restores announce, covers are labeled, sliders/theme choices expose names and selected state, icon-only buttons have tooltips
- Translation cache keyed on the first 100 characters could serve one chapter's translation for another; keys are now exact, bounded, and saved atomically
- The Startup Tab and Library Default View settings had no effect; the app now opens on the configured tab and the library seeds (and persists) its display mode from the setting
- Settings screens could briefly show default values on cold start before persisted values loaded; preferences are now loaded before the first frame, so saved values render immediately
- The app logo rendered without its colors and logged an `unhandled element <style/>` SVG warning; the logo's CSS classes were inlined as presentation attributes

### Changed

- Backup format is now v2 (URL-keyed history/bookmarks/annotations/downloads); v1 files still import (novels and settings)
- The provider/registry provider module moved from `features/settings/providers/` to `lib/core/providers/registries.dart` (same provider names); core no longer imports from features
- Per-novel/per-chapter provider families (reading progress, reader navigation, fetch state, chapter translation) now dispose with their screen instead of living forever; the log stream emits on write instead of polling 5 times a second
- Library, history, and downloads screens memoize their streams/futures instead of resubscribing per rebuild; download progress aggregates use COUNT queries instead of full-table scans
- Download queue state restores once per launch; notification permission is asked once per download run instead of per task
- Media notification reports the real TTS speed instead of hardcoded 1.0x
- All Riverpod providers were migrated from manual definitions to `@riverpod` codegen (riverpod_generator); no legacy `StateNotifierProvider`s remain. Provider behavior is unchanged
- Dependencies: safe `flutter pub upgrade` batch (image 4.10.1, sqlite3 3.6.0, flutter_local_notifications 22.3.1, flutter_widget_from_html 0.17.4, file_picker 12.3.0, build_runner 2.16.1, analyzer 14.4.0, and transitive patches); drift/drift_dev 2.34 → 2.35 with codegen rebuilt (analyze clean, 229 tests pass); flutter_edge_tts v0.0.4 → v0.3.0 with the TTS engine/manager adapted to the new word-boundary duration and prosody-format APIs

## 0.1.3-beta - 2026-09-05

### Fixed

- TTS sentence highlighting could lag or select the wrong sentence, especially when a paragraph was split into multiple synthesis chunks; highlighting now follows the active chunk's actual text range
- TTS auto-scroll could miss the first target after a rebuild, and auto-advance could use stale reader state or fail during chapter handoff; the listener lifecycle, target retry, and next-chapter startup are now coordinated explicitly
- Restarting TTS could repeatedly download the same cover, and mobile media controls had no artwork; cover files are now shared through one in-flight cache and exposed to both Linux MPRIS and mobile media metadata
- TTS starting position could reset to the chapter top when the visible paragraph had not mounted yet; startup now uses the current scroll geometry as a fallback instead of silently choosing paragraph zero
- MPRIS initialization could race when media controls were initialized concurrently; initialization requests now share one future
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
