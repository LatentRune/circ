# Open the pull request

```
Read AGENTS.md first.

Get my change ready as a pull request to LatentRune/circ:
1. Run python3 tools/check.py, luacheck src, python3 tools/tests/protocol.py and
   python3 tools/pr-shots.py; all must pass.
2. Commit on a branch named for the change (e.g. look/trade-dates,
   fix/one-sided-trades, feature/bag-counts-on-requests), one change per PR.
3. Write the description with .github/PULL_REQUEST_TEMPLATE.md: what players will see
   before and after in plain words, the screenshots table from screenshots/pr/summary.md,
   and how it was tested (scenarios, and in game if I tell you I tried it).
4. Push and open the PR. CI will post the before-and-after screenshots on it too.
```
