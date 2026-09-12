# NovelDock — Full Audit (2026-09-12)

Scope: entire repo (`lib/`, `android/`, `linux/`, tests, CI, docs) at the current
working tree, including uncommitted icon work. Method: five parallel deep-dives
(state management, data layer, TTS/downloads, reader/UI/accessibility,
JS-engine/network/security) plus manual verification of every P0 claim against
the code. Static analysis only, except startup timing measured on-device
(Redmi Note 13-class, debug APK: 15.6s to `Displayed`). No files were changed
for this audit.

One-line verdict: **a genuinely good reader buried under prototype-grade
resource discipline.** The product decisions are right (JS sources, chapter-row
identity, lazy startup, Markdown intake, persistent Edge socket) and the hard
pipelines (TTS, sync, search tokens) show real craft. But the app leaks a JS
runtime per provider load, a timer per novel visited, and unbounded provider
state; it has one live data-destruction bug, an unsigned code-distribution
channel with network-capable extensions, and a reader mode that silently
corrupts resume data. Fix P0 before any feature work.

---

## 1. Current state

What this is: ad-free novel reader/downloader (Android + Linux), Flutter +
Riverpod 3 codegen + Drift, installable JS source extensions via a quickjs-ng
fork, Edge + system TTS with read-aloud highlighting, offline downloads,
EPUB/PDF import, backup/restore. Early beta, single maintainer, fast-moving.

What actually works well today:

- Chapter sync by URL diff (`chapter_dao.dart`) with id/state preservation and
  the repo's only data-layer tests. This was a real destroy-everything bug,
  fixed correctly.
- TTS core loop: persistent Edge socket with generation guards, WAV-vs-MP3
  sniffing (load-bearing ExoPlayer fix), stall watchdog, premature-EOF
  handling, MPRIS on Linux, lazy `AudioService.init` on first play only.
- Central Dio client with retry + Cloudflare clearance handling; search
  request tokens; `NovelOpener` holding a provider-level `Ref` so background
  fetch outlives the screen.
- Startup discipline from 0.1.3 still holds: no eager notifications, media,
  provider assets, or background services. Measured cold-start cost is
  debug-build tax (JIT/AOT, VM service, dexopt), not a startup bug.
- DESIGN.md exists and app chrome mostly obeys it (single accent, AppColors,
  skeleton states, verb-first copy with no AI-cute strings).

Maturity snapshot: product ~70%, engineering ~45%. The gap is not features,
it is resource lifecycle, data safety, and trust boundaries.

---

## 2. P0 — fix before any feature work

### P0-1. Background sync deletes the chapter list it means to refresh (active data loss)

`lib/core/content/providers/reading_progress_provider.dart:157-173` builds
`chapterList` from **only URLs not already in the DB**, then passes it to
`syncChaptersForNovel`, whose contract is "URLs absent from the incoming list
are stale and get **deleted**" (`lib/core/database/daos/chapter_dao.dart:97-106,141-150`).
Normal refresh (server `[a,b,c]`, DB `[a,b]`) therefore deletes `a` and `b`
with all their read/download/bookmark state. The comment at `:160-162`
describes the old delete-all bug while the new code repeats the same mistake
in delta form. One-line fix: pass the full server list. Verified in code.

### P0-2. Import screen is the forbidden delete-all + re-insert (active data loss)

`lib/features/import/import_screen.dart:300-311` calls
`deleteChaptersForNovel` then inserts per chapter, no transaction. Violates the
repo's own rule (AGENTS.md) and the `syncChaptersForNovel` doc comment. Churns
autoincrement ids, orphaning every history/bookmark/download row keyed by
chapter id (FKs are declared but unenforced and uncascaded, see §4), destroys
flags, and a mid-import crash leaves a truncated list. Fix: reuse
`syncChaptersForNovel` (EPUB URLs are synthetic, URL-diff works) inside a
transaction.

### P0-3. Provider JS has unrestricted network access and no execution limits

`lib/core/providers/engine.dart:114` calls `getJavascriptRuntime()` with no
arguments; the pinned fork defaults to `xhr: true`, installing `fetch` +
`XMLHttpRequest` backed by its own Dart HTTP client, outside Dio, logging, and
cookie policy. `QuickJsRuntime2` supports timeout/memory caps; none are set.
`ProviderInstance.call` (`engine.dart:211-214`) is a synchronous blocking
`evaluate()` with no watchdog. A malicious or compromised provider can
exfiltrate queries/pages/chapter text to any host, mine, or `while(true)` the
UI isolate forever. Shipped providers are pure parsers today, so this is
latent capability, not active malice — but every third-party registry URL you
add activates it. Fix: `xhr: false`, stack/timeout/memory caps, evaluate off
the UI isolate (or at minimum a timeout that disposes and recreates the
runtime). The legitimate providers keep working; none use fetch/XHR.

