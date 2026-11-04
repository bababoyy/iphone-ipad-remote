#!/usr/bin/env python3
"""Reference implementation of the gamepad layout engine.

Reads iphone-app/layout.json and resolves it for a canvas size, exactly like
iphone-app/GamepadLayout.swift. Keep the two resolve() functions in step:
tests/test_layout.py checks this one against golden coordinates, and both
read the same JSON, so a layout change made in the JSON shows up in the SVG
preview and the app alike.
"""
from __future__ import annotations
import json
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LAYOUT_PATH = ROOT / "iphone-app/layout.json"
KINDS = ("stick", "button", "directional")
SHAPES = ("circle", "rect")


@dataclass
class Control:
    id: int
    title: str
    kind: str
    x: float
    y: float
    r: float
    style: dict | None   # None for sticks
    caption: str | None

    def half_extent(self) -> tuple[float, float]:
        """Half width/height of the drawn shape."""
        if self.style and self.style["shape"]["type"] == "rect":
            s = self.style["shape"]
            return self.r * s["halfWidth"], self.r * s["halfHeight"]
        return self.r, self.r


def load(path: Path = LAYOUT_PATH) -> dict:
    spec = json.loads(path.read_text(encoding="utf-8"))
    validate(spec)
    return spec


def validate(spec: dict) -> None:
    """Structural checks so a malformed layout fails in CI, not on the phone."""
    assert spec.get("version") == 1, "layout.json: unsupported version"
    for k in ("headerHeight", "headerGap"):
        assert isinstance(spec["chrome"][k], (int, float)), f"chrome.{k}"
    assert set(spec["hitSlop"]) == set(KINDS), "hitSlop must cover every kind"
    for name, oriented in spec["sizes"].items():
        for o in ("landscape", "portrait"):
            rule = oriented[o]
            assert isinstance(rule["short"], (int, float)), f"sizes.{name}.{o}.short"
            assert set(rule) <= {"short", "min", "max", "maxWidth"}, f"sizes.{name}.{o}: unknown key"
    for name, oriented in spec["groups"].items():
        for o in ("landscape", "portrait"):
            assert len(oriented[o]) == 2, f"groups.{name}.{o}"
    for name, st in spec["styles"].items():
        assert st["shape"]["type"] in SHAPES, f"styles.{name}.shape"
        if st["shape"]["type"] == "rect":
            for k in ("halfWidth", "halfHeight", "corner"):
                assert isinstance(st["shape"][k], (int, float)), f"styles.{name}.shape.{k}"
        for k in ("fill", "heldFill", "fg", "stroke"):
            assert _is_hex(st[k]), f"styles.{name}.{k}"
    for k, v in spec["stick"].items():
        assert _is_hex(v), f"stick.{k}"
    ids = [c["id"] for c in spec["controls"]]
    assert sorted(ids) == list(range(1, 19)), f"controls must be ids 1..18 exactly once, got {sorted(ids)}"
    for c in spec["controls"]:
        where = f"control {c['id']}"
        assert c["kind"] in KINDS, where
        assert c["size"] in spec["sizes"], f"{where}: size"
        assert ("group" in c) != ("at" in c), f"{where}: needs exactly one of group/at"
        if "group" in c:
            assert c["group"] in spec["groups"], f"{where}: group"
        else:
            for o in ("landscape", "portrait"):
                assert len(c["at"][o]) == 2, f"{where}: at.{o}"
        if "offset" in c:
            assert len(c["offset"]) == 2 and c.get("offsetUnit") in spec["sizes"], f"{where}: offset"
        if c["kind"] == "stick":
            assert "caption" in c, f"{where}: stick needs caption"
        else:
            assert c.get("style") in spec["styles"], f"{where}: style"
    # The iPad receiver maps ids 1-2 to sticks and 11-14 to the D-pad.
    kinds = {c["id"]: c["kind"] for c in spec["controls"]}
    assert all(kinds[i] == "stick" for i in (1, 2)), "ids 1,2 must be sticks"
    assert all(kinds[i] == "directional" for i in (11, 12, 13, 14)), "ids 11-14 must be D-pad"


def _is_hex(s) -> bool:
    return isinstance(s, str) and len(s) == 7 and s[0] == "#" and \
        all(ch in "0123456789abcdefABCDEF" for ch in s[1:])


def size(rule: dict, short: float, w: float) -> float:
    # Same order as GamepadLayout.swift: scale, then min, max, maxWidth.
    r = short * rule["short"]
    if "min" in rule: r = max(r, rule["min"])
    if "max" in rule: r = min(r, rule["max"])
    if "maxWidth" in rule: r = min(r, w * rule["maxWidth"])
    return r


def resolve(spec: dict, w: float, h: float) -> list[Control]:
    o = "portrait" if h > w else "landscape"
    short = min(w, h)
    sizes = {n: size(v[o], short, w) for n, v in spec["sizes"].items()}
    out = []
    for c in spec["controls"]:
        fx, fy = spec["groups"][c["group"]][o] if "group" in c else c["at"][o]
        x, y = w * fx, h * fy
        if "offset" in c:
            unit = sizes[c["offsetUnit"]]
            x += c["offset"][0] * unit
            y += c["offset"][1] * unit
        r = sizes[c["size"]] * c.get("radiusScale", 1.0)
        style = spec["styles"][c["style"]] if c["kind"] != "stick" else None
        out.append(Control(c["id"], c["title"], c["kind"], x, y, r, style, c.get("caption")))
    return out
