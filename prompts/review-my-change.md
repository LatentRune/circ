# Check my change before I open a PR

```
Read AGENTS.md first. Review my changes against origin/main (git diff origin/main).

Check:
1. features/ and core/ draw nothing; layers only use their own layer and the ones
   below; every new file is in src/Circ.toc at the end of its layer; events go through
   ns:On and timers through ns:After / ns:Every; nothing new is global.
2. Messages to other players still work with older clients: fields added, none renamed
   or removed. tools/tests/protocol.py passes.
3. Players never see the word "union".
4. New parts players see have a setting key, a Settings row and a help line if they
   have a command; moved settings have a migration.
5. It works on Lua 5.1, and version differences go through core/Compat.lua.
6. Comments are true, in plain words, and the top comment of each changed file still
   describes it. CHANGELOG.md has a line for anything players will notice.
7. Run python3 tools/check.py, luacheck src and python3 tools/pr-shots.py; look at
   every screenshot and tell me if anything else changed that shouldn't have.

List what you'd fix, most important first, and fix the ones I agree with.
```
