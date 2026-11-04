#!/usr/bin/env python3
"""Render the native iPhone gamepad layout (iphone-app/GamepadCanvas.swift +
App.swift header/safe-area constraints) as an SVG, without Xcode or CI.

The geometry below is a line-by-line port of GamepadCanvas.makeLayout() and
draw(_:). If you change the Swift layout, change it here too (or vice versa).

Usage:  python3 scripts/render_layout_svg.py [--hit] [-o out.svg]
  --hit   also draw touch hit regions (radius + identify() slop)

Device metrics are points, iPhone 17 Pro (402 x 874 pt, same as 16 Pro).
Safe-area insets are the iOS values for this screen class; verify on device.
"""
from __future__ import annotations
import argparse, math
from dataclasses import dataclass
from pathlib import Path

DEVICE = dict(name="iPhone 17 Pro", w=402, h=874, corner=62)
SAFE = {  # top, left, bottom, right
    "portrait": (62, 0, 34, 0),
    "landscape": (0, 62, 21, 62),
}
HEADER_H, HEADER_GAP = 48, 4

@dataclass
class Control:
    id: int; title: str; x: float; y: float; r: float; kind: str

def make_layout(w: float, h: float) -> list[Control]:
    portrait = h > w
    landscape = not portrait
    short = min(w, h)
    stickR = min(67, short * (0.13 if portrait else 0.185), w * 0.10)
    faceR = min(25, max(16, short * 0.067))
    faceSpacing = faceR * 1.83
    dR = min(23, max(16, short * 0.062))
    dStep = dR * 1.31
    shoulderR = min(31, max(19, short * 0.082))
    ls = (w * (0.15 if landscape else 0.23), h * (0.44 if landscape else 0.29))
    rs = (w * (0.69 if landscape else 0.77), h * (0.70 if landscape else 0.29))
    dc = (w * (0.30 if landscape else 0.23), h * (0.75 if landscape else 0.70))
    fc = (w * (0.86 if landscape else 0.77), h * (0.38 if landscape else 0.70))
    shoulderY = h * 0.085
    c: list[Control] = []
    add = lambda i, t, x, y, r, k: c.append(Control(i, t, x, y, r, k))
    add(1, "L", *ls, stickR, "stick")
    add(2, "R", *rs, stickR, "stick")
    add(6, "Y", fc[0], fc[1] - faceSpacing, faceR, "button")
    add(5, "X", fc[0] - faceSpacing, fc[1], faceR, "button")
    add(4, "B", fc[0] + faceSpacing, fc[1], faceR, "button")
    add(3, "A", fc[0], fc[1] + faceSpacing, faceR, "button")
    add(11, "▲", dc[0], dc[1] - dStep, dR, "directional")
    add(12, "▼", dc[0], dc[1] + dStep, dR, "directional")
    add(13, "◀", dc[0] - dStep, dc[1], dR, "directional")
    add(14, "▶", dc[0] + dStep, dc[1], dR, "directional")
    for sid, t, f in zip([9, 7, 8, 10], ["L2", "L1", "R1", "R2"], [0.075, 0.20, 0.80, 0.925]):
        add(sid, t, w * f, shoulderY, shoulderR, "button")
    systemY = h * (0.54 if landscape else 0.51)
    sysR = min(31, short * 0.083)
    add(16, "SELECT", w * 0.43, systemY, sysR, "button")
    add(15, "START", w * 0.57, systemY, sysR, "button")
    add(17, "L3", ls[0] + stickR * 0.90, ls[1] + stickR * 0.88, faceR * 0.76, "button")
    add(18, "R3", rs[0] + stickR * 0.90, rs[1] + stickR * 0.88, faceR * 0.76, "button")
    return c

def hit_extra(k: str) -> float:  # identify() slop
    return {"button": 8.0, "stick": 6.0}.get(k, 11.0)

