#!/usr/bin/env python3
"""Layout regression test: layout.json, resolved by scripts/gamepad_layout.py,
must reproduce tests/layout_golden.json for every device/orientation.

The golden file was captured from the hard-coded GamepadCanvas.makeLayout()
before the layout moved to JSON. When a layout change is intentional, refresh
it with:  python3 tests/test_layout.py --update
"""
import json, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import gamepad_layout as gl
import devices

GOLDEN = ROOT / "tests/layout_golden.json"
TOL = 1e-6


def snapshot(spec):
    out = {}
    for dev in devices.DEVICES:
        for o in ("portrait", "landscape"):
            cw, ch = devices.canvas_size(dev, o, spec)
            out[f"{dev['key']}/{o}"] = {"canvas": [cw, ch], "controls": [
                {"id": c.id, "x": round(c.x, 6), "y": round(c.y, 6), "r": round(c.r, 6)}
                for c in gl.resolve(spec, cw, ch)]}
    return out


def main():
    spec = gl.load()
    current = snapshot(spec)
    if "--update" in sys.argv:
        GOLDEN.write_text(json.dumps(current, indent=1) + "\n")
        print(f"updated {GOLDEN.relative_to(ROOT)}")
        return
    golden = json.loads(GOLDEN.read_text())
    assert golden.keys() == current.keys(), f"cases differ: {golden.keys() ^ current.keys()}"
    bad = []
    for case, g in golden.items():
        c = current[case]
        if any(abs(a - b) > TOL for a, b in zip(g["canvas"], c["canvas"])):
            bad.append(f"{case}: canvas {g['canvas']} -> {c['canvas']}")
        for gc, cc in zip(g["controls"], c["controls"]):
            if gc["id"] != cc["id"]:
                bad.append(f"{case}: order changed at id {gc['id']} -> {cc['id']}")
            elif any(abs(gc[k] - cc[k]) > TOL for k in ("x", "y", "r")):
                bad.append(f"{case}: id {gc['id']} {gc} -> {cc}")
    assert not bad, "layout differs from golden (run with --update if intended):\n  " + "\n  ".join(bad)
    print(f"Layout golden PASS ({len(golden)} device/orientation cases)")


if __name__ == "__main__":
    main()
