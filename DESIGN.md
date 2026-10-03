# DESIGN.md — NovelDock design contract

Standing agreement for all UI work. New work extends this; never contradict it silently.
When a decision changes, update this file in the same commit.

## Identity

- **App kind:** novel library + reader for Android and Linux desktop.
- **Register:** Expressive core (reader, library) with utility surfaces (settings, logs, provider management).
- **Style:** calm reader-first Material 3; the book is the hero, chrome recedes.
- **Voice:** plain and specific. No exclamation marks, no AI-cute copy. Buttons are verb-first and outcome-specific ("Download range", not "OK").

## Dials

- `DESIGN_VARIANCE: 6` — consistent screen anatomy; composition lives in covers and typography, not per-screen art direction.
- `MOTION_INTENSITY: 5` — state-explaining motion only; durations from `Motion` tokens.
- `VISUAL_DENSITY: 3 (wide) / 1 (compact)` — one focal element per viewport on desktop; on phones density wins, because a phone viewport is the scarce resource. Compact rows are dense by default and a screen must show a useful amount of content, not one card per gesture.

## Color

- **Accent:** single seed `#356AE6` (`AppTheme.kAccentSeed`), user-changeable at runtime via theme settings. All UI color derives from the scheme — never hardcode hex in widgets. The static `kPrimary` is the *seed*, not the live accent; widgets must read `colorScheme.primary`.
- **Schemes:** light, dark, AMOLED (`AppTheme.light/dark/amoled`) via FlexColorScheme, level surfaces, blend 0. Dark elevation = lighter surface layers, never shadows.
- **Status colors** (Reading/Ongoing, Completed, Dropped, On Hold) come only from the `AppColors` ThemeExtension, tuned per brightness. Downloads "done" reuses `ongoing`; registry "unmaintained" reuses `onHold`.
- **Reader palette is exempt by design:** `kReaderBgColors` / `kReaderTextColors` own the prose look across themes (dark/light/sepia/green/blue) and do not follow the UI accent. Reader-scoped constants: `kReaderError`, `kReaderAccent` (links + TTS highlight), tuned to stay legible on every reader background.
- **Star ratings keep amber** (`Colors.amber`) as a recognized rating convention; nothing else uses a second accent.

- One action per row. A row's tap target is its primary action; secondary actions go behind an explicit, labelled trailing control. Never let a row tap and a switch beside it do different things — it makes the switch feel like the only real control and the row feel broken.
- Each list owns its contents exactly once. If a tab already shows "installed" things, no other tab re-lists them.
- Popup menu items put the label in a flexible slot (`Expanded` + ellipsis). A `Row` of non-flexible children cannot shrink, and popup routes clamp their width.
- Bulk actions over a selection live in a bottom bar, not the app bar: the title row cannot spare the width, and on a phone the bottom is where the thumb is.
- Selections resolve against what the user can currently see (the active filter), not the whole underlying set.

## Typography

- Two families, bundled: **Sora** (all UI roles) + **Literata** (bodyLarge/Medium/Small).
- Scale and metrics live in `AppTheme._textTheme`. Never set `fontSize:` in widget code; use the nearest role and `copyWith` only for color/weight where a role cannot express it.
- Body height ≥ 1.4; headings ≥ 1.15.
- UI text uses **lining figures**; numerals in labels and chapter names get `tabularFigures` so columns align. Literata defaults to old-style figures, which reads as mismatched glyph heights in running UI text. Reader prose is exempt — it owns its own look.

## Tokens

- Spacing: `Insets` (4pt scale) — the only paddings/gaps that exist.
- Radii: one soft family via `Radii` (8/12/16, sheets 24). Bottom sheets always take their shape + drag handle from `bottomSheetTheme`; never draw manual handles or pass explicit shapes to `showModalBottomSheet`.
- Motion: `Motion.fast/base/enter/exit`. Exits faster than enters.
- Breakpoints: `Breakpoints.compact/medium/expanded`; desktop constants in `Desktop`.

## Layout

