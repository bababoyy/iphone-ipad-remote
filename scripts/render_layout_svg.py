#!/usr/bin/env python3
"""Render the native iPhone gamepad layout as SVG, without Xcode or CI.

Reads iphone-app/layout.json (the same file the app embeds) through
scripts/gamepad_layout.py and draws it inside the App.swift header and
safe-area frame for each device in scripts/devices.py.

  python3 scripts/render_layout_svg.py            # all devices -> docs/layout-preview/
  python3 scripts/render_layout_svg.py --hit      # also draw touch hit regions
  python3 scripts/render_layout_svg.py --device iphone-17-pro
  python3 scripts/render_layout_svg.py --check    # CI: fail on issues not in baseline
  python3 scripts/render_layout_svg.py --update-baseline

The report flags controls that are clipped by the canvas, drawn shapes that
overlap, touch regions that overlap, and buttons under Apple's 44 pt minimum.
Text uses the host's fonts, not SF, so label widths are approximate.
"""
from __future__ import annotations
import argparse, math, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import gamepad_layout as gl
import devices as dv

ROOT = gl.ROOT
OUT_DIR = ROOT / "docs/layout-preview"
BASELINE = ROOT / "tests/layout_known_issues.txt"
FONT = "-apple-system, 'SF Pro Text', system-ui, 'Helvetica Neue', Arial, sans-serif"
MONO = "ui-monospace, 'SF Mono', Menlo, monospace"
MIN_TARGET = 44


# ---------------------------------------------------------------- primitives
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


# ---------------------------------------------------------------- controls
def draw_controls(spec, cs, show_hit):
    """Mirrors GamepadCanvas.draw(_:) in the idle (nothing held) state."""
    st = spec["stick"]
    out = []
    for c in cs:
        r = c.r
        if c.kind == "stick":
            out.append(circle(c.x, c.y, r, st["base"], st["baseStroke"], 2))
            out.append(circle(c.x, c.y, r * 0.83, st["ring"], st["ringStroke"], 1))
            kr = r * 0.46
            out.append(circle(c.x, c.y, kr, st["knob"], st["knobStroke"], 1.3))
            out.append(circle(c.x, c.y, kr * 0.62, st["cap"], st["capStroke"], 1))
            out.append(text(c.caption, c.x, c.y + r + 13, 9, st["caption"], 600))
            continue
        s = c.style
        if s["shape"]["type"] == "rect":
            hw, hh = c.half_extent()
            out.append(rrect(c.x - hw, c.y - hh, c.x + hw, c.y + hh, r * s["shape"]["corner"],
                             s["fill"], s["stroke"], s["strokeWidth"]))
        else:
            out.append(circle(c.x, c.y, r, s["fill"], s["stroke"], s["strokeWidth"]))
        out.append(text(c.title, c.x, c.y, r * s["labelScale"], s["fg"]))
    if show_hit:
        for c in cs:
            out.append(f'<circle cx="{c.x:.2f}" cy="{c.y:.2f}" r="{c.r + spec["hitSlop"][c.kind]:.2f}" '
                       f'fill="none" stroke="#ff4fd8" stroke-width="0.8" stroke-dasharray="3 2"/>')
    return out


# ---------------------------------------------------------------- analysis
def analyse(spec, cs, cw, ch):
    slop = spec["hitSlop"]
    issues = []
    for c in cs:
        hw, hh = c.half_extent()
        x0, y0, x1, y1 = c.x - hw, c.y - hh, c.x + hw, c.y + hh
        if c.kind == "stick":
            y1 = max(y1, c.y + c.r + 13 + 6)  # caption below the stick
        clip = [f"{side} {v:.0f}pt" for side, v in
                (("left", -x0), ("top", -y0), ("right", x1 - cw), ("bottom", y1 - ch)) if v > 0.5]
        if clip:
            issues.append(f"CLIPPED {c.title} by " + ", ".join(clip))
    rect_like = lambda c: c.style is not None and c.style["shape"]["type"] == "rect"
    for i, a in enumerate(cs):
        for b in cs[i + 1:]:
            if a.kind == b.kind == "directional":
                continue  # D-pad arms form one cross by design; corners just touch
            d = math.hypot(a.x - b.x, a.y - b.y)
            if rect_like(a) and rect_like(b):
                (ahw, ahh), (bhw, bhh) = a.half_extent(), b.half_extent()
                ox = min(a.x + ahw, b.x + bhw) - max(a.x - ahw, b.x - bhw)
                oy = min(a.y + ahh, b.y + bhh) - max(a.y - ahh, b.y - bhh)
                drawn, amount = ox > 0 and oy > 0, min(ox, oy)
            else:
                drawn, amount = d < a.r + b.r, a.r + b.r - d
            if drawn and amount > 0.5:
                issues.append(f"OVERLAP {a.title} / {b.title} by {amount:.0f}pt")
            else:
                hit = a.r + slop[a.kind] + b.r + slop[b.kind] - d
                if hit > 0.5:
                    issues.append(f"HIT-ZONE {a.title} / {b.title} by {hit:.0f}pt")
    for c in cs:
        # identify() hit-tests a circle of radius r + slop around every control.
        reach = c.r + slop[c.kind]
        if 2 * reach < MIN_TARGET - 0.5:
            issues.append(f"SMALL {c.title} touch target {2*reach:.0f}pt (min {MIN_TARGET}pt)")
        hw, hh = c.half_extent()
        outside = max(hw, hh) - reach
        if outside > 0.5:
            issues.append(f"UNTOUCHABLE {c.title} drawn ends {outside:.0f}pt outside touch region")
    return issues


