#!/usr/bin/env python3
"""Source-only native controller regressions. Real multi-touch requires device tests."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
app=(root/"iphone-app/App.swift").read_text()
canvas=(root/"iphone-app/GamepadCanvas.swift").read_text()
state=(root/"iphone-app/ControllerState.swift").read_text()
build=(root/"scripts/build_ble_ipa.sh").read_text()
assert "WKWebView" not in app and "WebKit" not in app
assert "NativeBridge" not in build and "controller/index.html" not in build
assert "touchesBegan" in canvas and "touchesMoved" in canvas
assert "touchesCancelled" in canvas and "isMultipleTouchEnabled = true" in canvas
assert "canvas.releaseAll()" in app and "UIApplication.willResignActiveNotification" in app
assert "onChange?(state)" in canvas and "updateController(_ controller: ControllerState)" in app
for id in (1,2,3,4,5,6,11,12,13,14,15,16,17,18):
    assert f"add({id}," in canvas, f"Missing control ID {id}"
assert "let shoulders = [9,7,8,10]" in canvas, "Missing shoulder/trigger mapping"
for id in ("leftX","leftY","rightX","rightY","mask"):
    assert id in state
assert "pairingOverlay.isHidden=true" in app
assert "@objc private func closePairing()" in app
print("Native UIKit controller source invariants PASS")