### P0-4. Registry supply chain: unsigned code, HTTP-capable, file-write traversal

- No checksum/signature fields exist (`lib/core/providers/models.dart:1-97`);
  `_syncMetadata` (`lib/core/providers/registry.dart:203-293`) writes
  registry-controlled JS to disk on trust.
- `p.join(registryDir.path, provider.file)` / `provider.icon` use **raw
  registry strings** (`registry.dart:240-249`). The `_sanitizeId` helper exists
  (`lib/core/config/app_config.dart:129-135`) but is not applied here, so a
  `file: "../../evil.js"` escapes the registry dir on write. Genuine
  metadata-to-file-write traversal, reachable by any registry the user adds.
- No HTTPS enforcement (`registry.dart:411-462`, plus global
  `usesCleartextTraffic="true"` in `AndroidManifest.xml:12`).
- Flat provider-id merge across registries with last-modified-wins
  (`provider_management_providers.dart:139-165`, `registry.dart:319-367`):
  any enabled registry can shadow `royalroad` with its own JS, silently, on
  every path (search/browse/detail/download).
- Backup restore adopts `"registries"` URLs from arbitrary JSON files with a
  version check as the only gate (`backup_restore_page.dart:230-237`), then
  re-downloads JS from them. A shared backup file is a drive-by registry
  install chaining into P0-3/P0-4.
- Fix: `sha256` of exact JS bytes verified before write; reject `..`/absolute
  paths; key instances by `(registryId, providerId)`; enforce `https:` for
  remotes; scope cleartext down with a `networkSecurityConfig`; confirm-UI
  before adopting registries from a backup.

### P0-5. Translation cache returns wrong translations by key collision

`lib/core/translation/translation_service.dart:21-25`: cache key is
base64 of the **first 100 chars + lang pair**. Two chapters sharing a prefix
serve each other translations. Companion defect: `_saveCache()` rewrites the
whole JSON file per batch, unawaited (`:80,92`), so concurrent translates race
on the file. Fix: hash the full text (sha256, cheap) and write atomically.

### P0-6. Per-novel eternal timers (+ fresh JS runtime per sync, never disposed)

`reading_progress_provider.dart:63-73,113-120`: every visited novel spawns
`Timer.periodic(30min → syncWithServer)`. The provider is `keepAlive`, so
`onDispose` cancellation never runs. 20 novels = 20 immortal network pollers.
Worse, `syncWithServer` bypasses the shared instance cache and calls
`engine.loadProvider` directly (`:145`), appending a native QuickJS runtime
per sync that is never disposed (see §3). Fix: `autoDispose` (cancel already
written, just unreachable) or one app-level scheduler reusing cached
instances.

---

## 3. P1 — leaks, races, performance

### Resource leaks (the app's systemic disease: 41 of 42 providers are `keepAlive`)

- **JS runtimes leak on every load/update.** `_runtimes` only ever `add`s
  (`engine.dart:93-115`); `providerInstance` family entries are keepAlive
  (`engine.dart:612-633`); registry update/remove invalidates the instance
  **without disposing its runtime** (`provider_management_providers.dart:391,447,474`).
  Long sessions + updates = native memory growth. Fix: dispose on family
  eviction (`ref.onDispose` removing from `_runtimes`).
- **Reader state grows forever.** `contentProvider.chapters` map never evicts
  (`content_provider.dart:19-23,42-49`; `_cache` is LRU-20 but `state.chapters`
  is not; `clearCache()` at `:126` has zero callers). `readerNavigation`,
  `readingProgress`, `novelFetchState`, `chapterTranslation` families are
  per-novel/per-chapter keepAlive. Open 100 novels, keep 100 sessions.
  Fix: `autoDispose` families (+ small cacheTime), enforce eviction, call
  `clearCache` on reader dispose.