def issue_key(issue: str) -> str:
    """Issue identity without the measurement, so small geometry changes don't
    churn the baseline: 'OVERLAP L2 / L1 by 35pt' -> 'OVERLAP L2 / L1'."""
    for sep in (" by ", " touch target ", " drawn ends "):
        if sep in issue:
            return issue.split(sep)[0]
    return issue


# ---------------------------------------------------------------- device frame
def device_group(spec, dev, orientation, show_hit, ox, oy):
    portrait = orientation == "portrait"
    W, H = dv.screen(dev, orientation)
    st, sl, sb, sr = dev["safe"][orientation]
    corner = dev["corner"]
    gid = f"{dev['key']}-{orientation}"
    out = [f'<g transform="translate({ox},{oy})">',
           f'<rect x="-10" y="-10" width="{W+20}" height="{H+20}" rx="{corner+10}" fill="#2b2f36"/>',
           f'<clipPath id="scr-{gid}"><rect width="{W}" height="{H}" rx="{corner}"/></clipPath>',
           f'<g clip-path="url(#scr-{gid})">',
           f'<defs><linearGradient id="bg-{gid}" x1="0.3" y1="0" x2="0.7" y2="1">'
           '<stop offset="0" stop-color="#0c121c"/><stop offset="1" stop-color="#141d2c"/>'
           '</linearGradient></defs>',
           f'<rect width="{W}" height="{H}" fill="url(#bg-{gid})"/>',
           f'<rect x="{sl}" y="{st}" width="{W-sl-sr}" height="{H-st-sb}" fill="none" '
           'stroke="#ffd166" stroke-width="0.8" stroke-dasharray="6 4" opacity="0.55"/>']
    # Header (App.swift configureHeader)
    hh = spec["chrome"]["headerHeight"]
    hx, hy, hw = sl, st, W - sl - sr
    mid = hy + hh / 2
    out.append(text("VCREMOTE / PAD", hx + 12, mid, 14, "#b0d4fc", 700, "start", MONO))
    dot_x = hx + 12 + 14 * 0.6 * 14 + 1.1 * 13 + 14  # monospaced width estimate
    out.append(circle(dot_x + 4, mid, 4, "#e39175"))
    out.append(text("Not connected", dot_x + 15, mid, 11, "#a3bad6", 500, "start"))
    gx1 = hx + hw - 9; gx0 = gx1 - 86; px1 = gx0 - 7; px0 = px1 - 48
    for x0, x1, t in ((px0, px1, "Pair"), (gx0, gx1, "⚙ Settings")):
        out.append(rrect(x0, mid - 16.5, x1, mid + 16.5, 10, "#1d2b40", "#455e82", 1))
        out.append(text(t, (x0 + x1) / 2, mid, 12, "#ffffff", 600))
    out.append(f'<rect x="{hx}" y="{hy+hh-1}" width="{hw}" height="1" fill="#2e425e"/>')
    # Canvas
    cx, cy, cw, ch = dv.canvas_rect(dev, orientation, spec)
    out.append(f'<rect x="{cx}" y="{cy}" width="{cw}" height="{ch}" fill="none" '
               'stroke="#4fd1ff" stroke-width="0.6" stroke-dasharray="2 3" opacity="0.5"/>')
    controls = gl.resolve(spec, cw, ch)
    out.append(f'<g transform="translate({cx},{cy})">')
    out += draw_controls(spec, controls, show_hit)
    out.append('</g>')
    # Hardware: Dynamic Island + home indicator
    if dev["island"]:
        if portrait:
            out.append(rrect(W/2 - 63, 11, W/2 + 63, 48, 18.5, "#000"))
            out.append(rrect(W/2 - 72, H - 13, W/2 + 72, H - 8, 2.5, "#ffffff"))
        else:
            out.append(rrect(11, H/2 - 63, 48, H/2 + 63, 18.5, "#000"))
            out.append(rrect(W/2 - 100, H - 10, W/2 + 100, H - 5, 2.5, "#ffffff"))
    out.append('</g></g>')
    return out, W, H, controls, (cw, ch)


