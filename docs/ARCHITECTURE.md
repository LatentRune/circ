# How Circ fits together

This is the map for changing Circ. Each file's own top comment has the detail.

## Layers

```
core/      shared table, events, timers, settings, compat, messages   (everything uses it)
data/      every recipe and BoE item name, generated                  (read by features)
features/  works things out: records, prices, lookups, the ledger     (uses core, data)
ui/        draws what features worked out                             (uses core, features)
settings/  the Settings tab, /circ and its help                       (uses all of the above)
dev/       /circ debug, /circ status, /circ cpu; not in release zips  (uses all of the above)
```

A feature often has two files: `features/Nudges.lua` finds members who pay more than the
vendor; `ui/Nudges.lua` says so in chat. `features/ItemSummary.lua` counts buyers and
makers; `ui/Tooltip.lua` adds the lines. Each tab of the window is one ui/ file
(`ui/Lookup.lua`, `ui/Requests.lua`, `ui/Prices.lua`, `ui/Ledger.lua`) built on the
shared widgets in `ui/widgets/`.

`tools/check.py` enforces the line between them: features/ and core/ draw nothing, and no
file uses a name from a layer above its own. When a lower layer needs something from a
higher one, it fires a callback (`ns:Fire("VendorOffers", offers)`) or asks through a
hook the higher layer fills in (`ns:Ask("INVITE", ...)`, `ui/Popups.lua`).

## The shared table

Every file starts with `local ADDON, ns = ...`. The game hands each file of an addon its
name and one shared table; whatever a file puts on `ns` the files after it can use.
Everything else stays local to the file. The load order is `src/Circ.toc`.

What's on `ns`, by where it comes from:

- `core/Namespace.lua`: `ns.version`, `ns.protocol`, `ns:Print`, `ns:Debug`, names
  (`ns:PlayerKey`, `ns:FullName`, `ns:ShortName`), items (`ns:ItemName`,
  `ns:ItemIDFromLink`), money (`ns:Money`, `ns:ParseMoney`), `ns.Hash`, `ns.To36` /
  `ns.From36`, and `ns:Ask`, which ui/Popups.lua fills in.
- `core/Events.lua`: `ns:On(event, fn)` for game events, `ns:Listen(name, fn)` and
  `ns:Fire(name, ...)` for Circ's own callbacks, and `ns.Run`, which every handler runs
  through (dev/Profiler.lua times it).
- `core/Timers.lua`: `ns:After(seconds, fn)` and `ns:Every(seconds, fn)`.
- `core/Compat.lua`: `ns.Compat`, one name for whatever differs between game versions.
- `core/Settings.lua`: `CircDB` (the saved variables), `ns:UnionDB()` (this ledger's
  members, bags and trades on this realm and faction) and `ns:CharDB()` (this
  character's professions and listings).
- `core/Comm.lua`: `ns.Comm:Send(kind, data, target)`; received messages arrive as
  `ns:Listen("Msg:<kind>", fn(data, sender, dist))`.
- features/: one table per file, named in its top comment: `ns.Recipes`, `ns.Scan`,
  `ns.Prices`, `ns.Stock`, `ns.Bags`, `ns.Records`, `ns.Lookup`, `ns.Union` (Channel,
  Connection and Union all add to it), `ns.Protection`, `ns.Sync`, `ns.Ledger`,
  `ns.Guide`, and `ns:ItemSummary`.
- ui/: `ns.UI` (the window, `ui/Window.lua`, with each tab adding to it), `ns.Text` and
  `ns.Widgets` (building blocks), `ns.MoneyInput`, `ns.Minimap`, `ns:ShowPopup`.
- settings/: `ns.Panel`, `ns.Help`, `ns.Slash` (`ns.Slash.commands`, which dev/ adds to).

Code calls a ledger a "union" (`ns.Union`, `CircDB.union`, `ns:UnionDB`); players only
ever see "ledger". The saved variables keep the old word so nobody's data moves.

## Callbacks

| Callback | Fired by | When |
|---|---|---|
| `Ready` | core/Settings.lua | once at login, after the saved variables are loaded |
| `DataChanged` | many | something in my record changed: prices, requests, listings, a scan |
| `RecordsUpdated` | features/Sync.lua | my record was rebuilt |
| `Msg:<KIND>` | core/Comm.lua | an addon message of that kind arrived |
| `Seen` | core/Comm.lua | any message from a member, so they count as online |
| `UnionChanged`, `UnionLeaving`, `UnionConnected` | features/Union.lua, Connection.lua | the ledger changed, is being left, or its channel is joined |
| `LedgerChanged`, `BagsChanged` | features/Ledger.lua, Bags.lua | a trade or a member's bags changed |
| `ScanDone` | features/Scan.lua | a profession window was read |
| `VendorOffers`, `AuctionOffer` | features/Nudges.lua | members pay more than the vendor or market |

Handlers run in the order they were added, which is the order of the files in
`Circ.toc`. Keep that in mind before moving a file: two handlers of the same event can
depend on running in turn, and timers started at the same moment fire in the order they
were started.

## Life of a record

1. A player opens their Tailoring window. `features/Scan.lua` reads every recipe,
   matches it against the bundled `data/RecipeData.lua`, saves the profession and fires
   `DataChanged`.
2. `features/Sync.lua` waits 3 seconds for more changes, then has `features/Records.lua`
   build this character's record (professions, recipe IDs, buy and sell prices, requests,
   listings), packed short in base 36. If its version changed, Sync says `HELLO` to the
   ledger's channel with the new version.