- **`AudioPlayer` never disposed; engine/MPRIS leak with it.**
  `TtsPlaybackController.disposeAsync` stops but never disposes the player
  (`controller.dart:1206-1240`; `TtsPlayer.dispose` has no callers);
  manager `onDispose` never closes the Edge socket; `TtsMpris.dispose` has no
  callers. Rare per session due to keepAlive, but every hot-restart/test leaks
  player + socket + MPRIS registration.
- **Download notification Cancel is dead.** `DownloadNotification.init()`
  creates the channel but nothing ever calls `plugin.initialize()` with the
  response handler (`main.dart` has no such init despite the comment at
  `download_notification.dart:49-51` claiming it does). The shade action fires
  into the void; the `onCancelRequest` bridge is wired but unreachable.
- **Killed-app queue never resumes.** `requeueStaleDownloading()` runs only
  from `DownloadsScreen.initState`. No startup hook, so rows sit in
  `'downloading'` forever after a process kill and the queue never restarts.
  (In-process downloads without WorkManager are defensible only with
  startup-resume; today you have neither kill-survival nor resume.)
- **Log viewer rebuilds 5×/sec forever.** `logBufferProvider` polls with
  `Stream.periodic(200ms)` + `.distinct()` on `List` identity (never filters),
  keepAlive, even with the log page closed. Fix: listener-backed broadcast +
  autoDispose.

### Races

- **Rapid chapter skip interleaves history/content writes**
  (`navigation_provider.dart:163-197`, `novel_opener.dart:63`): unawaited
  `_saveHistory`/`_loadCurrent`/fetch pipelines; history can point at a
  skipped chapter; double-tap races `syncChaptersForNovel`.
- **TTS start silently drops** (`tts_manager.dart:552-555`): returns
  immediately if speaking/paused; the manual skip path
  (`reader_screen.dart:578-644`) doesn't stop first, so old audio keeps
  playing over the new chapter. Needs a toast or steal-and-restart semantic.
- **Skip-while-paused blips audio** (`tts_manager.dart:738-761`): restart
  plays before the pause lands.
- **Reader auto-advance can touch `ref` after dispose**
  (`reader_screen.dart:771` unawaited, awaits `loadChapter` at `:720` after
  pop): use-after-dispose crash or writes into a dead scope.
- **Download cancel slot vs worker pool** (`download_provider.dart:65-68,181-195`):
  single `_currentTaskId` shared by up to 5 workers; cancel-tracking invariant
  is false under parallelism. (Actual cancellation works via row-deletion
  checkpoints, but there is no mid-transfer `CancelToken` and no
  `onReceiveProgress`, so progress bars sit at 0% for whole transfers and
  Wi-Fi loss fails every task instead of deferring; the gate is checked once
  per pool run, never per task, with no pause/resume API.)
- **Search has no per-provider timeout** (`search_providers.dart:557-707`,
  `Future.wait` at `:343-345`): one hung source stalls all sources.
- **Two truths for "where am I reading"**: `ReaderNavigation.currentIndex`
  vs `ReadingProgress.currentChapterIndex`, fed by different triggers, never
  reconciled. Merge them.

### Main-thread / rebuild storms

- **Reader rebuilds per TTS word.** `reader_screen.dart:906-911` watches four
  whole states; per-word emits rebuild everything including content maps
  (`:935-936`). Needs `.select()` on chunk/speaking/paused + highlight-only
  subtree. `ref.listen` inside `build` (`:917-928`) re-registers per rebuild.
- **Search rows watch the world** (`search_results_screen.dart:528`): one
  provider's page append rebuilds all rows. Needs `.select()`.
- **DAO objects watched instead of read** (`library_screen.dart:152-156`,
  `downloads_screen.dart:58,81-82,273-274`, `history_screen.dart:34-35`,
  `novel_detail_screen.dart:276-277`): 6 library streams where novel detail
  already shows the correct memoize-stream pattern (`:48,434-436`).
- **I/O as a side effect of `build`**: `availableProviders` re-syncs local
  registries from disk per rebuild (`:127-137`); `RegistriesNotifier.build`
  writes back (`:52-55`); settings/search/enabled-providers `_load()` async
  mutation post-build (transient-empty flash papered over with a `ready`
  Completer callers must remember to await — fragile contract).
- **Heavy sync work on UI isolate**: full-chapter `MDParser.parse` in TTS
  toggle/advance paths, system-TTS synth-to-file + read-back, `existsSync()`
  loops in reconcile, recursive tree walk for the storage card.

### Data layer (schema, queries, migrations)

