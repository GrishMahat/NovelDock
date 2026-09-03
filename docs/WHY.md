# Why it's built this way

Short answers to questions a contributor would reasonably ask. Written the way
I'd answer them on Discord, including the parts where the honest answer is
"habit" or "I don't remember."

## Why is everything converted to Markdown?

Every chapter that enters the app, no matter where it came from, becomes a
Markdown file. Provider sites return HTML, EPUBs contain XHTML, imports and
downloads each have their own shape, and I didn't want the reader, TTS,
translation, and download code all dealing with those formats directly. So
there's one intake step (`html2md.dart`, driven by `chapter_intake.dart`) that
converts whatever arrived into Markdown, and from there on the app works with
one parsed AST (`md_ast.dart`).

It wasn't the first design. The original reader rendered provider HTML
directly, and that worked until TTS showed up. Read-aloud needs to know which
paragraph is being spoken, how to skip forward, and where to put the
highlight. Pulling that out of a different pile of nested divs per provider
was fragile, and styling was just as bad, because fonts, themes, and bionic
reading all had to fight the inline styles each site shipped. Commit
`7251665` replaced it with the current pipeline and it's been stable since.

The cost is that conversion is lossy. Some site-specific layout gets flattened,
and HTML keeps producing weird edge cases, which is why the git history has
several "escape markdown special chars in html2md" fixes. I accepted that. One
content model the whole app can trust beats three fragile ones. A WebView was
never a real option since it can't even see paragraph boundaries for
highlighting, and plain text would throw away the italics and bold that matter
in novels. The old `html_chapter_view.dart` still sits in the repo
unreferenced, a leftover from the HTML days.

## Why are providers JavaScript instead of built into the app?

Because every time a source breaks, I didn't want to rebuild and ship a whole
app release for a one-line patch. Sites change constantly. With providers as
JavaScript files loaded from a registry, fixing a source is a registry update,
users never have to update the app, and I'm not the bottleneck for every site
on earth. Building sources into Dart would also have locked out the people who
are best at writing them: a provider is mostly "fetch a page and parse it",
which is exactly what web-side JavaScript folks already do.

Why JavaScript and not Lua or something else embeddable? No benchmark and no
deep comparison, I'm afraid. I looked for a well-embedded language for
Flutter, people recommended JavaScript, and I already knew it well. I've
barely touched Lua, just some Neovim config and one small script, and
debugging community providers in a language I can't read fluently sounded
miserable. In hindsight the choice holds up beyond luck: the contributor pool
that can write a scraper already speaks JS. The trade-off I accepted is trust.
Running community code on-device means users are trusting whoever curates the
registry they add. And quickjs is not fast, but providers do network I/O and
light parsing, which is plenty.

## Why Drift (SQLite) for the database?

Mostly familiarity. I'd used Drift in an earlier project and had a good
experience, so it carried over. I tried Hive in a different project, and it's
good, but the experience didn't click for me. Isar wasn't a considered option
at all; I wrote my first Dart code in 2026 and didn't know it existed when I
picked the database. Plain sqflite lost because I didn't want to write raw SQL
by hand. The thing I regret is Drift's migrations. Adding one field to
bookmarks hurt enough that I cursed the choice that day. Not enough to migrate
away, but if you're adding your first schema change, budget time for it.

## Why Riverpod with manual providers instead of codegen?

Momentum. Another project of mine used manual Riverpod, so I carried the
patterns over, and I genuinely forgot codegen existed while building. I don't
hate generated code; if something big enough comes up, switching is on the
table. Until then, one small thing I like is that the provider rules, like
"hold a provider-level Ref, never a widget-scoped one", are visible in the
source instead of hidden behind a generator.

## Why do chapter rows act as identity?

Reading history, bookmarks, downloads, and read flags all key off the chapter
row id, and refreshing a novel preserves those ids by diffing URLs instead of
deleting and reinserting everything. Truthfully, I don't remember what forced
this design anymore. What survives is the reasoning, written into the code
itself: delete-and-reinsert churns the autoincrement ids, which orphans
everything keyed by chapter and silently wipes per-chapter state. If you're
touching chapter sync, trust the doc comment on `syncChaptersForNovel`. It
remembers more than I do.

## Why is Edge TTS the default voice engine?

I'm dyslexic and use TTS every day, and I've liked Microsoft's voices for as
long as I can remember. They simply sound better than anything else I tried.
It's also free, and it works. On Linux there's no good on-device TTS out of the
box; you can install voices, but none matched Edge. Yes, it's an unofficial
endpoint, and I accepted that knowingly. The fork of `flutter_edge_tts` keeps
one persistent WebSocket instead of reconnecting per request, and if Microsoft
ever closes the door, the pluggable engine system is the fallback, not a
rewrite.

## Why mpv (media_kit) for Linux audio?

`just_audio` alone didn't work on Linux; the problems are in the git history.
Routing playback through media_kit/mpv fixed it, and I forked
`just_audio_media_kit` to add an `mpvProperties` hook so player settings like
network timeout and HTTP headers can actually reach mpv. Upstream had no way
to do that.
