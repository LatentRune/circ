#!/usr/bin/env python3
"""Redraw the README's and website's screenshots from the current code, as small WebP files.

    python3 tools/site-images.py            # every picture docs/ and README.md use
    python3 tools/site-images.py ledger     # just these

Runs the circ-shots scenarios of the same names (tools/circ-shots/scenarios/) and saves each
as docs/images/shots/<name>.webp. WebP keeps the pages light: about a tenth of the PNG.
Needs what circ-shots needs, plus Pillow (pip install pillow).
"""

import glob
import os
import re
import subprocess
import sys
import tempfile

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = os.path.join(ROOT, "docs", "images", "shots")

# What to keep of the 1366x768 screen, in screen pixels (x, y, width, height); the pictures
# are drawn at 2x. Most scenarios show the main window, so that's the default; None keeps
# everything the scenario drew.
WINDOW = (372, 134, 622, 526)
CROPS = {
    "vendor": (0, 600, 470, 150),
    "tooltip": (884, 266, 250, 104),
}


def used_names():
    # Every images/shots/<name>.webp the pages point at
    names = set()
    pages = glob.glob(os.path.join(ROOT, "docs", "*.html")) + [os.path.join(ROOT, "README.md")]
    for page in pages:
        with open(page, encoding="utf-8") as fh:
            names.update(re.findall(r"images/shots/([a-z0-9-]+)\.webp", fh.read()))
    return sorted(names)


def main():
    names = sys.argv[1:] or used_names()
    os.makedirs(SHOTS, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for name in names:
            crop = CROPS.get(name, WINDOW)
            env = dict(os.environ, CIRC_SHOTS_OUT=tmp, CIRC_SHOTS_CLIP=",".join(map(str, crop or ())))
            subprocess.run([sys.executable, os.path.join(ROOT, "tools", "circ-shots", "shoot.py"), name],
                           env=env, check=True, stdout=subprocess.DEVNULL)
            out = os.path.join(SHOTS, name + ".webp")
            Image.open(os.path.join(tmp, name + ".png")).convert("RGB").save(out, "WEBP", quality=82, method=6)
            print("saved %s (%d KB)" % (os.path.relpath(out, ROOT), os.path.getsize(out) // 1024))


if __name__ == "__main__":
    main()
