# Circ screenshots without the game

`shoot.py` runs the addon's real Lua against a stand-in for the game and saves what it
draws as PNGs in `screenshots/` at the top of the repo. The addon loads exactly as the
game loads it (saved variables first, then every file in `Circ.toc` order), so a
screenshot shows the code as it is now.

```
python3 shoot.py                      # every scenario
python3 shoot.py ledger prices        # just these
python3 shoot.py --html-only          # write the .html pages only (open them in any browser)
python3 shoot.py --dump=DIR           # write every scenario as data instead of pictures
python3 compare.py OLD_DIR NEW_DIR    # what changed between two dumps
```

Needs Python 3 with `lupa` (`pip install lupa`). For PNGs it also needs Node with the
`playwright` package and its Chromium.

## Proving a change changed nothing

A refactor must dump identically:

```
git stash; python3 shoot.py --dump=/tmp/before; git stash pop
python3 shoot.py --dump=/tmp/after
python3 compare.py /tmp/before /tmp/after     # every line should say "same"
```

A dump holds everything drawn (position, size, color, text of every texture and font
string, back to front), plus what Circ printed to chat, the addon messages it sent, the
popup it opened and the saved variables at the end. Runs are repeatable: the clock,
dates (UTC) and `math.random` are fixed, so the same code gives the same bytes twice.

`tools/tests/protocol.py` covers the other half: two clients talking to each other
(invites, record sync, the trade ledger, takeover moves). Run both.

## How it works

- `ui.lua` stands in for the game's widgets: frames, textures, font strings, buttons, edit
  boxes, check buttons, scroll frames, backdrops and the tooltip, plus rough looks for the
  templates Circ uses (`BasicFrameTemplateWithInset`, `UIPanelButtonTemplate`,
  `InputBoxTemplate`, tab buttons, `FauxScrollFrameTemplate`). It keeps what the addon sets
  and lays things out the way the game does. Methods it doesn't model do nothing.
- `world.lua` answers the game's API from a `WORLD` table: you, your bags, items, chat
  channels, the profession window, a price addon, popups (with the game's real
  `StaticPopup_Show` argument order) and timers run from a fake clock.
- `sim.lua` has the helpers scenarios use: `Boot(savedVariables)`, `Advance(seconds)`,
  `Member{...}` and `OfflineMember{...}` (other players, speaking Circ's wire format the
  way their client would), `Trade{...}`, `OpenProfession`, `Slash("find Linen Cloth")`,
  `Click(ButtonNamed("Who makes it"))`, `Type(box, text)`, `PressEnter(box)` and
  `HoverItem(id)`.
- `fixtures.lua` is the shared cast: Alice (you, a Tailor), Bob, Cara, Dain (offline) and
  Eira, their items, and `Setup()` for a returning player in the ledger SMITH.
- `shoot.py` turns the drawn list into HTML and `shoot.js` screenshots it with headless
  Chromium at 2x.

## Adding a scenario

Copy one in `scenarios/`, change the world, and run it. The usual order: load
`fixtures.lua`, `Setup()`, then do what a player would do and let time pass. Drive the
addon the way a player does (slash commands, buttons by their text, typing), not by
calling its functions, so a scenario keeps working when the code inside is reorganized.

## What's approximate

- Game art can't be loaded or shipped here, so item icons are colored tiles with a short
  label, class icons are class-colored tiles, coins and online dots are small circles, and
  window and button art are flat rectangles.
- Text uses Liberation Sans squeezed to the width of Arial Narrow, not Friz Quadrata.
- The background is a stand-in for the game world, with a chat window bottom left.
- Layout, sizes, colors, text, timing and what Circ prints and sends come from the
  addon itself. Nothing here proves the real client agrees; check in game before a release.
