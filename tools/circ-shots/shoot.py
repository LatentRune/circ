#!/usr/bin/env python3
"""Circ screenshots without the game.

Runs the addon's real Lua against a stand-in for the game's widget system (ui.lua) and a
scripted world (world.lua + a scenario), then draws what the addon built as HTML and
screenshots it with headless Chromium.

    python3 shoot.py                 # every scenario in scenarios/
    python3 shoot.py combat idle     # just these
    python3 shoot.py --html-only     # skip the PNGs (open the .html files in a browser)
    python3 shoot.py --dump=DIR      # write what was drawn as JSON, for compare.py

Environment: CIRC_ADDON (the addon folder, default ../../src), CIRC_SHOTS_OUT
(where pages and PNGs go, default ../../screenshots).

Needs: lupa (pip install lupa) and, for PNGs, Node with the playwright package.
"""
import colorsys, hashlib, html, json, os, re, subprocess, sys

import lupa
from lupa import lua51

HERE = os.path.dirname(os.path.abspath(__file__)) + "/"
ADDON = os.path.normpath(os.environ.get("CIRC_ADDON") or HERE + "../../src") + "/"
# Where pages and PNGs go: screenshots/ at the top of the repo unless CIRC_SHOTS_OUT says.
OUT = os.path.normpath(os.environ.get("CIRC_SHOTS_OUT") or HERE + "../../screenshots") + "/"


def run_scenario(path):
    # The game's Lua is 5.1, so the addon runs on 5.1 here too.
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    g = L.globals()
    g.SIM_DIR, g.ADDON_DIR = HERE, ADDON
    for f in ("ui.lua", "world.lua", "sim.lua"):
        L.execute(open(HERE + f).read())
    L.execute(open(path).read())
    items, mouse = L.eval("{Dump()}")[1], L.eval("{Dump()}")[2]
    meta = to_py(g.SHOT) or {}
    world = g.WORLD
    state = {
        "chat": to_py(world.chat) or [],
        "errors": to_py(world.errors) or [],
        "sent": to_py(world.sent) or [],
        "popup": world.popup,
        "saved": to_py(g.CircDB),
    }
    return to_py(items), to_py(mouse), meta, state


def to_py(v):
    """Lua values to JSON-ready Python. Arrays become lists; other tables become dicts
    with string keys, so saved variables keyed by item ID can be written and compared."""
    if lua51.lua_type(v) == "table":
        keys = list(v.keys())
        if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [to_py(v[k]) for k in sorted(keys)]
        return {str(k): to_py(v[k]) for k in keys}
    if isinstance(v, float) and v == int(v) and abs(v) < 2**53:
        return int(v)
    if isinstance(v, bytes):
        return v.decode("utf-8", "replace")
    return v


# ---------------------------------------------------------------- drawing

def css_rgba(c, alpha=1.0):
    r, g, b, a = (list(c) + [1, 1, 1, 1])[:4]
    return "rgba(%d,%d,%d,%.3f)" % (round(r * 255), round(g * 255), round(b * 255), a * alpha)


def mul(a, b):
    if not a: return b
    if not b: return a
    return [x * y for x, y in zip((list(a) + [1] * 4)[:4], (list(b) + [1] * 4)[:4])]


# The class icon sheet's cells (world.lua's CLASS_ICON_TCOORDS), drawn as class-colored tiles.
CLASS_BY_COORD = {
    (0, 0.25, 0, 0.25): "WARRIOR", (0.25, 0.496, 0, 0.25): "MAGE", (0.496, 0.742, 0, 0.25): "ROGUE",
    (0.742, 0.988, 0, 0.25): "DRUID", (0, 0.25, 0.25, 0.5): "HUNTER", (0.25, 0.496, 0.25, 0.5): "SHAMAN",
    (0.496, 0.742, 0.25, 0.5): "PRIEST", (0.742, 0.988, 0.25, 0.5): "WARLOCK", (0, 0.25, 0.5, 0.75): "PALADIN"}
CLASS_COLOR = {"WARRIOR": "#c79c6e", "MAGE": "#40c7eb", "ROGUE": "#fff569", "DRUID": "#ff7d0a", "HUNTER": "#abd473",
               "SHAMAN": "#0070de", "PRIEST": "#ffffff", "WARLOCK": "#8787ed", "PALADIN": "#f58cba"}

