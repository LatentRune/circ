#!/usr/bin/env python3
"""Redraw Circ's brand pictures from brand/ and docs/images/icon.svg.

    python3 tools/brand-images.py

Writes:
    brand/sheet.webp              the theme sheet (brand/sheet.html)
    docs/images/icon-512.png      the icon at 512px, for stores and the repo
    docs/images/social.jpg        the 1200x630 card for link previews (brand/social.html)

Run tools/site-images.py first if the screenshots changed; the social card uses one.
Needs Node with the playwright package and its Chromium, and Pillow (pip install pillow).
The Google font loads from the web, so it needs a network connection.
"""

import os
import subprocess
import tempfile

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RENDER = os.path.join(ROOT, "brand", "render.js")


def render(src, size=None):
    out = tempfile.mktemp(suffix=".png")
    w, h = size or (1200, 100)
    subprocess.run(["node", RENDER, os.path.join(ROOT, src), out, str(w), str(h)], check=True, cwd=ROOT)
    img = Image.open(out)
    img.load()
    os.remove(out)
    return img


def save(img, rel, **kw):
    path = os.path.join(ROOT, rel)
    img.save(path, **kw)
    print("saved %s (%d KB)" % (rel, os.path.getsize(path) // 1024))


def main():
    save(render("brand/sheet.html").convert("RGB"), "brand/sheet.webp", quality=85, method=6)
    save(render("docs/images/icon.svg", (512, 512)), "docs/images/icon-512.png", optimize=True)
    save(render("brand/social.html", (1200, 630)).convert("RGB").crop((0, 0, 1200, 630)),
         "docs/images/social.jpg", quality=85, optimize=True, progressive=True)


if __name__ == "__main__":
    main()