- **FKs declared, never enforced or cascaded** (`tables.dart`, `database.dart:87-92`
  plain `NativeDatabase`, no `PRAGMA foreign_keys`): deletes never cascade,
  orphans accumulate; chapter stale-deletes (`chapter_dao.dart:141-150`)
  strand history/download/bookmark/`library.lastChapterId` rows. Either
  enforce + cascade or clean dependents in the same transaction (prefer the
  latter, explicit and testable).
- **Indices: effectively none** beyond UNIQUE auto-indexes. Every
  chapter-open probes (`reading_history.novelId`, queue status/novel/chapter,
  bookmarks, `novels.title LIKE` unescaped) full-scans at scale.
- **`settings` table has no key** (`tables.dart:81-84`): duplicate keys legal,
  `getSetting` returns arbitrary row, delete+insert races. One-line: PK on key.
- **N+1 everywhere hot**: `getLibraryNovels` (1+N), `getContinueReadingNovels`
  (~3N+1 full rows to test non-emptiness — use `EXISTS`/`COUNT`),
  `allReadingProgress` (N full chapter lists + N history probes),
  `_updateProgress` (loads ALL chapters + ALL downloads per task transition,
  filters in Dart), full-table-then-filter in cancel/delete/retry.
- **Unbounded streams**: `watchAllHistory`/`watchAllDownloads` no `LIMIT`;
  history screen dedups to latest-per-novel in Dart (push to SQL `GROUP BY`);
  `watchChaptersForNovel` re-emits all N full rows on any single-column touch
  (a single `markChapterAsRead` rebuilds 1000-chapter lists; no `selectOnly`
  projections exist anywhere).
- **Migrations**: v2 `onUpgrade` swallows errors per step
  (`database.dart:62-84`) so a half-applied migration still bumps the version
  permanently, with no retry, no log, no test (only fresh-create DAO test
  exists). Add `PRAGMA`/repair, real logging, and an upgrade-from-v1 test.
- **Reconcile is partial**: heals flag-false-on-missing-file but never
  flag-false-on-existing-file (wasted bytes + re-downloads), ignores
  non-numeric filenames, never validates `downloadedPath` scope. Read path
  heals separately (`content_provider.dart:70-78`), racing the flag clearing.
- **Backup/restore drops chapters/library/progress/JS**, imports without a
  transaction, collapses multi-row history via one-row-per-novel semantics,
  and reuses source-DB integer ids meaningless in the target DB (dangling
  refs). Decide: backup is metadata-only (say so, re-fetch on restore) or full
  (export chapters + remap ids).

---

## 4. Architecture critique (decisions, kept or challenged)

**Keep — these are right:**

- JS extensions over native parsers. Source coverage velocity demands it;
  the `register()` + helpers + `tool/provider-test` mirror harness is good
  design. The sandbox is missing (P0-3), the direction is not.
- Chapter rows are identity + URL-diff sync. Correct, tested, already fixed
  one destroy-everything bug. Finish compliance (P0-1/P0-2/F3 cleanup) rather
  than revisiting.
- Lazy startup (0.1.3 + current): audio, notifications, registry network all
  off the launch path. The 15.6s measured cold start is debug tax, verified in
  logcat phase by phase.
- Persistent Edge socket, synth-to-file bridge for system voices, Markdown
  intake over raw HTML/WebView (docs/WHY.md rationale holds; consistently
  applied). All pragmatic, all load-bearing, all keepable.
- `NovelOpener`'s provider-level `Ref` for background fetch. The one place
  the widget-vs-provider `Ref` rule is documented and obeyed — extend the
  pattern, don't regress it.

**Challenge — these cost more than they pay:**

- **`keepAlive: true` as house default (41/42 providers).** Codegen defaults to
  autoDispose for a reason. You opted the entire graph out of disposal, which
  turned every per-novel/per-chapter family, every timer, every JS runtime,
  every stream into a permanent resident. This single decision is the root of
  §3's leak list and the largest stability/battery win available. Policy:
  keepAlive only for true app singletons (DB, dio, prefs, engine host, TTS
  manager); everything session-scoped goes autoDispose with explicit cacheTime
  or LRU where continuity matters.
- **God providers.** `SearchNotifier` (~879 lines: orchestration + pagination +
  network fallback), `DownloadNotifier` (642: queue + transfer + notifications
  + FS repair), `TtsManager` (867: engines + settings + media + playback +
  highlight). Huge interface + huge implementation = low leverage per method,
  untestable without container+DB+network, and every invalidate rebuilds the
  world. Split along seams that already exist (`searchProviderOnce` is already
  a free function; queue-claim already lives in the DAO; reader nav vs
  progress already want merging in the opposite direction — one truth, not
  two).
