# Change how something looks

```
Read AGENTS.md first and follow it.

I want to change how this part of Circ looks: <the part, e.g. "the Ledger tab's trade list">.
What I want: <e.g. "show the trade's date as 'Tue 14:05' instead of '10-27 14:05'">.
Why (what's hard to read now): <e.g. "I can't tell which trades were this week">.

1. Find the ui/ file that draws it (the top comments say what each file draws) and make
   the smallest change that does what I asked. Don't touch features/ unless the look
   needs a new number from it.
2. Run python3 tools/check.py and luacheck src.
3. Run python3 tools/pr-shots.py and show me the before and after screenshots it made.
   If no scenario shows this part, add one (see prompts/add-a-screenshot-scenario.md).
4. Add a line to CHANGELOG.md under Unreleased if players will notice.
5. Tell me what changed in one or two sentences a player would understand, and anything
   I should check in game.
```
