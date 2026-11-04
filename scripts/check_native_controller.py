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
# Layout lives in iphone-app/layout.json (validated by gamepad_layout.load:
# ids 1..18 exactly once, sticks 1-2, D-pad 11-14).
import sys
sys.path.insert(0,str(root/"scripts"))
import gamepad_layout
spec=gamepad_layout.load()
titles={c["id"]:c["title"] for c in spec["controls"]}
assert [titles[i] for i in (9,7,8,10)]==["L2","L1","R1","R2"], "Shoulder/trigger mapping changed"
assert "GamepadLayoutSpec.shared" in canvas and "spec.controls" in canvas
assert "embed_layout.py" in build and "LayoutData.generated.swift" in build
assert "GamepadLayout.swift" in build
for id in ("leftX","leftY","rightX","rightY","mask"):
    assert id in state
assert "pairingOverlay.isHidden=true" in app
assert "@objc private func closePairing()" in app
print("Native UIKit controller source invariants PASS")
