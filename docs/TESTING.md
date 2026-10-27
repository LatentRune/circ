# Testing Circ in the game

The screenshot tools (`tools/circ-shots/`) and the network tests (`tools/tests/protocol.py`)
run Circ's real code against a stand-in for the game. They catch most mistakes, but only
the game can say whether the real client agrees. Before a release, someone runs through
this list in game.

## Two accounts, same realm and faction

You need two accounts (A and B) logged in at once, or two players who both have the
build to test.

- [ ] A fresh install opens Circ by itself after a few seconds, on Lookup, with the
      getting-started bar. Both accounts end up in START without typing anything.
- [ ] A turns on Ledger management (Settings > Advanced), creates a ledger and invites B.
      B gets a popup naming A and the ledger; accepting moves B. The Ledger tab on both
      shows both members, with recipe counts.
- [ ] Lookup on B finds A's recipes and prices.
- [ ] Tooltips show "Ledger: bought by..." and "made by...".
- [ ] Open a vendor with an item a member buys in your bags: chat lists the ledger offer.
- [ ] B shift-clicks a BoE item on the Prices tab; A finds it under Lookup > Who has it.
      B mails or vendors it; within a minute it's gone from A's lookup.
- [ ] Trade gold between the two: the Ledger tab shows the trade as confirmed on both.
- [ ] Takeover: on A (the creator, so the channel's owner) type `/chatlist` to find the
      `circ...` channel, then `/password <that channel> test`. B gets a popup offering to
      move the ledger; accepting moves B to a fresh channel with its members and trades.
- [ ] A logs out while owning the channel: ownership passes to B (`/chatlist` on B).
- [ ] `/circ debug` turns on debug lines. Report any "Circ debug: error" lines at
      [Issues](https://github.com/LatentRune/circ/issues).

## Not yet confirmed in game

- The invite and takeover popups: the stand-in found that both pass the game's popup one
  more piece of text than it fills in, which in the real client may stop them from
  showing. If B never sees the invite popup, that's why.
- Ownership handoff on logout, and the exact channel notice names the takeover check
  listens for.
- `/circ cpu` (the profiler in test builds).
