"""iPhone screen profiles used by the layout preview and tests (points).

Safe-area insets assume the app hides the status bar (App.swift
prefersStatusBarHidden). Values for notched/Dynamic Island phones are the
standard iOS insets for these screen classes; confirm on a device when a
control sits within a few points of an edge.
"""
DEVICES = [
    {"key": "iphone-se", "name": "iPhone SE (3rd gen)", "w": 375, "h": 667, "corner": 0,
     "island": False,
     "safe": {"portrait": (0, 0, 0, 0), "landscape": (0, 0, 0, 0)}},
    {"key": "iphone-17-pro", "name": "iPhone 17 Pro", "w": 402, "h": 874, "corner": 62,
     "island": True,
     "safe": {"portrait": (62, 0, 34, 0), "landscape": (0, 62, 21, 62)}},
    {"key": "iphone-17-pro-max", "name": "iPhone 17 Pro Max", "w": 440, "h": 956, "corner": 66,
     "island": True,
     "safe": {"portrait": (62, 0, 34, 0), "landscape": (0, 62, 21, 62)}},
]
BY_KEY = {d["key"]: d for d in DEVICES}


def screen(dev, orientation):
    return (dev["w"], dev["h"]) if orientation == "portrait" else (dev["h"], dev["w"])


def canvas_rect(dev, orientation, spec):
    """(x, y, w, h) of GamepadCanvas, mirroring App.swift constraints:
    header pinned to the safe-area top, canvas below it down to safe bottom."""
    W, H = screen(dev, orientation)
    top, left, bottom, right = dev["safe"][orientation]
    chrome = spec["chrome"]
    y = top + chrome["headerHeight"] + chrome["headerGap"]
    return left, y, W - left - right, H - bottom - y


def canvas_size(dev, orientation, spec):
    _, _, w, h = canvas_rect(dev, orientation, spec)
    return w, h
