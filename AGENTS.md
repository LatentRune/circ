# Working on Circ (for AI coding assistants)

Circ is a World of Warcraft Classic Era addon in Lua 5.1 (the game's Lua). The addon is
`src/` (installed into the game as `AddOns/Circ/`); everything else is tooling and docs.
Read `docs/ARCHITECTURE.md` before a change that touches more than one file.

## Layout

- `src/core/`: the shared table, events (`ns:On`, `ns:Listen`, `ns:Fire`), timers
  (`ns:After`, `ns:Every`), saved settings and defaults, version differences
  (`core/Compat.lua`) and addon messages (`core/Comm.lua`).
- `src/data/`: generated recipe and item lists. Don't edit by hand; see
  `tools/gen_recipes.py` and `tools/gen_boe.py`.
- `src/features/`: reads the game and works things out. **Never creates frames,
  textures or font strings, and never draws, opens popups, touches tooltips or writes
  chat lines** (`ns:Print` is allowed).
- `src/ui/`: draws. The window is `ui/Window.lua`, one file per tab, and
  `ui/widgets/` holds the shared building blocks.
- `src/settings/`: the Settings tab, `/circ` and its help.
- `src/dev/`: `/circ debug`, `/circ status`, `/circ cpu`. Left out of release zips, so
  nothing else may depend on it.
- `src/Circ.toc`: load order. Every .lua file must be listed. Handlers run in file
  order, so append new files at the end of their layer rather than reordering.

## Rules

- Every file starts with a top comment `-- <path>: what it's for`, its setting key, and
  the files it works with, then `local ADDON, ns = ...` (or `local _, ns = ...`). Keep
  that comment true when you change the file.
- A layer only uses its own layer and the ones below (core/data, features, ui,
  settings, dev). To reach up, fire a callback or use a hook like `ns:Ask`.
- Share through `ns` only. No new globals (the few the game needs are in `.luacheckrc`).
- Game events through `ns:On`, timers through `ns:After` / `ns:Every`. No
  `RegisterEvent` or `C_Timer` outside core/.
- Circ talks to other players' clients. Changing a message (`ns.Comm:Send` kinds and
  fields) must keep older clients working: add fields, don't rename or remove them, and
  run `tools/tests/protocol.py`.
- Code says "union", players see "ledger". Never show "union" to a player.
- A new part players see gets a key in `core/Settings.lua` (`DEFAULTS.settings`), a row
  in `settings/Panel.lua`, and a line in `settings/Help.lua` if it has a command. A
  saved setting that moves gets a step in `MIGRATIONS`.
- The game's Lua is 5.1: no `goto`, no integer division `//`, no `utf8`. Anything that
  differs between clients goes through `core/Compat.lua`.
- No donation links or anything about money for the addon inside `src/`; the game's
  addon policy forbids it. Slash help may point at Discord and Issues only.
- Comments: plain words a player would follow, saying what and why. Don't narrate code.
- Anything players will notice gets a line in `CHANGELOG.md` under Unreleased.

## Commands to run

```
python3 tools/check.py                                  # layout rules and .toc listing
luacheck src                                            # globals and mistakes
python3 tools/tests/protocol.py                         # clients talking to each other
python3 tools/circ-shots/shoot.py --dump=/tmp/after     # every scenario as data
python3 tools/circ-shots/compare.py /tmp/before /tmp/after
python3 tools/pr-shots.py                               # before/after PNGs vs origin/main
```

Needs `pip install lupa`; PNGs also need Node with `playwright`.

- **A refactor must dump identically** to the code before it. Make a `--dump` before your
  change and compare after. "same, reordered" means the same things in a different draw
  order: render the PNGs and look, since order matters where things overlap.
- **A visible change** should show in some scenario. If none covers it, add one in
  `tools/circ-shots/scenarios/` (see `prompts/add-a-screenshot-scenario.md`). Drive it
  the way a player would (slash commands, clicks, typing), not by calling Circ's
  functions.
- **Look at the PNGs you made before saying a change looks right.**
- The stand-in isn't the game. Say what you checked in the harness and what still needs
  a check in game (`docs/TESTING.md`).

## Pull requests

Use `.github/PULL_REQUEST_TEMPLATE.md`. Lead with what players will see before and
after, attach `screenshots/pr/summary.md` and its images, and say how it was tested.