def shape_box(c: Control):
    """Drawn bounding box (x0,y0,x1,y1), mirrors draw(_:)."""
    r = c.r
    if 7 <= c.id <= 10:  hw, hh = r * 1.39, r * 0.56
    elif c.id in (15, 16): hw, hh = r * 1.35, r * 0.60
    else: hw = hh = r
    return (c.x - hw, c.y - hh, c.x + hw, c.y + hh)

# ---------------------------------------------------------------- drawing
FACE_FILL = {3: "#224762", 4: "#4e3138", 5: "#25483c", 6: "#50432e"}
FACE_FG = {3: "#b2ddff", 4: "#ffb8c0", 5: "#a3f2ce", 6: "#ffdc96"}
FONT = "-apple-system, 'SF Pro Text', system-ui, 'Helvetica Neue', Arial, sans-serif"

def circle(x, y, r, fill, stroke=None, sw=1):
    s = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ""
    return f'<circle cx="{x:.2f}" cy="{y:.2f}" r="{r:.2f}" fill="{fill}"{s}/>'

def rrect(x0, y0, x1, y1, rad, fill, stroke=None, sw=1):
    s = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ""
    return (f'<rect x="{x0:.2f}" y="{y0:.2f}" width="{x1-x0:.2f}" height="{y1-y0:.2f}" '
            f'rx="{rad:.2f}" fill="{fill}"{s}/>')

def text(t, x, y, size, fill, weight=700, anchor="middle", family=FONT):
    t = t.replace("&", "&amp;").replace("<", "&lt;")
    return (f'<text x="{x:.2f}" y="{y:.2f}" font-family="{family}" font-size="{size:.2f}" '
            f'font-weight="{weight}" fill="{fill}" text-anchor="{anchor}" '
            f'dominant-baseline="central">{t}</text>')

def draw_controls(cs: list[Control], show_hit: bool) -> list[str]:
    out = []
    for c in cs:
        r = c.r
        if c.kind == "stick":
            out.append(circle(c.x, c.y, r, "#0e1725", "#455b78", 2))
            out.append(circle(c.x, c.y, r * 0.83, "#142133", "#2a3d55", 1))
            kr = r * 0.46
            out.append(circle(c.x, c.y, kr, "#324760", "#7892b3", 1.3))
            out.append(circle(c.x, c.y, kr * 0.62, "#354b65", "#597493", 1))
            out.append(text("LEFT STICK" if c.id == 1 else "RIGHT STICK",
                            c.x, c.y + r + 13, 9, "#8597b0", 600))
            continue
        compact = 3 <= c.id <= 6
        fill, fg = "#111a29", "#d9e4f3"
        if compact: fill, fg = FACE_FILL[c.id], FACE_FG[c.id]
        elif c.kind == "directional": fill = "#26374b"
        x0, y0, x1, y1 = shape_box(c)
        if 7 <= c.id <= 10:
            out.append(rrect(x0, y0, x1, y1, r * 0.49, fill, "#526681", 1))
        elif c.id in (15, 16):
            out.append(rrect(x0, y0, x1, y1, r * 0.55, fill, "#526681", 1))
        elif compact or c.id >= 17:
            out.append(circle(c.x, c.y, r, fill, "#63758e", 1.2))
        else:
            out.append(rrect(x0, y0, x1, y1, r * 0.23, fill, "#6a7f97", 1.2))
        size = r * 0.77 if compact else (r * 0.35 if c.id in (15, 16) else r * 0.58)
        out.append(text(c.title, c.x, c.y, size, fg))
    if show_hit:
        for c in cs:
            out.append(f'<circle cx="{c.x:.2f}" cy="{c.y:.2f}" r="{c.r + hit_extra(c.kind):.2f}" '
                       f'fill="none" stroke="#ff4fd8" stroke-width="0.8" stroke-dasharray="3 2"/>')
    return out