3. Every member holding an older version asks for it (`REQ`), at most every 30 seconds;
   the owner answers with the record (`REC`), on the channel if three or more asked.
4. `core/Comm.lua` splits anything over 240 bytes into chunks and sends at most about
   one message a second; the other side puts the chunks back together and fires
   `Msg:REC`. Records.lua unpacks it into `ns:UnionDB().players`.
5. `features/Lookup.lua` answers from those records, and `ui/Lookup.lua` draws the
   answer the next time the window refreshes.

A member who logs in late asks the channel for a directory (`DIRREQ`); one member answers
with the versions it holds and relays the records the newcomer is missing (`RRELAY`),
marked as relayed. Trades (`LEDG`, `LREQ`, `LDUMP`) and bag contents (`BAGS`, `BAGD`,
`BAGREQ`) work the same way.

## The ledger's channel

A ledger lives in a hidden custom chat channel named `circ` + 4 hidden characters + the
5-letter name, like `circQ7K2smith` (`features/Channel.lua`). Nobody can guess the hidden
part, so ledgers are joined by invite. Every new account starts in `circ0000start`
(START). `features/Connection.lua` keeps the account in its channel: after login, after
loading screens, and whenever the channel drops. `features/Protection.lua` watches for a
stranger taking over the channel and offers to move the ledger to a successor channel
that every member's client works out the same way.

## The window

`ui/Window.lua` builds the window the first time it opens and redraws it on every
callback that might change what it shows. A redraw asks the current tab's builder
(`UI.builders.<tab>`) for a list of row descriptions (see `ui/widgets/List.lua`) and fills
the 18 rows from them, so a tab never touches frames itself. Each tab also builds its
toolbar once and adds a function to `UI.refreshers` to keep it up to date.

## Settings

`CircDB.settings` holds one key per part players can turn off; `core/Settings.lua` lists
them with the files they switch. A new part needs its key in `DEFAULTS`, a row in
`settings/Panel.lua`, and a line in `settings/Help.lua` if it has a command. When a saved
setting moves or is renamed, add a step to `MIGRATIONS` in `core/Settings.lua`, so
players keep their setup.

## Screenshots and tests without the game

`tools/circ-shots/` loads the addon exactly as the game does (`Circ.toc` order) into a
stand-in for the game's widgets (`ui.lua`) and API (`world.lua`), runs a scenario, and
draws what Circ built. Other members are simulated by sending the same addon messages
their client would. `--dump=DIR` writes what was drawn, printed, sent and saved as JSON,
and `compare.py` diffs two dumps; `tools/pr-shots.py` does both sides of a change and
renders what differs. A refactor that changes nothing dumps identically.

`tools/tests/protocol.py` runs several Circ clients at once and checks what they say to
each other: invites, record sync, prices, the trade ledger, takeovers and bag sharing.