- Mobile: bottom `NavigationBar` (4 tabs). Desktop: custom rail + keyboard shortcuts. Never stretch phone layout wide; cap reading measure with `MaxWidthBox`/`Desktop.readerMaxWidth`.
- Lists >20 items are builder-based; no `shrinkWrap` scrollables inside viewports (bounded grids embedded in a scrolling column excepted).

### Adaptivity

- Layout decisions use `screenSizeOf(context)` (`ScreenSize.compact/medium/expanded`), not the `isDesktop` boolean. `isDesktop` stays for genuinely platform-bound behavior (window management, tray, system fonts, process spawning) — never for column counts, row heights, or padding.
- `Breakpoints` are the **lower** bound of each tier. Every phone width (320-480dp) is `compact`; a half-screen desktop window is `medium`.
- Grid column counts come from `Grids` and are **fixed per tier**. Never derive them from `maxCrossAxisExtent`: it flips count across a 33dp width range and lands phones on unusable ~120dp cards. Card heights use `mainAxisExtent`, not `childAspectRatio`, so a column change never squeezes the text block.
- Dense content lists (catalog rows, chapter rows, settings rows) set `dense: true` on compact. A themed `ListTile` with a trailing `Switch` measures 72dp; compact rows target ≤56dp.
- One action per row. A trailing control must not duplicate the row's own tap target.
- System text scale is clamped app-wide to 1.0-1.3 (`kMinTextScale`/`kMaxTextScale`) at the `MaterialApp` builder. Fixed-extent grids and fixed-height pills overflow without it.
- Reader settings are per-form-factor. Phones default to 16px / 1.5 line height / 16dp margins and clamp to a readable range; desktop keeps 17px / 1.6 / 24dp. `ReaderSettings.effectiveFontSize`/`effectivePaddingH`/`effectivePaddingV` are what render paths read — never the raw fields.

## States

- Loading = skeleton matching final layout (`ShimmerGrid`/`ShimmerList`); no bare centered spinners on content screens.
- Empty/error = `EmptyState` / `ErrorView` with a next action; errors use `colorScheme.error`.
- Every icon-only button carries a tooltip.

## Decisions log

