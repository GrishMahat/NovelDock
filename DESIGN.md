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
- `VISUAL_DENSITY: 3` — generous spacing, one focal element per viewport.

## Color

- **Accent:** single seed `#356AE6` (`AppTheme.kAccentSeed`), user-changeable at runtime via theme settings. All UI color derives from the scheme — never hardcode hex in widgets. The static `kPrimary` is the *seed*, not the live accent; widgets must read `colorScheme.primary`.
- **Schemes:** light, dark, AMOLED (`AppTheme.light/dark/amoled`) via FlexColorScheme, level surfaces, blend 0. Dark elevation = lighter surface layers, never shadows.
- **Status colors** (Reading/Ongoing, Completed, Dropped, On Hold) come only from the `AppColors` ThemeExtension, tuned per brightness. Downloads "done" reuses `ongoing`; registry "unmaintained" reuses `onHold`.
- **Reader palette is exempt by design:** `kReaderBgColors` / `kReaderTextColors` own the prose look across themes (dark/light/sepia/green/blue) and do not follow the UI accent. Reader-scoped constants: `kReaderError`, `kReaderAccent` (links + TTS highlight), tuned to stay legible on every reader background.
- **Star ratings keep amber** (`Colors.amber`) as a recognized rating convention; nothing else uses a second accent.

## Typography

- Two families, bundled: **Sora** (all UI roles) + **Literata** (bodyLarge/Medium/Small).
- Scale and metrics live in `AppTheme._textTheme`. Never set `fontSize:` in widget code; use the nearest role and `copyWith` only for color/weight where a role cannot express it.
- Body height ≥ 1.4; headings ≥ 1.15.

## Tokens

- Spacing: `Insets` (4pt scale) — the only paddings/gaps that exist.
- Radii: one soft family via `Radii` (8/12/16, sheets 24). Bottom sheets always take their shape + drag handle from `bottomSheetTheme`; never draw manual handles or pass explicit shapes to `showModalBottomSheet`.
- Motion: `Motion.fast/base/enter/exit`. Exits faster than enters.
- Breakpoints: `Breakpoints.compact/medium/expanded`; desktop constants in `Desktop`.

## Layout

- Mobile: bottom `NavigationBar` (4 tabs). Desktop: custom rail + keyboard shortcuts. Never stretch phone layout wide; cap reading measure with `MaxWidthBox`/`Desktop.readerMaxWidth`.
- Lists >20 items are builder-based; no `shrinkWrap` scrollables inside viewports (bounded grids embedded in a scrolling column excepted).

## States

- Loading = skeleton matching final layout (`ShimmerGrid`/`ShimmerList`); no bare centered spinners on content screens.
- Empty/error = `EmptyState` / `ErrorView` with a next action; errors use `colorScheme.error`.
- Every icon-only button carries a tooltip.

## Decisions log

- 2026-08-25 — First contract written during the full polish pass. Fixed: EmptyState used `surface` as text color (invisible text); StatusChip hardcoded green/red ignoring AppColors; TTS mini player used seed instead of live accent; duplicate drag handles on all bottom sheets (theme owns them now); library status menu unified into StatusPickerSheet; stray `Colors.*` swept to scheme roles across downloads/import/logs/providers/browse/search; shimmer placeholders de-shrinkwrapped; inline font sizes/radii in shared widgets replaced with type-scale roles. Reader internals (prose geometry, TTS highlight alphas) intentionally keep local values; reader owns its look.
