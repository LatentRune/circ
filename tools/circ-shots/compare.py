"""Compare two --dump directories scenario by scenario.

    python3 compare.py OLD_DIR NEW_DIR

For each scenario: "same" when the dumps are identical; "same, reordered" when they hold
the same things in a different draw order (check the PNGs: order only matters where
things overlap); otherwise the first differences. Besides what is drawn, a dump holds
what Circ printed to chat, the addon messages it sent, any popup, and the saved
variables at the end, so a change there counts as a difference too.

A refactor must come out "same" for every scenario. Exit code 1 means something differed.
"""
import json
import os
import sys


def key(item):
    return json.dumps(item, sort_keys=True)


def main():
    old_dir, new_dir = sys.argv[1], sys.argv[2]
    bad = 0
    for name in sorted(os.listdir(old_dir)):
        if not name.endswith(".json"):
            continue
        with open(os.path.join(old_dir, name)) as f:
            old = json.load(f)
        path = os.path.join(new_dir, name)
        if not os.path.exists(path):
            print(f"{name}: missing")
            bad += 1
            continue
        with open(path) as f:
            new = json.load(f)
        if old == new:
            print(f"{name}: same")
            continue
        oi, ni = [key(i) for i in old["items"]], [key(i) for i in new["items"]]
        rest_same = {k: v for k, v in old.items() if k != "items"} == {k: v for k, v in new.items() if k != "items"}
        if sorted(oi) == sorted(ni) and rest_same:
            print(f"{name}: same, reordered")
            continue
        bad += 1
        print(f"{name}: DIFFERENT ({len(oi)} -> {len(ni)} things)")
        for k in ("mouse", "meta"):
            if old.get(k) != new.get(k):
                print(f"  {k}: {old.get(k)} -> {new.get(k)}")
        for k in sorted(set(old.get("state", {})) | set(new.get("state", {}))):
            a, b = old.get("state", {}).get(k), new.get("state", {}).get(k)
            if a != b:
                print(f"  {k}: " + (key(a)[:200]) + " -> " + (key(b)[:200]))
        gone = [k for k in oi if k not in set(ni)]
        added = [k for k in ni if k not in set(oi)]
        for k in gone[:4]:
            print("  - " + k[:300])
        for k in added[:4]:
            print("  + " + k[:300])
    for name in sorted(os.listdir(new_dir)):
        if name.endswith(".json") and not os.path.exists(os.path.join(old_dir, name)):
            print(f"{name}: new")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