RAID = {1: ("★", "#ffe23a"), 2: ("●", "#ff8a1a"), 3: ("◆", "#c25cff"), 4: ("▲", "#3ce05a"),
        5: ("☾", "#cfe3ff"), 6: ("■", "#3a9bff"), 7: ("✖", "#ff3b3b"), 8: ("☠", "#f2f2f2")}

# Icons we can't load are drawn as tiles; a few get a recognizable label.
ICON_LABELS = {"questionmark": "?", "coin": "COIN", "fabric": "CLO", "ingot": "BAR"}


def icon_tile(path):
    name = re.split(r"[\\/]", path or "")[-1]
    hue = int(hashlib.md5(name.encode()).hexdigest()[:4], 16) / 65535
    r1, g1, b1 = colorsys.hls_to_rgb(hue, 0.42, 0.55)
    r2, g2, b2 = colorsys.hls_to_rgb(hue, 0.18, 0.6)
    low = name.lower().replace("_", "")
    label = next((v for k, v in ICON_LABELS.items() if k in low), None)
    if not label:
        parts = [p for p in re.split(r"[_\s]", name) if p and p.lower() not in ("spell", "ability", "inv", "misc", "nature", "shadow", "holy", "fire", "frost")]
        label = (parts[-1][:3] if parts else "?").upper()
    bg = "linear-gradient(135deg, rgb(%d,%d,%d), rgb(%d,%d,%d))" % (r1 * 255, g1 * 255, b1 * 255, r2 * 255, g2 * 255, b2 * 255)
    return bg, label


COLOR_RE = re.compile(r"\|c([0-9a-fA-F]{8})|\|r|\|n|\|T(.*?)\|t|\|H.*?\|h|\|h|\|\|")

# Inline textures we can draw: coins and the online / offline dots.
INLINE = {"goldicon": "#f2c230", "silvericon": "#c9cdd2", "coppericon": "#c4793a",
          "statusicon-online": "#3fdc4a", "statusicon-offline": "#7a7a7a"}


def inline_texture(spec):
    path = spec.split(":")[0].lower().replace("\\", "/")
    name = path.split("/")[-1]
    col = next((c for k, c in INLINE.items() if k in name), None)
    if col:
        size = "0.7em"
        return ('<span style="display:inline-block;width:%s;height:%s;border-radius:50%%;background:%s;'
                'margin:0 1px;vertical-align:-0.05em;box-shadow:inset 0 -1px 1px rgba(0,0,0,.4)"></span>' % (size, size, col))
    return '<span style="display:inline-block;width:.8em;height:.8em;background:#555"></span>'


def rich(text, base):
    """WoW escape codes to HTML spans."""
    out, stack, pos = [], [], 0
    for m in COLOR_RE.finditer(text):
        out.append(html.escape(text[pos:m.start()]))
        tok = m.group(0)
        if tok.startswith("|c"):
            h = m.group(1)
            out.append('<span style="color:#%s">' % h[2:])
            stack.append(1)
        elif tok == "|r":
            if stack:
                stack.pop(); out.append("</span>")
        elif tok == "|n":
            out.append("<br>")
        elif tok.startswith("|T"):
            out.append(inline_texture(m.group(2) or ""))
        elif tok == "||":
            out.append("|")
        pos = m.end()
    out.append(html.escape(text[pos:]))
    out.extend("</span>" for _ in stack)
    return "".join(out)


OUTLINE = "text-shadow: 1px 0 0 #000, -1px 0 0 #000, 0 1px 0 #000, 0 -1px 0 #000, 1px 1px 0 #000, -1px -1px 0 #000, 1px -1px 0 #000, -1px 1px 0 #000;"