- **Inverted layering at the worst spots.** Core imports features
  (`translation_provider.dart:4` → settings page,
  `md_renderer.dart:4` → reader settings state) and features import sideways
  (browse↔search↔settings, novel→browse/download, library→novel/settings).
  AGENTS.md says screens call into core, never the reverse; the violations sit
  exactly on the settings providers, which means settings owned by features
  but depended on by core. Move them to `lib/core/config/` or
  `lib/core/settings/` and route feature sharing through `core/`/`widgets/`.
- **Shallow-module sprawl.** 9 DAO one-liners + 7 prefs-wrapper settings
  notifiers + zero-logic service wrappers pass the deletion test negatively:
  deleting any one removes ~zero complexity. Collapse into one deep
  `SettingsRepository` (sync load in `main`, typed getters, debounced save,
  `select()`-friendly providers) and use the DB handle directly in DAOs.
- **Work-in-`build` reactive graph.** I/O, writes, timer creation, and
  provider re-syncs triggered by watching; coarse watches (whole search/TTS/
  content states, stable DAOs, notifier identity) fanning out into
  filesystem/network/rebuild storms on typing, scrolling, word ticks, and
  registry toggles. Make `availableProviders` pure (explicit refresh action),
  `read` stable handles, memoize streams, `.select()` hot consumers, and move
  `_load`-in-`build` to `AsyncNotifier`/`FutureProvider`.
- **Community registries as trust-on-first-URL.** The mechanism (cached
  metadata, multi-registry, offline-first) is fine; the trust model
  (unsigned, HTTP-ok, shadowable ids, backup-adopted URLs) makes it a
  code-distribution channel with paste-a-URL safety. Hashes + namespacing +
  https-only + consent UI make it defensible without losing velocity.
- **In-app-process downloads without the compensating half.** Dropping
  `flutter_background_service`/WorkManager is defensible for small chapters,
  but you also dropped resume-at-startup and never wired the notification
  actions, while still offering custom paths the manifest can't honor
  (no `MANAGE_EXTERNAL_STORAGE`/SAF; free-text path fails at write time).
  Either restore resume + wiring + path validation, or label downloads
  foreground-only and remove the custom path.
- **"ML Kit on-device translation" is documented but absent.** Pubspec
  declares `google_mlkit_translation`, README-adjacent copy claims on-device,
  zero call sites exist; real path is MyMemory cloud GETs with chapter text in
  URL query strings (proxy/CDN logs + cleartext on-disk cache). Either ship
  the ML Kit path or stop claiming it — and say plainly that default TTS
  (Edge) and translation (MyMemory) send chapter text to Microsoft/a public
  API. The no-analytics posture (verified: no firebase/crashlytics/sentry
  anywhere) is good and worth stating in-app.
- **Dead code and dead settings erode trust.** `html_chapter_view.dart`
  (unreferenced), theme's `bionicText` copy (md_renderer owns the live one),
  TTS **word** highlight selectable but unrendered, paged mode breaking
  resume/bookmarks/TTS-follow silently (either promote it or delete ~120
  lines), and four reader settings stored+shown+ignored (`selectableText`,
  `showTime`/`showBattery`, `orientation` vs forced portrait, `keepScreenOn`
  vs unconditional wakelock — the last one burns battery against explicit
  opt-out). Each is a promise the app breaks.

---

## 5. UI/UX, DESIGN.md compliance, accessibility

DESIGN.md verdict: **conditional pass.** Chrome obeyed the August contract;
reader-adjacent UI and several screens reintroduce swept violations.

- Typography/spacing/radii/motion letter-violations: `.fontSize` extracted
  from roles (`chapter_sheet.dart:184`, `novel_detail_screen.dart:721,737,847`,
  `reader_controls.dart:120,135`, …); raw dp literals instead of `Insets`
  (`reader_content_view.dart`, `shimmer_list.dart`, `log_viewer_page.dart`,
  `bookmark_sheet.dart`, …); off-contract radii (`circular(28)` pills,
  `circular(20)` fields, `circular(3/4/6/10)` sprawl — bless pills in DESIGN.md
  or tokenize); hardcoded durations bypassing `Motion`
  (`reader_screen.dart:406,426,453,480,552,569,706`); `Breakpoints` defined
  but never used (adaptivity is `isDesktop` boolean; 500px Linux windows and
  landscape phones fall through); reader mobile branch skips `MaxWidthBox`.
