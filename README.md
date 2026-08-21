# NovelDock

Ad-free novel reader and downloader for Android and Linux desktop, built with Flutter.

Read web novels through installable JavaScript source extensions, import your own EPUB and PDF files, or listen to your library with text-to-speech.

> NovelDock hosts nothing. It renders whatever sources you install. Novels belong to their authors and publishers; support official releases when you can.

## Features

- **Sources**: install community JS providers from the catalog, then browse, search, and download
- **Library**: status tabs (Reading, On Hold, Plan to Read, Completed, Dropped) with grid, list, and compact views
- **Reader**: continuous or paged scrolling, five themes, adjustable typography, bionic reading mode
- **Resume**: reopens at the exact paragraph you left, even after a force close
- **Text-to-speech**: read aloud with paragraph highlighting, auto-advance across chapters, background playback, media keys (MPRIS on Linux)
- **Downloads**: queue chapters for offline reading
- **Translation**: on-device chapter translation via ML Kit
- **Bookmarks and history**: bookmark any position; history follows what you actually finished
- **Import**: open local EPUB and PDF files
- **Backup and restore**: export your library and settings

## Platforms

| Platform | Status |
|----------|--------|
| Android  | Supported |
| Linux    | Supported |
| Windows / macOS / iOS | Not yet |

## Build from source

Flutter 3.38+ with Dart 3.12+.

```bash
git clone https://github.com/GrishMahat/NovelDock.git
cd NovelDock
flutter pub get
flutter run -d linux   # or: flutter build apk
```

Forked git dependencies (see below) resolve automatically during `pub get`.

## Desktop keyboard shortcuts

| Keys | Action |
|------|--------|
| `1` - `4` | Switch tabs (Library, Browse, History, Settings) |
| `Ctrl+D` | Downloads |
| `Ctrl+,` | Settings |
| `F5` / `Ctrl+R` | Refresh current tab |
| `Left` / `Right` (reader) | Previous / next chapter |
| `Space` (reader) | Toggle reader controls |
| `Esc` (reader) | Back |
| `Ctrl+L` (reader) | Pin the chapter panel |

## Sources

Novels come from provider registries you add in Settings > Providers. The default registry lives at [noveldock-providers](https://github.com/GrishMahat/noveldock-providers).

## Forked packages

Some Dart packages are maintained as forks and pulled as git dependencies:

- [flutter_edge_tts](https://github.com/GrishMahat/flutter_edge_tts), fork of [Moosphan/flutter_edge_tts](https://github.com/Moosphan/flutter_edge_tts). Upstream opens a new connection per synthesis request; the fork holds one persistent WebSocket instead.
- [just_audio_media_kit](https://github.com/GrishMahat/just_audio_media_kit), fork of [Pato05/just_audio_media_kit](https://github.com/Pato05/just_audio_media_kit). Adds a static `mpvProperties` map so any mpv property (network timeout, HTTP headers) applies to every player; upstream had no such hook.
- [flutter_js](https://github.com/GrishMahat/flutter_js), fork of [abner/flutter_js](https://github.com/abner/flutter_js). Runs provider scripts on quickjs-ng. Forked early on; the exact reason is lost to time, but it works and stays pinned.

## Credits

I built NovelDock because I wanted to read my novels on the desktop. [QuickNovel](https://github.com/LagradOst/QuickNovel) by LagradOst and contributors was the inspiration, and credit goes to that team for the idea. The app itself is an independent Flutter codebase with a different architecture, not a port.

JS runtime: forked [flutter_js](https://github.com/abner/flutter_js) running quickjs-ng.

## License

Copyright (C) 2026 Grish Mahat

NovelDock is free software: you can redistribute it and modify it under the GNU General Public License, version 3 or later. See [LICENSE](LICENSE). It ships without warranty; the license has details.

## Status

Early beta. Rough edges expected. Issues and pull requests welcome.
