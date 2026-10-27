# Fix something that's wrong

```
Read AGENTS.md first and follow it.

What's wrong: <e.g. "a trade shows as 'one side' even though we both have Circ">.
What should happen instead: <...>.
When it happens: <what you were doing, with whom, and whether it happens every time>.
Lua error, if any (from /console scriptErrors 1 or BugSack): <paste it>.
Debug lines, if any (/circ debug in a test build): <paste them>.

1. Find the cause. The top comment of each file says what it's for; features/ works
   things out and ui/ draws, so a wrong number is usually in features/ and a wrong look
   in ui/. Problems between two players usually live in core/Comm.lua, features/Sync.lua
   or the feature that sends the message.
2. If you can, first make a screenshot scenario or a tools/tests/protocol.py check that
   shows the bug, so the fix can be seen and stays fixed.
3. Fix it with the smallest change that does it.
4. Run python3 tools/check.py, luacheck src, python3 tools/tests/protocol.py and
   python3 tools/pr-shots.py. Show me before and after, and confirm the other scenarios
   didn't change.
5. Add a CHANGELOG.md line under Unreleased > Fixed. Explain the cause and the fix in a
   couple of sentences.
```