# ---------------------------------------------------------------- analysis
def analyse(cs: list[Control], cw: float, ch: float) -> list[str]:
    issues = []
    for c in cs:
        x0, y0, x1, y1 = shape_box(c)
        if c.kind == "stick": y1 = max(y1, c.y + c.r + 13 + 6)  # caption
        clip = []
        if x0 < 0: clip.append(f"left {-x0:.0f}pt")
        if y0 < 0: clip.append(f"top {-y0:.0f}pt")
        if x1 > cw: clip.append(f"right {x1-cw:.0f}pt")
        if y1 > ch: clip.append(f"bottom {y1-ch:.0f}pt")
        if clip: issues.append(f"CLIPPED  {c.title:<7} by " + ", ".join(clip))
    for i, a in enumerate(cs):
        for b in cs[i + 1:]:
            d = math.hypot(a.x - b.x, a.y - b.y)
            ax0, ay0, ax1, ay1 = shape_box(a); bx0, by0, bx1, by1 = shape_box(b)
            ox, oy = min(ax1, bx1) - max(ax0, bx0), min(ay1, by1) - max(ay0, by0)
            rect_like = lambda c: c.kind == "directional" or 7 <= c.id <= 10 or c.id in (15, 16)
            if a.kind == b.kind == "directional":
                continue  # D-pad arms form one cross by design; corners just touch
            if rect_like(a) and rect_like(b):
                drawn, amount = ox > 0 and oy > 0, min(ox, oy)
            else:
                drawn, amount = d < a.r + b.r, a.r + b.r - d
            if drawn:
                issues.append(f"OVERLAP  {a.title} / {b.title} drawn shapes overlap by {amount:.0f}pt")
            elif d < a.r + hit_extra(a.kind) + b.r + hit_extra(b.kind) and \
                    {a.kind, b.kind} != {"directional"}:
                issues.append(f"HIT-ZONE {a.title} / {b.title} touch regions overlap "
                              f"by {a.r + hit_extra(a.kind) + b.r + hit_extra(b.kind) - d:.0f}pt")
    for c in cs:
        if c.kind != "stick" and 2 * c.r < 44:
            issues.append(f"SMALL    {c.title:<7} {2*c.r:.0f}pt wide (Apple min 44pt)")
    return issues

