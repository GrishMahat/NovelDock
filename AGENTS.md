# NovelDock — agent ground rules

## Git policy (strict)

- Never `git commit` or `git push` without an explicit request from Grish.
- Stage only files related to the current task; never blanket-stage (`git add -A`).
- Default flow: implement → analyze/test locally → hand over for manual testing → wait for explicit "commit" / "push" instructions.
- Pushes go to `origin` (github.com/GrishMahat/NovelDock). History rewrites need extra care; keep release tags intact.

## Project facts

- Flutter app (Android + Linux desktop), Riverpod + Drift, GPL-3.0.
- Design contract lives in DESIGN.md; read before UI work.
- Analyzer runs with `flutter analyze --no-pub`; tests via `flutter test`.
- Android signing keystore: ~/noveldock-keys/ (never commit, never delete).
- Releases: pushing a `v*` tag triggers the signed-build workflow.
