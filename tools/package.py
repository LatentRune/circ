#!/usr/bin/env python3
"""Zip Circ up, either as the whole project or as a player-ready addon.

    python3 tools/package.py            # dist/circ-<version>-source.zip: everything in the repo
    python3 tools/package.py release    # dist/Circ-<version>.zip: src/ as Circ/, plus LICENSE

The source zip is what you hand a contributor: README, .github, tools, prompts, docs and all.
The release zip is what players unzip into Interface/AddOns, with nothing GitHub-specific in
it. It also leaves out src/dev/ (the testing tools: /circ debug, /circ status, /circ cpu) and
their lines in Circ.toc. Both skip .git and anything .gitignore covers. The version comes
from src/Circ.toc.
"""

import fnmatch
import os
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
DIST = os.path.join(ROOT, "dist")
NOT_RELEASED = "dev"  # folder under src/ that stays out of the player zip


def version():
    with open(os.path.join(SRC, "Circ.toc"), encoding="utf-8") as fh:
        for line in fh:
            if line.startswith("## Version:"):
                return line.split(":", 1)[1].strip()
    sys.exit("No ## Version line in src/Circ.toc")


def ignored_patterns():
    # Simple .gitignore reading: one pattern per line, a trailing slash means a folder.
    pats = [".git/", "dist/"]
    path = os.path.join(ROOT, ".gitignore")
    if os.path.exists(path):
        with open(path, encoding="utf-8") as fh:
            pats += [l.strip() for l in fh if l.strip() and not l.startswith("#")]
    return pats


def skip(name, is_dir, pats):
    for p in pats:
        if p.endswith("/"):
            if is_dir and fnmatch.fnmatch(name, p[:-1]):
                return True
        elif fnmatch.fnmatch(name, p):
            return True
    return False


def files_under(top, pats):
    for here, dirs, files in os.walk(top):
        dirs[:] = sorted(d for d in dirs if not skip(d, True, pats))
        for f in sorted(files):
            if not skip(f, False, pats):
                yield os.path.join(here, f)


def release_toc():
    # Circ.toc without the dev\ files
    with open(os.path.join(SRC, "Circ.toc"), encoding="utf-8") as fh:
        lines = fh.read().split("\n")
    keep = [l for l in lines if not l.strip().replace("/", "\\").startswith(NOT_RELEASED + "\\")]
    return "\n".join(keep)


def write_zip(out, entries, extra=()):
    os.makedirs(DIST, exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for src, arc in entries:
            z.write(src, arc)
        for arc, text in extra:
            z.writestr(arc, text)
    print(out)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "source"
    v, pats = version(), ignored_patterns()
    if mode == "release":
        # Players get the addon folder with the license inside it, nothing else.
        entries = []
        for p in files_under(SRC, pats):
            rel = os.path.relpath(p, SRC).replace(os.sep, "/")
            if rel.split("/", 1)[0] == NOT_RELEASED or rel == "Circ.toc":
                continue
            entries.append((p, "Circ/" + rel))
        entries.append((os.path.join(ROOT, "LICENSE"), "Circ/LICENSE"))
        write_zip(os.path.join(DIST, "Circ-%s.zip" % v), entries, [("Circ/Circ.toc", release_toc())])
    elif mode == "source":
        top = "circ-%s" % v
        entries = [(p, os.path.join(top, os.path.relpath(p, ROOT))) for p in files_under(ROOT, pats)]
        write_zip(os.path.join(DIST, "circ-%s-source.zip" % v), entries)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
