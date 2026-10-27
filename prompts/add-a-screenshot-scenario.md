# Add a screenshot scenario

```
Read AGENTS.md and tools/circ-shots/README.md first.

Add a screenshot scenario showing: <e.g. "the Ledger tab with a trade only one side
reported, so it shows 'one side'">.

1. Copy the closest scenario in tools/circ-shots/scenarios/ to a new file named for
   what it shows (lowercase-with-dashes.lua). Set SHOT.title to a short caption.
2. Load the shared cast with dofile(SIM_DIR .. "fixtures.lua") and call Setup(), then
   use the helpers in tools/circ-shots/sim.lua (Member, OfflineMember, Trade,
   OpenProfession, Slash, Click(ButtonNamed(...)), Type, PressEnter, HoverItem, Advance)
   to get to the moment worth showing. Drive Circ the way a player would, not by calling
   its functions, so the scenario keeps working when the code inside changes.
3. If the scenario needs a game function world.lua doesn't answer yet, add it there the
   way the others are written, with a comment.
4. Run python3 tools/circ-shots/shoot.py <name> and look at screenshots/<name>.png.
   Make sure it shows what it's meant to and nothing reads as broken.
5. Run every scenario with --dump twice and check with compare.py that the new one comes
   out the same both times.
```