def draw(item):
    k = item["kind"]
    box = "left:%.2fpx;top:%.2fpx;width:%.2fpx;height:%.2fpx;" % (item["x"], item["y"], item["w"], item["h"]) if "x" in item else ""
    alpha = item.get("alpha", 1)
    if k == "texture":
        style = box + "opacity:%.3f;" % alpha
        path = (item.get("path") or "")
        low = path.lower()
        if item.get("blend") == "ADD":
            style += "mix-blend-mode:plus-lighter;"
        if item.get("desat"):
            style += "filter:grayscale(1);"
        if item.get("raid"):
            glyph, col = RAID.get(int(item["raid"]), ("?", "#fff"))
            fs = min(item["w"], item["h"]) * 0.9
            return ('<div class="r" style="%sdisplay:flex;align-items:center;justify-content:center;'
                    'font-size:%.1fpx;color:%s;%s">%s</div>' % (style, fs, col, OUTLINE, glyph))
        if item.get("color") or "white8x8" in low or not path:
            c = mul(item.get("color") or [1, 1, 1, 1], item.get("vc"))
            if item.get("round"):
                style += "border-radius:50%;"
            return '<div class="r" style="%sbackground:%s"></div>' % (style, css_rgba(c))
        vc = item.get("vc") or [1, 1, 1, 1]
        if "spark" in low:
            c = css_rgba(vc)
            return ('<div class="r" style="%sbackground:radial-gradient(ellipse at center, %s 0%%, %s 22%%, rgba(0,0,0,0) 68%%)"></div>'
                    % (style, css_rgba([1, 1, 1, vc[3] if len(vc) > 3 else 1]), c))
        if "charactercreate-classes" in low:
            cls = CLASS_BY_COORD.get(tuple(round(x, 3) for x in (item.get("coord") or [])[:4]), "?")
            col = CLASS_COLOR.get(cls, "#888")
            fs = max(5, min(item["w"], item["h"]) * 0.5)
            return ('<div class="r icon" style="%sbackground:%s;color:#111;font-size:%.1fpx;justify-content:center;align-items:center;padding:0">%s</div>'
                    % (style, col, fs, cls[:2]))
        coin = next((c for k, c in INLINE.items() if k in low), None)
        if coin:  # coin icons and status dots drawn as textures
            return '<div class="r" style="%sborder-radius:50%%;background:%s;transform:scale(.8)"></div>' % (style, coin)
        if "trackingborder" in low:  # the round frame around a minimap button
            return ('<div class="r" style="left:%.2fpx;top:%.2fpx;width:%.2fpx;height:%.2fpx;border-radius:50%%;'
                    'border:3px solid #b8953f;box-sizing:border-box;opacity:%.3f"></div>'
                    % (item["x"] + 2, item["y"] + 2, item["w"] * 0.6, item["h"] * 0.6, alpha))
        if "page-" in low and "spellbookicon" in low:  # the guide's arrows
            glyph = "&#9664;" if "prev" in low else "&#9654;"
            dim = "disabled" in low
            return ('<div class="r" style="%sdisplay:flex;align-items:center;justify-content:center;border-radius:50%%;'
                    'background:#3a2a10;color:%s;font-size:%.1fpx">%s</div>' % (style, "#666" if dim else "#ffd100", item["h"] * 0.5, glyph))
        if "minimapface" in low:
            return '<div class="r" style="%sborder-radius:50%%;background:radial-gradient(circle,#4a5a3a,#22301f);box-shadow:0 0 0 3px #6b5a33"></div>' % style
        if "icons" in low or low.startswith("fileid:"):
            bg, label = icon_tile(path)
            fs = max(5, min(item["w"], item["h"]) * 0.26)
            return ('<div class="r icon" style="%sbackground:%s;font-size:%.1fpx">%s</div>' % (style, bg, fs, html.escape(label)))
        if "stateicon" in low:  # the game's combat state icon: crossed swords
            fs = min(item["w"], item["h"]) * 0.85
            return ('<div class="r" style="%sdisplay:flex;align-items:center;justify-content:center;'
                    'font-size:%.1fpx;color:#ffd200;%s">&#9876;</div>' % (style, fs, OUTLINE))
        if "slider" in low:
            return '<div class="r" style="%sbackground:#c9a227;border-radius:3px;transform:scale(0.6,0.9)"></div>' % style
        return '<div class="r unknown" style="%s" title="%s"></div>' % (style, html.escape(path))
    if k == "text":
        n = item.get("narrow", 1)
        just = {"LEFT": "left", "RIGHT": "right"}.get(item.get("justify"), "center")
        if item.get("wrap"):  # a set width with word wrap: lines break, starting at the top
            inner = ("position:absolute;left:0;top:0;width:%.2fpx;transform:scaleX(%.3f);transform-origin:left top;"
                     "text-align:%s;white-space:normal;font-size:%.2fpx;line-height:1.15;color:%s;%s"
                     % (item["w"] / n, n, just, item["size"], css_rgba(item["color"]), OUTLINE if item.get("outline") else ""))
        else:
            inner = ("position:absolute;left:0;top:50%%;width:%.2fpx;transform:translateY(-50%%) scaleX(%.3f);"
                     "transform-origin:left center;text-align:%s;white-space:nowrap;%s"
                     "font-size:%.2fpx;line-height:1.15;color:%s;%s"
                     % (item["w"] / n, n, just, "overflow:hidden;text-overflow:ellipsis;" if item.get("clip") else "", item["size"], css_rgba(item["color"]), OUTLINE if item.get("outline") else ""))
        return ('<div class="r" style="%sopacity:%.3f"><div style="%s">%s</div></div>'
                % (box, alpha, inner, rich(item["text"], item["color"])))
    if k == "sweep":
        # A cooldown's pie from 12 o'clock clockwise. Reversed, the dark part is the time
        # that has passed; otherwise it's the time left.
        deg = 360 * item["done"]
        dark = css_rgba(item["color"])
        if item.get("reverse"):
            grad = "conic-gradient(%s 0deg %.1fdeg, transparent %.1fdeg 360deg)" % (dark, deg, deg)
        else:
            grad = "conic-gradient(transparent 0deg %.1fdeg, %s %.1fdeg 360deg)" % (deg, dark, deg)
        hand = ""
        if item.get("edge"):  # the bright hand on the sweep's leading edge
            hand = ('<div style="position:absolute;left:50%%;top:0;width:1.5px;height:50%%;margin-left:-0.75px;'
                    'background:rgba(255,240,200,.95);box-shadow:0 0 2px #fff;transform-origin:50%% 100%%;transform:rotate(%.1fdeg)"></div>' % deg)
        return '<div class="r" style="%sopacity:%.3f;background:%s;overflow:hidden">%s</div>' % (box, alpha, grad, hand)
    if k == "tooltip":
        lines = []
        for i, l in enumerate(item["lines"]):
            cls = "big" if l.get("big") else ""
            wrap = "normal" if l.get("wrap") else "nowrap"
            right = ""
            if l.get("right"):
                right = '<span style="float:right;margin-left:12px;color:%s">%s</span>' % (css_rgba([l["rr"], l["rg"], l["rb"]]), rich(l["right"], None))
            lines.append('<div class="%s" style="color:%s;white-space:%s">%s%s</div>'
                         % (cls, css_rgba([l["r"], l["g"], l["b"]]), wrap, right, rich(l["text"], None) or "&nbsp;"))
        pos = ""
        o, m, anchor = item.get("owner"), item.get("mouse"), item.get("anchor") or ""
        if anchor == "ANCHOR_CURSOR" and m:
            pos = "left:%.1fpx;bottom:calc(100%% - %.1fpx);" % (m["x"] + 14, m["y"] - 4)
        elif o and anchor == "ANCHOR_BOTTOMRIGHT":
            pos = "left:%.1fpx;top:%.1fpx;" % (o["x"] + o["w"], o["y"] + o["h"])
        elif o and anchor == "ANCHOR_RIGHT":
            pos = "left:%.1fpx;top:%.1fpx;" % (o["x"] + o["w"] + 2, o["y"])
        elif o:
            pos = "left:%.1fpx;bottom:calc(100%% - %.1fpx);" % (o["x"], o["y"] - 2)
        elif m:
            pos = "left:%.1fpx;bottom:calc(100%% - %.1fpx);" % (m["x"] + 14, m["y"] - 4)
        return '<div class="tip" style="%s">%s</div>' % (pos, "".join(lines))
    return ""


