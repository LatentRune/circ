#!/usr/bin/env python3
"""Checks the layout rules that keep Circ easy to work on. Run before a pull request; CI
runs it too.

    python3 tools/check.py

- Every .lua file under src/ is listed in Circ.toc, and every listed file exists.
- Every file starts with a comment that names it: "-- features/Bags.lua: ...".
- Layers only use the layers below them: core/ and data/, then features/, ui/, settings/
  and dev/. A name a file puts on ns (ns.Union, ns.UI, ...) belongs to its layer.
- core/ and features/ work things out and don't draw: no frames, textures, font strings,
  popups, tooltips or chat output (ns:Print is fine), except where the game makes core/
  do it (the event frame, Print, and the version checks in core/Compat.lua).
- Game events go through ns:On (core/Events.lua) and timers through ns:After / ns:Every
  (core/Timers.lua), so /circ cpu can see what each part costs.
- Plain Lua 5.1, which is what the game runs: no goto, no // and no utf8 library.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "src")
LAYERS = {"core": 0, "data": 0, "features": 1, "ui": 2, "settings": 3, "dev": 4}

DRAWING = re.compile(r"CreateFrame|CreateTexture|CreateFontString|StaticPopup|ShowPopup|GameTooltip"
                     r"|ItemRefTooltip|HookScript|DEFAULT_CHAT_FRAME|UIErrorsFrame|:SetPoint\(|:Show\(\)"
                     r"|:Hide\(\)|:SetShown\(|SetColorTexture")
# Where core/ has to touch the game's frames anyway
DRAWING_OK = {"core/Events.lua", "core/Namespace.lua", "core/Compat.lua"}
EVENTS = re.compile(r":RegisterEvent\(|:RegisterUnitEvent\(")
TIMERS = re.compile(r"C_Timer\.")
NOT_51 = re.compile(r"\bgoto\b|//|\butf8\.")
DEFINES = [re.compile(r"^\s*ns\.(\w+)\s*="), re.compile(r"^\s*function\s+ns[.:](\w+)")]
USES = re.compile(r"\bns[.:](\w+)")


def code_of(line):
    """The line without its comment and without the insides of its strings."""
    line = re.sub(r'"(\\.|[^"\\])*"', '""', line)
    line = re.sub(r"'(\\.|[^'\\])*'", "''", line)
    return line.split("--", 1)[0]


def main():
    problems = []
    listed = []
    with open(os.path.join(ADDON, "Circ.toc")) as f:
        for line in f:
            m = re.match(r"^\s*([^#\s]\S*\.lua)\s*$", line)
            if m:
                listed.append(m.group(1).replace("\\", "/"))
    on_disk = sorted(os.path.relpath(os.path.join(d, n), ADDON).replace(os.sep, "/")
                     for d, _, files in os.walk(ADDON) for n in files if n.endswith(".lua"))
    for f in listed:
        if f not in on_disk:
            problems.append(f"Circ.toc lists {f}, which doesn't exist")
    for f in on_disk:
        if f not in listed:
            problems.append(f"{f} isn't listed in Circ.toc, so the game won't load it")
    if len(set(listed)) != len(listed):
        problems.append("Circ.toc lists a file twice")

    sources = {}
    for rel in on_disk:
        with open(os.path.join(ADDON, rel), encoding="utf-8") as f:
            sources[rel] = f.read().split("\n")

    # Which layer each ns name belongs to: the lowest layer that defines it
    owner = {}
    for rel, lines in sources.items():
        layer = LAYERS.get(rel.split("/", 1)[0])
        if layer is None:
            problems.append(f"{rel}: put files in one of {', '.join(LAYERS)}")
            continue
        for line in lines:
            for d in DEFINES:
                m = d.match(code_of(line))
                if m and (m.group(1) not in owner or owner[m.group(1)][0] > layer):
                    owner[m.group(1)] = (layer, rel)

    names = {v: k for k, v in LAYERS.items() if k != "data"}
    for rel, lines in sources.items():
        top = rel.split("/", 1)[0]
        layer = LAYERS.get(top)
        if layer is None:
            continue
        if not lines or not lines[0].startswith("-- " + rel + ":"):
            problems.append(f"{rel}: start with a comment that names the file and says what it's for (\"-- {rel}: ...\")")
        if top == "data":
            continue
        for i, line in enumerate(lines, 1):
            code = code_of(line)
            if layer <= 1 and rel not in DRAWING_OK and DRAWING.search(code):
                problems.append(f"{rel}:{i}: {top}/ works things out and doesn't draw; move this to ui/")
            if rel != "core/Events.lua" and EVENTS.search(code):
                problems.append(f"{rel}:{i}: listen with ns:On (core/Events.lua)")
            if rel != "core/Timers.lua" and top != "dev" and TIMERS.search(code):
                problems.append(f"{rel}:{i}: use ns:After or ns:Every (core/Timers.lua)")
            if NOT_51.search(code):
                problems.append(f"{rel}:{i}: the game runs Lua 5.1: no goto, // or utf8")
            for m in USES.finditer(code):
                o = owner.get(m.group(1))
                if o and o[0] > layer and o[1] != rel:
                    problems.append(f"{rel}:{i}: {top}/ can't use ns.{m.group(1)} from {names[o[0]]}/ ({o[1]});"
                                    " pass it down with a callback or ns:Fire instead")

    if problems:
        print("\n".join(problems))
        sys.exit(1)
    print(f"ok: {len(on_disk)} files, all listed, layers clean")


if __name__ == "__main__":
    main()