def render_device(spec, dev, show_hit):
    pad, gap, title_h = 40, 60, 46
    land, LW, LH, lc, lcan = device_group(spec, dev, "landscape", show_hit, pad, pad + title_h)
    port, PW, PH, pc, pcan = device_group(spec, dev, "portrait", show_hit, pad + LW + gap, pad + title_h)
    tw, th = pad * 2 + LW + gap + PW, pad * 2 + title_h + max(LH, PH)
    legend = "Yellow dashed: safe area   Cyan dotted: canvas bounds"
    if show_hit:
        legend += "   Pink dashed: touch hit regions"
    svg = "\n".join([
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {tw} {th}" width="{tw}" height="{th}">',
        f'<rect width="{tw}" height="{th}" fill="#e9edf2"/>',
        text(f"{dev['name']} — native gamepad (iphone-app/layout.json), 1 unit = 1 pt",
             pad, pad + 6, 18, "#1b2533", 700, "start"),
        text(legend, pad, pad + 28, 12, "#4a5568", 500, "start"),
        *land, *port, "</svg>"])
    issues = {}
    for o, cs, (cw, ch) in (("landscape", lc, lcan), ("portrait", pc, pcan)):
        issues[o] = analyse(spec, cs, cw, ch), (cw, ch), cs
    return svg, issues


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--hit", action="store_true", help="also write *-hit.svg with touch regions")
    ap.add_argument("--device", choices=list(dv.BY_KEY), help="only this device")
    ap.add_argument("--out-dir", default=str(OUT_DIR))
    ap.add_argument("--check", action="store_true", help="fail if issues differ from the baseline")
    ap.add_argument("--update-baseline", action="store_true")
    ap.add_argument("--verbose", "-v", action="store_true", help="print every control's geometry")
    a = ap.parse_args()

    spec = gl.load()
    devs = [dv.BY_KEY[a.device]] if a.device else dv.DEVICES
    out_dir = Path(a.out_dir); out_dir.mkdir(parents=True, exist_ok=True)
    found = []
    for dev in devs:
        svg, issues = render_device(spec, dev, False)
        (out_dir / f"{dev['key']}.svg").write_text(svg, encoding="utf-8")
        if a.hit:
            (out_dir / f"{dev['key']}-hit.svg").write_text(render_device(spec, dev, True)[0], encoding="utf-8")
        for o, (lst, (cw, ch), cs) in issues.items():
            print(f"[{dev['key']} {o}] canvas {cw:.0f} x {ch:.0f} pt: "
                  f"{len(lst) or 'no'} issue{'s' if len(lst) != 1 else ''}")
            if a.verbose:
                for c in cs:
                    print(f"    {c.title:<7} id={c.id:<2} center=({c.x:6.1f},{c.y:6.1f}) r={c.r:4.1f}")
            for i in lst:
                print("   ", i)
                found.append(f"{dev['key']} {o}: {issue_key(i)}")
    print(f"SVGs written to {out_dir.relative_to(ROOT) if out_dir.is_relative_to(ROOT) else out_dir}")

    if a.update_baseline:
        BASELINE.write_text("# Known layout issues; CI fails on anything new.\n"
                            "# Regenerate: python3 scripts/render_layout_svg.py --update-baseline\n"
                            + "".join(f"{i}\n" for i in sorted(found)), encoding="utf-8")
        print(f"baseline updated: {len(found)} issues")
    if a.check:
        if a.device:
            sys.exit("--check needs all devices")
        known = {l.strip() for l in BASELINE.read_text(encoding="utf-8").splitlines()
                 if l.strip() and not l.startswith("#")}
        new, fixed = sorted(set(found) - known), sorted(known - set(found))
        for i in fixed:
            print("FIXED (remove from baseline):", i)
        for i in new:
            print("NEW ISSUE:", i)
        if new or fixed:
            sys.exit("layout check failed: run --update-baseline if these changes are intended")
        print(f"Layout check PASS ({len(found)} known issues, none new)")


if __name__ == "__main__":
    main()
