# Contributing to NovelDock

Thanks for your interest! NovelDock is an early-beta project and contributions of
every size are welcome — code, docs, bug reports, and **JavaScript provider
extensions** (which need zero Dart/Flutter knowledge).

## Ways to contribute

1. **Provider extensions** — write a JS source for your favorite novel site. The
   default registry lives at [noveldock-providers](https://github.com/GrishMahat/noveldock-providers),
   and `tool/provider-test` in this repo lets you test a script from the terminal
   without building the app.
2. **Code** — Flutter/Dart, see the map in [AGENTS.md](AGENTS.md) for where things live.
3. **Triage & docs** — reproduce bugs, improve this documentation, add screenshots.

## Development setup

- Flutter 3.38+ with Dart 3.12+
- Linux desktop builds need `libmpv-dev` (see `linux/` and the release workflow)

```bash
git clone https://github.com/GrishMahat/NovelDock.git
cd NovelDock
flutter pub get
flutter run -d linux        # or: flutter build apk --debug
```

Forked git dependencies resolve automatically during `pub get`.

## Before you open a PR

CI enforces exactly this, so run it locally first:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
```

- One logical change per PR; keep the diff focused.
- Add or update tests for anything in `lib/core/` (especially `tts/` and `database/`).
- Add a line to `CHANGELOG.md` under the unreleased section for user-visible changes.
- UI changes must follow the design contract in [DESIGN.md](DESIGN.md).
- Don't touch `android/key.properties`, keystore files, or release tags.

## Reporting bugs

Open an issue with the bug report template. Include: device/platform, app version,
the provider (source) you were using, and steps to reproduce. Logs from
Settings → Logs are gold.

## Questions & ideas

Use [GitHub Discussions](https://github.com/GrishMahat/NovelDock/discussions) for
questions, ideas, and provider requests — issues are for actionable work.

## License

By contributing, you agree that your contributions are licensed under the
GNU General Public License v3.0 (or later), same as the project.
