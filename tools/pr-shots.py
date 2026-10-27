#!/usr/bin/env python3
"""Before-and-after screenshots for a change, ready to paste into a pull request.

    python3 tools/pr-shots.py                 # compare your working copy with origin/main
    python3 tools/pr-shots.py --base v0.14.0  # or with any branch, tag or commit
    python3 tools/pr-shots.py --all           # every scenario, changed or not

Runs every scenario in tools/circ-shots/scenarios/ against the base and against your
working copy, finds the ones whose drawing changed, and saves screenshots of both:

    screenshots/pr/before/<scenario>.png
    screenshots/pr/after/<scenario>.png
    screenshots/pr/summary.md       a table for the PR description

Both sides run the same scenarios (yours), so a new scenario shows up with no "before".
Needs what tools/circ-shots needs: Python with lupa, and Node with playwright.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = os.path.join(ROOT, "tools", "circ-shots")
SHOOT = os.path.join(SHOTS, "shoot.py")


def git(*args, **kw):
    return subprocess.run(["git", "-C", ROOT] + list(args), check=True, capture_output=True, text=True, **kw).stdout.strip()


def shoot(addon, names, dump=None, out=None):
    env = dict(os.environ, CIRC_ADDON=addon)
    if out:
        env["CIRC_SHOTS_OUT"] = out
    args = [sys.executable, SHOOT] + names + ([f"--dump={dump}"] if dump else [])
    return subprocess.run(args, env=env, capture_output=True, text=True)


def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base", default="origin/main", help="branch, tag or commit to compare with")
    ap.add_argument("--out", default=os.path.join(ROOT, "screenshots", "pr"), help="where to save them")
    ap.add_argument("--all", action="store_true", help="every scenario, not just the changed ones")
    opts = ap.parse_args()

    names = sorted(f[:-4] for f in os.listdir(os.path.join(SHOTS, "scenarios")) if f.endswith(".lua"))
    tmp = tempfile.mkdtemp(prefix="circ-pr-shots-")
    base_tree = os.path.join(tmp, "base")
    try:
        git("worktree", "add", "--detach", base_tree, opts.base)
        dumps = {side: os.path.join(tmp, side + "-dump") for side in ("before", "after")}
        addons = {"before": os.path.join(base_tree, "src"), "after": os.path.join(ROOT, "src")}
        for side in ("before", "after"):
            shoot(addons[side], names, dump=dumps[side])  # failures show up as a missing dump

        changed = []
        for n in names:
            b, a = load(os.path.join(dumps["before"], n + ".json")), load(os.path.join(dumps["after"], n + ".json"))
            if a is None:
                print(f"{n}: fails on your copy; run tools/circ-shots/shoot.py {n} to see why")
            elif opts.all or b != a:
                changed.append((n, b is not None))

        if os.path.isdir(opts.out):
            shutil.rmtree(opts.out)
        rows = []
        for side in ("before", "after"):
            wanted = [n for n, had in changed if side == "after" or had]
            if wanted:
                shoot(addons[side], wanted, out=os.path.join(opts.out, side))
        for n, had in changed:
            before = f"![before](before/{n}.png)" if had else "(new scenario)"
            rows.append(f"| `{n}` | {before} | ![after](after/{n}.png) |")
        if not changed:
            print("Nothing drawn differently in any scenario. If your change should show, add a scenario"
                  " (see prompts/add-a-screenshot-scenario.md).")
            return
        os.makedirs(opts.out, exist_ok=True)
        with open(os.path.join(opts.out, "summary.md"), "w") as f:
            f.write("| Scenario | Before | After |\n|---|---|---|\n" + "\n".join(rows) + "\n")
        print(f"{len(changed)} scenario(s) changed: " + ", ".join(n for n, _ in changed))
        print(f"Screenshots and a table for your PR are in {os.path.relpath(opts.out, ROOT)}/")
    finally:
        subprocess.run(["git", "-C", ROOT, "worktree", "remove", "--force", base_tree], capture_output=True)
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