CURSOR = ('<svg class="cursor" style="left:%.1fpx;top:%.1fpx" width="14" height="20" viewBox="0 0 14 20">'
          '<path d="M1 1 L1 16 L5 12 L8 19 L10.5 18 L7.5 11 L13 11 Z" fill="#e8d9a8" stroke="#2a1f0a" stroke-width="1.2"/></svg>')

PAGE = """<!doctype html><html><head><meta charset="utf-8"><title>%(title)s</title><style>
html,body{margin:0;background:#0b0d10;}
#screen{position:relative;width:%(w)dpx;height:%(h)dpx;overflow:hidden;font-family:'Liberation Sans',Arial,sans-serif;
  background:radial-gradient(ellipse at 50%% 35%%, #3d4a3a 0%%, #262f27 45%%, #14191a 100%%);}
#screen::before{content:"";position:absolute;inset:0;background:
  radial-gradient(circle at 20%% 70%%, rgba(120,140,90,.18), transparent 40%%),
  radial-gradient(circle at 80%% 20%%, rgba(90,110,140,.16), transparent 45%%);}
.r{position:absolute;box-sizing:border-box;}
.icon{display:flex;align-items:flex-start;justify-content:flex-start;padding:1px 0 0 2px;color:rgba(255,255,255,.55);font-weight:bold;letter-spacing:-.3px;
  box-shadow:inset 0 0 0 1px rgba(0,0,0,.5), inset 0 8px 10px rgba(255,255,255,.12);overflow:hidden;}
.unknown{background:repeating-linear-gradient(45deg,rgba(255,0,255,.35) 0 3px,transparent 3px 6px);outline:1px dashed #f0f;}
.tip{position:absolute;background:rgba(6,8,22,.92);border:1px solid #5d5d6b;border-radius:4px;padding:6px 8px;max-width:260px;
  font-size:12px;line-height:1.3;box-shadow:0 2px 8px rgba(0,0,0,.6);}
.tip .big{font-size:14px;margin-bottom:2px;}
.cursor{position:absolute;}
.chat{position:absolute;left:12px;bottom:40px;width:430px;font-size:12.5px;line-height:1.3;color:#fff;
  text-shadow:1px 1px 0 #000;background:rgba(0,0,0,.25);padding:4px 6px;}
.err{position:absolute;left:0;right:0;text-align:center;color:#ff2020;font-size:16px;text-shadow:1px 1px 0 #000;}
.caption{position:absolute;left:8px;top:6px;color:#9aa;font:12px 'Liberation Sans',sans-serif;}
</style></head><body><div id="screen">%(body)s</div>
<script>
// The area worth keeping: everything drawn, plus a margin.
window.bounds = function(){
  let l=1e9,t=1e9,r=-1e9,b=-1e9;
  document.querySelectorAll('#screen > *').forEach(e=>{
    if(e.classList.contains('caption')) return;
    const q=e.getBoundingClientRect(); if(q.width<=0||q.height<=0) return;
    l=Math.min(l,q.left);t=Math.min(t,q.top);r=Math.max(r,q.right);b=Math.max(b,q.bottom);});
  const m=%(margin)d; return {x:Math.max(0,l-m),y:Math.max(0,t-m),width:r-l+2*m,height:b-t+2*m};
};
</script></body></html>"""


