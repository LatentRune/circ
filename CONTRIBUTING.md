# Contributing to Circ

Thanks for helping. Circ gets better fastest when players who use it every week change
what bugs them, so small pull requests are welcome: a wording, a color, a column, one new
reminder. You don't need to know the whole addon to change one part of it.

## The short version

1. Fork and clone the repo.
2. Change something under `src/`.
3. Run the checks and make screenshots:
   ```
   python3 tools/check.py
   python3 tools/pr-shots.py
   ```
4. Open a pull request. Paste `screenshots/pr/summary.md` into it and attach the
   pictures (CI also posts them on the PR for you).

## Setting up

You need **Python 3** with `lupa` (`pip install lupa`), and for pictures **Node** with
`playwright` (`npm install -g playwright && npx playwright install chromium`).
`tools/site-images.py` (the website's screenshots) and `tools/brand-images.py` (the icon,
social card and theme sheet in `brand/`) also need Pillow (`pip install pillow`), and
[luacheck](https://github.com/lunarmodules/luacheck) is worth having (`luacheck src`).

To try your change in the game too, link the addon folder into your AddOns folder so the
game loads your copy:

```
# macOS / Linux
ln -s "$PWD/src" "/path/to/World of Warcraft/_classic_era_/Interface/AddOns/Circ"
# Windows (from an admin prompt)
mklink /D "C:\...\_classic_era_\Interface\AddOns\Circ" "%CD%\src"
```

Then `/reload` in game after each change. Testing with a friend, or a second account on
the same realm and faction, covers the ledger itself: [docs/TESTING.md](docs/TESTING.md)
is the checklist.

## Where things are

```
src/
  core/       the foundation: the shared table, events, timers, settings, messages
  data/       every Classic Era recipe and BoE item name, generated: don't edit by hand
  features/   works things out: records, prices, lookups, the ledger channel, trades
  ui/         draws what features/ worked out: the window, one file per tab
  settings/   the Settings tab, /circ and its help
  dev/        testing tools: /circ debug, /circ status, /circ cpu (not in release zips)
tools/
  circ-shots/     draws Circ without the game, for screenshots and tests
  tests/          two or more Circ clients talking to each other
  pr-shots.py     before-and-after screenshots of your change
  check.py        the layout rules below
  package.py      zips: the whole repo, or the player zip
prompts/          ready-made prompts for AI coding assistants
docs/             how it all fits together, and the website
```

Most changes touch one file in `ui/` (how something looks) or one in `features/` (what it
works out), sometimes both. The comment at the top of each file says what it's for, which
setting switches it, and which other files it works with.
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) explains the whole thing.

## The rules

These keep the code easy for the next person. `tools/check.py` checks the first four.

- **features/ never draws.** No frames, textures, font strings, popups, tooltips or
  chat lines there (`ns:Print` is fine). It works things out and puts functions on `ns`,
  or fires a callback, for ui/ to use.
- **Layers only look down.** core/ and data/, then features/, ui/, settings/, dev/. A
  file can use anything from its own layer or below, never above.
- **Every file is listed in `src/Circ.toc`** and starts with a comment naming it.
- **Events go through `ns:On`, timers through `ns:After` / `ns:Every`**, so `/circ cpu`
  can see what each part costs.
- **No new globals.** Share through `ns`. The few the game needs are in `.luacheckrc`.
- **Lua 5.1**, which is what the game runs: no `goto`, no `//`, no `utf8`. Anything that
  differs between game versions goes in `core/Compat.lua`.
- **Every part has a checkbox.** A new part players see gets a key in
  `core/Settings.lua`, a row in `settings/Panel.lua` and a line in `settings/Help.lua` if
  it has a command. A saved setting that moves or is renamed gets a migration there too.
- **Comments say what and why**, in plain words a player would follow. Name the setting
  and the game behavior; skip what the code already says.

## Screenshots

`tools/circ-shots/` runs Circ's real Lua against a stand-in for the game and draws what it
built, in scenarios like "looking up who makes Linen Cloak" or "a takeover detected". It
isn't the game (icons are colored tiles, fonts are close), but layout, sizes, colors,
text, timing, chat lines and addon messages all come from the addon.

- `python3 tools/pr-shots.py` compares your copy with `origin/main` and saves before and
  after pictures of every scenario your change affects.
- `python3 tools/circ-shots/shoot.py ledger` draws one scenario into `screenshots/`.
- If your change doesn't show in any scenario, add one: copy a file in
  `tools/circ-shots/scenarios/`, set up the world, and run it.
  [prompts/add-a-screenshot-scenario.md](prompts/add-a-screenshot-scenario.md) walks through it.
- `python3 tools/tests/protocol.py` runs several Circ clients against each other:
  invites, record sync, trades, takeovers, bag sharing. Run it after touching anything
  that sends or receives messages.

A change that only reorganizes code should draw exactly the same: `pr-shots.py` then says
nothing changed. That's the test.

## Pull requests

- Say what players will see, before and after, in plain words. Screenshots help most.
- Say how you tested: the screenshot scenarios, and if you can, in game (which client,
  class and level, and whether a second player was in the ledger).
- Keep it to one change. Two small PRs get reviewed faster than one big one.
- Anything players will notice gets a line in [CHANGELOG.md](CHANGELOG.md) under
  Unreleased.
- CI runs `tools/check.py`, luacheck, the network tests and every screenshot scenario,
  and posts your before-and-after pictures on the PR.

## Zips

`python3 tools/package.py` zips the whole project into `dist/` for sharing with another
contributor. `python3 tools/package.py release` builds the player zip: `src/` as the
`Circ/` folder the game expects, with the license inside and without `dev/`, which is
what a `v*` tag publishes.

## Feedback without code

Issues are just as useful: [a bug](https://github.com/LatentRune/circ/issues/new?template=bug.yml),
[how something looks](https://github.com/LatentRune/circ/issues/new?template=looks.yml),
or [an idea](https://github.com/LatentRune/circ/issues/new?template=idea.yml).
A screenshot from the game is worth a paragraph.

For a quick question, come to [Discord](https://discord.gg/wcCfAmMsFV). Bigger ideas that
need talking through belong in [Discussions](https://github.com/LatentRune/circ/discussions).

## License

By contributing you agree your contribution is released under the [MIT License](LICENSE).