# ---------------------------------------------------------------- page
def device_svg(orientation: str, show_hit: bool, ox: float, oy: float):
    portrait = orientation == "portrait"
    W, H = (DEVICE["w"], DEVICE["h"]) if portrait else (DEVICE["h"], DEVICE["w"])
    st, sl, sb, sr = SAFE[orientation]
    out = [f'<g transform="translate({ox},{oy})">']
    out.append(f'<rect x="-10" y="-10" width="{W+20}" height="{H+20}" rx="{DEVICE["corner"]+10}" fill="#2b2f36"/>')
    out.append(f'<clipPath id="scr-{orientation}"><rect width="{W}" height="{H}" rx="{DEVICE["corner"]}"/></clipPath>')
    out.append(f'<g clip-path="url(#scr-{orientation})">')
    out.append('<defs><linearGradient id="bg-%s" x1="0.3" y1="0" x2="0.7" y2="1">'
               '<stop offset="0" stop-color="#0c121c"/><stop offset="1" stop-color="#141d2c"/>'
               '</linearGradient></defs>' % orientation)
    out.append(f'<rect width="{W}" height="{H}" fill="url(#bg-{orientation})"/>')
    # safe area guide
    out.append(f'<rect x="{sl}" y="{st}" width="{W-sl-sr}" height="{H-st-sb}" fill="none" '
               f'stroke="#ffd166" stroke-width="0.8" stroke-dasharray="6 4" opacity="0.55"/>')
    # header (topBar)
    hx, hy, hw = sl, st, W - sl - sr
    out.append(text("VCREMOTE / PAD", hx + 12, hy + 24, 14, "#b0d4fc", 700, "start",
                    "ui-monospace, 'SF Mono', Menlo, monospace"))
    logo_w = 14 * 0.6 * 14 + 1.1 * 13  # monospaced estimate
    dot_x = hx + 12 + logo_w + 14
    out.append(circle(dot_x + 4, hy + 24, 4, "#e39175"))
    out.append(text("Not connected", dot_x + 15, hy + 24, 11, "#a3bad6", 500, "start"))
    gx1 = hx + hw - 9; gx0 = gx1 - 86; px1 = gx0 - 7; px0 = px1 - 48
    for x0, x1, t in ((px0, px1, "Pair"), (gx0, gx1, "⚙ Settings")):
        out.append(rrect(x0, hy + 7.5, x1, hy + 40.5, 10, "#1d2b40", "#455e82", 1))
        out.append(text(t, (x0 + x1) / 2, hy + 24, 12, "#ffffff", 600))
    out.append(f'<rect x="{hx}" y="{hy+47}" width="{hw}" height="1" fill="#2e425e"/>')
    # canvas
    cx, cy = sl, st + HEADER_H + HEADER_GAP
    cw, ch = W - sl - sr, H - sb - cy
    out.append(f'<rect x="{cx}" y="{cy}" width="{cw}" height="{ch}" fill="none" '
               f'stroke="#4fd1ff" stroke-width="0.6" stroke-dasharray="2 3" opacity="0.5"/>')
    controls = make_layout(cw, ch)
    out.append(f'<g transform="translate({cx},{cy})">')
    out += draw_controls(controls, show_hit)
    out.append('</g>')
    # hardware: Dynamic Island + home indicator
    if portrait:
        out.append(rrect(W/2 - 63, 11, W/2 + 63, 48, 18.5, "#000"))
        out.append(rrect(W/2 - 72, H - 13, W/2 + 72, H - 8, 2.5, "#ffffff"))
    else:
        out.append(rrect(11, H/2 - 63, 48, H/2 + 63, 18.5, "#000"))
        out.append(rrect(W/2 - 100, H - 10, W/2 + 100, H - 5, 2.5, "#ffffff"))
    out.append('</g></g>')
    return out, W, H, controls, (cw, ch)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--hit", action="store_true", help="draw touch hit regions")
    ap.add_argument("-o", "--out", default="docs/layout-preview/iphone17pro.svg")
    a = ap.parse_args()
    pad, gap, title_h = 40, 60, 46
    land, LW, LH, lc, lcanvas = device_svg("landscape", a.hit, pad, pad + title_h)
    port, PW, PH, pc, pcanvas = device_svg("portrait", a.hit, pad + LW + gap, pad + title_h)
    totalW = pad * 2 + LW + gap + PW
    totalH = pad * 2 + title_h + max(LH, PH)
    head = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {totalW} {totalH}" '
            f'width="{totalW}" height="{totalH}">',
            f'<rect width="{totalW}" height="{totalH}" fill="#e9edf2"/>',
            text(f"{DEVICE['name']} — GamepadCanvas (experiment/native-uikit), 1 unit = 1 pt",
                 pad, pad + 6, 18, "#1b2533", 700, "start"),
            text("Yellow dashed: safe area   Cyan dotted: canvas bounds" +
                 ("   Pink dashed: touch hit regions" if a.hit else ""),
                 pad, pad + 28, 12, "#4a5568", 500, "start")]
    svg = "\n".join(head + land + port + ["</svg>"])
    out = Path(a.out); out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(svg)
    print(f"wrote {out}")
    for name, cs, (cw, ch) in (("landscape", lc, lcanvas), ("portrait", pc, pcanvas)):
        print(f"\n[{name}] canvas {cw:.0f} x {ch:.0f} pt")
        for c in cs:
            print(f"  {c.title:<7} id={c.id:<2} center=({c.x:6.1f},{c.y:6.1f}) r={c.r:4.1f}")
        issues = analyse(cs, cw, ch)
        print("  issues:" if issues else "  no issues found")
        for i in issues: print("   ", i)

if __name__ == "__main__":
    main()