def chat_panel(state, meta):
    """The chat window, bottom left, with the last lines printed; red error text on top."""
    out = []
    lines = (state.get("chat") or [])[-meta.get("chatLines", 12):]
    if lines and meta.get("chat", True):
        rows = "".join('<div>%s</div>' % rich(l, None) for l in lines)
        out.append('<div class="chat">%s</div>' % rows)
    for i, e in enumerate((state.get("errors") or [])[-3:]):
        out.append('<div class="err" style="top:%dpx">%s</div>' % (120 + i * 18, rich(e, None)))
    return out


def page(title, items, mouse, meta, state):
    body = [draw(i) for i in items] + chat_panel(state, meta)
    if mouse and meta.get("cursor", True):
        body.append(CURSOR % (mouse["x"] - 1, mouse["y"] - 1))
    return PAGE % {"title": html.escape(title), "w": 1366, "h": 768, "body": "\n".join(body),
                   "margin": int(meta.get("margin", 24))}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    html_only = "--html-only" in sys.argv
    dump = next((a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--dump=")), None)
    sdir = HERE + "scenarios/"
    names = args or sorted(f[:-4] for f in os.listdir(sdir) if f.endswith(".lua"))
    pages, failed = [], []
    for name in names:
        try:
            items, mouse, meta, state = run_scenario(sdir + name + ".lua")
        except lua51.LuaError as e:
            print("FAILED %s: %s" % (name, e)); failed.append(name); continue
        if dump:  # what was drawn and what Circ did, as data, for compare.py; no pages
            os.makedirs(dump, exist_ok=True)
            with open(os.path.join(dump, name + ".json"), "w") as out:
                json.dump({"items": items, "mouse": mouse, "meta": meta, "state": state}, out, indent=1, sort_keys=True)
            print("dumped %s (%d things)" % (name, len(items)))
            continue
        os.makedirs(OUT, exist_ok=True)
        path = OUT + name + ".html"
        open(path, "w").write(page(meta.get("title", name), items, mouse, meta, state))
        pages.append(path)
        print("drew %s (%d things)" % (name, len(items)))
    if pages and not html_only:
        subprocess.run(["node", HERE + "shoot.js"] + pages, check=True)
    if failed:
        sys.exit("%d scenario(s) failed: %s" % (len(failed), ", ".join(failed)))


if __name__ == "__main__":
    main()