- States: bare centered spinners on next-chapter/paged/provider/search/webview/
  import paths (the file already imports `ShimmerBlock` — use it); per-chapter
  errors are dead ends showing raw `Exception:` strings with no retry;
  `novel_detail_screen.dart:745-756` trailing download button is a no-op that
  looks interactive; one user-visible em-dash (`webview_screen.dart:274-275`);
  `debugPrint` ships in the TTS path.
- Reader specifics: links styled but untappable (`md_renderer.dart:377-387`);
  block images second-class (no cache/loading/semantics, no block path);
  TTS paragraph extraction triplicated across two files (centralize
  `ttsParagraphs(doc)`; headings/lists never spoken); per-block GlobalKeys
  unbounded (2000-block chapters); scroll-spy capped at +3 chapters with
  unscaled 120px threshold; paged resume/bookmark/TTS-follow silently dead
  (decide its fate); chapter sidebar undiscoverable (28px mouse-only hover,
  no keyboard path) with ratio-scroll landing and shortcut-hijacked filter
  input.
- Accessibility (untested surface, real users affected): no `SemanticsService`
  announcements anywhere (chapter/TTS/download/import state changes silent);
  headings/lists/quotes expose no roles; sliders lack `semanticLabel`
  ("slider, 50%" — of what?); theme circles expose no selected state; covers
  unlabeled ("unlabeled image" with no title); icon-only deletes/clears/play
  missing tooltips; touch targets under 48dp (theme circles, compact deletes,
  64×36 rail pill); muted alphas down to 0.4 on information-bearing text
  (floor at 0.72); reduced-motion honored by exactly one widget; desktop
  shortcuts fire inside text fields (space toggles chrome mid-search);
  focus invisible and unordered. For an app whose audience includes
  dyslexic and read-aloud users, this is the largest unaddressed user-facing
  gap after P0.

---

## 6. Platform, build, startup

- Measured cold start (debug, Redmi-class): **15.6s to Displayed**, phase-split
  ~4.2s native/engine + ~9–11s Dart-JIT-before-first-frame + ~1.6s first
  raster. No network/service/DB stall present (DB opened in 25ms). Your 20s+
  is this tax plus first-install dexopt, on the debug APKs built for icon
  verification — not a regression of the 0.1.3 splash fix. Release/AOT
  removes nearly all of it. (Stayed on debug per your call; the concurrent
  prefs/docsdir trim in `main.dart` is in the tree, analyzer-clean.)
- Permissions: `FOREGROUND_SERVICE_DATA_SYNC` declared with no dataSync
  service in the manifest (dead or future — remove or add the service);
  `usesCleartextTraffic` global (scope it, §2 P0-4); everything else justified
  and refreshingly minimal (no storage/location/mic/contacts).
- `MainActivity` startup markers exist (native onCreate + plugin-registration
  timing) — keep them; they paid off in this audit.
- Linux desktop: `Desktop.minWindowWidth 960` saves layout; forced
  `portraitUp` + unconditional wakelock + no-op mpv/media hooks outside TTS
  are the platform debts to clear when touching reader settings.
- Branding fallout from the SVG/PNG divergence (logo.svg rounded-square large
  book vs logo.png circular ring design) is now structural: README, Linux
  icon, legacy Android icons follow the PNG; About page follows the SVG;
  adaptive foreground is a third simplified variant. Pick one mark and
  regenerate all surfaces from it.

---

## 7. Tests, CI, docs, process

- CI runs format + `--fatal-infos` + `flutter test`. Green, strict, good.
- Coverage is a thin shell: chunker, MIME sniff, locale tables, Markdown
  intake, one DAO test, one widget smoke. Everything concurrent (controller,
  manager, downloads, audio service, migrations, sync edge cases) lives only
  in manual on-device integration runs or nowhere. The live-network
  `edge_tts_engine_test` in the unit suite will flake offline — mark or mock
  it. Highest-ROI tests: migration v1→v2, `syncChaptersForNovel` stale-delete
  with dependents, translation cache keys, JS timeout/dispose, download
  claim/cancel/progress, search token cancellation.