- 2026-10-03 — Browse result cache. Every visit to a source's Popular/Latest tab was a cold network fetch plus HTML parse with no caching at all, which is what made "Popular" feel slow on a phone. Added a `browse_cache` table keyed by `providerId|mode|query|filterHash|page`, so an infinite list can be served fully from cache after the first visit. Two-tier freshness: inside `BrowseCacheDao.freshWindow` (30 min) an entry answers outright; past it the entry is still served but reported stale so the caller revalidates behind the content — stale content beats a spinner. Two rules the key must uphold, both covered by tests: changing a filter can never read another filter's page (hence the fingerprint), and `FilterValues` key order must not change the fingerprint (hence the recursive sort). Cache reads and writes never throw into the UI — the cache is an optimization, and a corrupt payload degrades to a miss. Registry updates/removals clear it, since updated provider code can change the result shape.
- 2026-10-02 — Novel detail, catalog and downloads pass. Removed the dead "Soon" action (onTap was `() {}`); library membership and the source page moved inline beside the cover instead of claiming a full-width action row; chapter sort moved into the chapter list header. Added chapter selection (long-press row menu, or overflow → Select chapters) with bulk download/bookmark/mark read/mark unread from a bottom bar, and "Mark earlier as read" for the cross-provider resume case. Catalog redesigned: the Installed section was deleted because the Installed tab already owns it, so the same source appeared twice with two toggle affordances; row tap now installs/uninstalls (the primary intent) with details behind an explicit trailing button. Downloads gained per-row removal for completed tasks, deleting the file and clearing the chapter flag instead of orphaning both; `markChapterAsUnread` added because only the forward direction existed and "mark unread" would otherwise have been a UI-only fiction.
- 2026-10-02 — Startup stall fixed. `reconcileDownloads()` ran across the entire library in the first post-frame callback, calling `File.existsSync()` per downloaded chapter on the UI isolate. With a real library that is thousands of blocking stat calls before the first interaction. Deferred behind a short grace period and switched to async `exists()`; the same safety net still runs, just not on the critical path.
- 2026-10-02 — Mobile density pass. The core finding: adaptivity was `isDesktop` only. `Breakpoints` was defined and never referenced, and exactly one `LayoutBuilder` existed in the app, so phones got desktop metrics with the rail swapped for a bottom bar. Introduced `ScreenSize` + `screenSizeOf` + `Grids`, and moved every column-count, row-height and padding decision onto them. Specific fixes: browse catalog rows 72dp → 48dp (removed an info `IconButton` whose tap target duplicated the row's own); browse installed-sources grid made scrollable (it was a bounded shrinkWrap column, so sources below the fold were unreachable on a phone — a real bug desktop hid) and 1-up → 2-up; browse/search grids moved off `maxCrossAxisExtent: 170`, which resolved to 2 columns at 360dp and 3 of 120dp at 393dp, flipping layout on a 33dp width change; library and search grids now share `Grids` so the screens agree per tier; chapter rows became dense InkWell rows with a read-state rule instead of 72dp ListTiles; settings tiles densified; system text scale clamped app-wide; reader settings split per form factor so desktop tuning no longer leaks to phones. Browse defaults to list view on phones. Added `test/widget/mobile_density_test.dart` to lock the phone geometry.
- 2026-09-12 — Audit fix program, UI surface. Removed Paged reading mode (it silently broke resume anchors, bookmarks, and TTS follow; continuous is the only mode). Removed dead reader settings that were stored and shown but never read (`selectableText`, `showTime`/`showBattery`, `orientation`, scroll-mode choice); `keepScreenOn` is now honored instead of unconditional. Reader loading rule now holds everywhere: next-chapter shimmer replaces the bare spinner, per-chapter errors get Retry + human strings (no `Exception:` verbatim). Deleted unreferenced `HtmlChapterView` and the duplicate theme `bionicText`. Every icon-only button carries a tooltip; covers expose `Cover of <title>` semantics; sliders expose value semantics; theme circles expose button+selected; chapter turns announce for screen readers. Reader muted-text floor raised (kicker/numbers/hints at 0.65-0.75). Copy register: no `sp` units, no H/V jargon, no em-dash in user strings.
- 2026-09-12 — Known remaining deviations (not yet swept): hardcoded millisecond durations in reader scroll/ensureVisible paths bypass `Motion` tokens; pill radii (`circular(18/28)`) and filter-field `circular(20)` live outside the `Radii` family; `Breakpoints` defined but adaptivity is still the `isDesktop` boolean; reader motion ignores reduced-motion settings except `_ReaderEnter`.

(2026-10-02: the `isDesktop` adaptivity deviation is resolved — see the decisions log. Remaining: hardcoded millisecond durations, pill radii outside the `Radii` family, reader reduced-motion coverage.)
- 2026-08-25 — First contract written during the full polish pass. Fixed: EmptyState used `surface` as text color (invisible text); StatusChip hardcoded green/red ignoring AppColors; TTS mini player used seed instead of live accent; duplicate drag handles on all bottom sheets (theme owns them now); library status menu unified into StatusPickerSheet; stray `Colors.*` swept to scheme roles across downloads/import/logs/providers/browse/search; shimmer placeholders de-shrinkwrapped; inline font sizes/radii in shared widgets replaced with type-scale roles. Reader internals (prose geometry, TTS highlight alphas) intentionally keep local values; reader owns its look.
- 2026-08-25 — Lever two: completed the type-scale sweep across all remaining screens (reader widgets + sheets, every settings page, browse/downloads/history/novel-detail/library items). All UI text now resolves through `_textTheme` roles; the only remaining literal is the reader code-block style (exempt). Every remaining `AppTheme.kPrimary` in widget code replaced with the live `colorScheme.primary` (the static seed is now referenced only by theme construction and the accent picker). Copy pass: no OK/Submit-style buttons, no AI-cute strings found; "Wi-Fi Only" recased, download "Limit" relabeled "Parallel", segmented-button label styles dropped in favor of component defaults.
