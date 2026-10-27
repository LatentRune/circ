# Add something new

```
Read AGENTS.md and docs/ARCHITECTURE.md first and follow them.

I'd like Circ to: <what, e.g. "show how many of an item I have in my bags next to each
request on the Requests tab">.
Where: <e.g. "the Requests tab, in the 'What others want to buy' list">.
When it should show and when not: <e.g. "only when I have at least one">.
Does another member need to see it? <yes/no; if yes, it has to travel in a message>

Build it the Circ way:
1. Anything worked out from the game goes in features/ (an existing file, or a new
   features/<Name>.lua) that draws nothing. Drawing goes in ui/. If it has to reach
   other players, add an optional field to an existing message rather than a new kind,
   and keep older clients working.
2. List new files in src/Circ.toc at the end of their layer.
3. If players can turn it off, give it a setting key in core/Settings.lua, a row in
   settings/Panel.lua, and a line in settings/Help.lua if it has a command.
4. Top comment on each new file: what it does, its setting, the files it works with.
5. Add a screenshot scenario that shows it (prompts/add-a-screenshot-scenario.md). If it
   sends messages, add a check to tools/tests/protocol.py.
6. Run python3 tools/check.py, luacheck src, python3 tools/tests/protocol.py and
   python3 tools/pr-shots.py. Show me the screenshots, and confirm the scenarios that
   shouldn't change didn't.
7. Add a CHANGELOG.md line. Tell me what it does in plain words and what to test in game.
```