- `tool/provider-test` mirror harness is a genuine asset; keep it in sync
  with `engine.dart` + search flows (it is the only executable spec of the
  provider contract — consider a `PROVIDER_CONTRACT.md` stating timeouts,
  allowed APIs (no fetch after P0-3), size caps, and error shapes).
- CHANGELOG discipline is good; AGENTS.md is load-bearing and specific
  (identity rule, TTS gotchas, codegen policy). Two repo rules are currently
  violated by the code (core↔feature imports, delete-all import path) — either
  enforce or amend.
- Git hygiene per AGENTS.md (no commit/push unasked) held throughout this
  session; the icon work + `main.dart` trim are uncommitted in the tree.

---

## 8. Flaws you made (direct, no padding)

1. **You defaulted the whole provider graph to `keepAlive: true`.** The single
   decision behind the timer leak, the runtime leak, the unbounded reader
   state, and the 5Hz ghost rebuilds. Codegen's autoDispose default was
   protecting you; you turned it off 41 times.
2. **You shipped the delta-as-full-list sync** (`reading_progress_provider.dart:163-173`)
   with a comment describing the exact bug class you then re-implemented.
   Reading your own comment would have caught it.
3. **You kept the fork's development defaults in production** (`xhr: true`, no
   caps, sync evaluate on UI thread). The threat model of "arbitrary community
   code with network" follows from one four-character omission at
   `engine.dart:114`.
4. **You built a trust-on-URL code channel** (unsigned, HTTP-ok, shadowable,
   backup-adoptable) while writing sanitizers and partial-sync guards that
   stop one directory short of the actual write. Security thinking is present;
   it is just never extended to the last mile where it matters.
5. **You expose settings that do nothing** (orientation, keepScreenOn,
   selectableText, word highlight, paged TTS-follow). Each passed review with
   UI but no reader wiring. A setting that lies is worse than a missing
   feature; the wakelock one costs battery.
6. **You let documentation drift from code**: ML Kit claimed but uncalled,
   DESIGN.md decisions log claiming sweeps the tree contradicts, `Breakpoints`
   defined and unused, notification-init comment pointing at code that does
   not exist, backup page promising restores the importer cannot perform.
7. **You test the easy parts.** Chunker, sniffing, locale tables — all
   valuable, all pure functions. The concurrent, stateful, lossy parts
   (sync, migrations, queue, TTS races, JS lifecycle) have no CI coverage,
   which is exactly where your P0s live.

None of this is fatal or unusual for a fast solo beta. But items 1–4 are the
kind that turn into 1-star reviews and incident responses ("my chapters
vanished", "my battery died", "this source stole my session"), so they go
before features.

---

## 9. Feature ideas (gated on P0; ordered by value/effort)

Near-term (small, high value):

- Startup-resume for downloads + wire notification init/actions (repairs C1/C2
  and converts the honest-foreground-downloads decision into a finished one).
- Retry on per-chapter errors + human error strings everywhere (biggest
  visible reader jank, reuses existing widgets).
- Reading stats (time read, chapters/day, streak) from existing history rows —
  nearly free, readers love it.
- Per-novel TTS voice + speed memory (state shape already exists).
- "Clear site data" action for the cookie jar (pairs with H4 hygiene fix).
- Cover fallback monograms (title-initial tiles) instead of book icons.
- True offline mode toggle (kills all network except cached; pairs with
  Wi-Fi-gate honesty).
- Sleep timer for TTS (chapter-end / 15-30-60min) — the most-requested
  audiobook feature archetype, trivial on your pipeline.

Mid-term:

- OPDS catalog support (libraries, Calibre): second source type beside JS
  registries, reuses loaders.
- Full-text search inside downloaded library (SQLite FTS over chapter cache).
- Annotations/highlights with export (Markdown file per novel — fits your
  Markdown intake beautifully).
- Reading goals + streaks UI on top of stats.
- Cloud sync adapter (WebDAV first, not Google Drive): history/progress JSON —
  your one-row-history + progress tables are already shaped for it.
- Auto-download next-N-chapters on Wi-Fi for Reading list.
- Provider health dashboard (latency, failure rate per source from existing
  logs) to route around dead sites.
- E-ink mode (pure black/white theme, no animation, paged-first): your paged
  mode decision (§5) is the prerequisite.

Far-term / strategic:

- iOS port honesty: pubspec claims `ios: true` for launcher icons but no
  `ios/` dir exists and generation crashes; either scaffold it or stop
  claiming it.
- Desktop (Windows/macOS) icon claims have the same code path — verify or
  drop.
- Signed registries + provider permissions manifest (`network: [hosts]`,
  `storage: none`, `timeoutMs`, `maxBytes`) shown in the install dialog —
  turns the extension ecosystem from a risk into a selling point.
- End-to-end encrypted backup (age/XChaCha) since backups are share-sheet
  exports containing library graphs.

---

## 10. Suggested order of work

1. P0-1, P0-2, dependent-cleanup-in-transaction, settings PK, FK/index pass
   (one data-safety release; add the migration + sync tests first so the fix
   is pinned).
2. P0-6 + JS dispose-on-evict + translation key fix (stop the growth; all
   small diffs).
3. P0-3 + P0-4 trust package (`xhr:false` + caps, sha256 verify, path reject,
   id namespacing, https-only, backup consent) + cookie hygiene. Ship as
   "extension security hardening" with a CHANGELOG entry users can see.
4. Disposal policy (`autoDispose` sweep) + reactive-graph pass (selects,
   memoized streams, pure `availableProviders`, broadcast log stream).
   This is where the jank and battery wins come from.
5. Download honesty (startup resume, notification wiring, real progress,
   per-claim Wi-Fi, CancelToken) + TTS ownership pass (disposals, preview
   isolation, no-silent-drop).
6. Reader correctness (paged fate, dead settings wired-or-removed, retry +
   human errors, shimmer everywhere, link taps) + accessibility pass
   (announcements, roles, labels, targets, contrast floor, motion gates).
7. DESIGN.md re-sweep against §5 list + one-mark branding unification.
8. Then features from §9, in order.

---

*Notes: line references are to the audited tree; flaws marked "verified in
code" were read directly, the rest carry agent-cited file:line evidence worth
a second look before scheduling. Nothing in this file changes behavior;
it is a map, not a patch.*

---

## 11. Fix program status (2026-09-12, same session)

All of §10 items 1–7 except branding unification and net-new features are
implemented in the working tree (uncommitted): P0-1/P0-2 call sites fixed with
dependent cleanup in-transaction; settings PK + hot-path indices + v3
migration with tests; eternal timers killed via autoDispose; JS runtimes
disposed on evict; translation keys exact/bounded/atomic; `xhr:false` + 30s
watchdog + 64MB cap; sha256 pin + verify; path rejection; https-only;
incumbent-wins resolution; resolved-URL dedupe; backup v2 + registry consent;
clearance-only cookie copy; notification response wiring; startup resume;
real progress + mid-transfer cancel + per-claim Wi-Fi gate; batch enqueue;
COUNT aggregates; TTS disposals + preview isolation + steal-start + muted
skip; real media speed; paged mode removed; dead settings removed (wired:
keepScreenOn); retry + human errors; link taps; dead code deleted;
announcements/labels/tooltips; contrast floors; copy nits. Registries module
moved to `lib/core/providers/registries.dart`. 147 unit tests green,
`flutter analyze --fatal-infos` clean, `dart format` clean.

Deliberately deferred (honest residuals, not oversights):

- Full widget-extraction to stop per-word full-reader rebuilds: per-word
  rebuilds are small (visible blocks only) and unmeasured as jank; the
  extraction is a dedicated refactor with regression risk.
- `_SearchRows` structural narrowing: transient-screen cost during active
  search only; parent + section selects applied where safe.
- Reduced-motion gates beyond `_ReaderEnter`; `Breakpoints` vs `isDesktop`;
  pill radii vs `Radii`; reader motion durations vs `Motion` tokens
  (all logged in DESIGN.md as known deviations).
- Registry authenticity beyond integrity (signatures), JS isolate execution,
  OPDS/FTS/annotations/sync adapters, sleep timer, stats — §9 stays
  feature-gated on owner approval.
- Branding unification (README PNG vs in-app SVG vs adaptive glyph): needs an
  owner call on which mark is canonical; surfaces documented, not renamed.
- Release-device validation of the caged JS runtime finished during the
  program: `xhr:false` verified working on-device (new
  `integration_test/provider_engine_smoke_test.dart` pins it); `memoryLimit`
  and the `timeout` watchdog do NOT exist in the bundled native bridge
  (`jsSetMemoryLimit: undefined symbol`, 30s watchdog never fired) and were
  removed again rather than kept as false confidence. Remaining hardening is
  isolate execution of provider JS.

