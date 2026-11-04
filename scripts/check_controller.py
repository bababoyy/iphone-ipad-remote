#!/usr/bin/env python3
"""Zero-dependency static checks for embedded controller interface and protocol."""
from pathlib import Path
import re, subprocess, tempfile

root=Path(__file__).resolve().parents[1]
html=(root/"controller/index.html").read_text()
native=(root/"receiver/VirtualGamepad.mm").read_text()
server=(root/"receiver/VCRemote.mm").read_text()
names=["A","B","X","Y","LB","RB","LT","RT","UP","DOWN","LEFT","RIGHT","MENU","OPTIONS","L3","R3"]
for name in names:
    assert f'data-control="{name}"' in html, f"Missing UI control {name}"
assert 'bindStick(byId(\'leftStick\'),\'LS\')' in html
assert 'bindStick(byId(\'rightStick\'),\'RS\')' in html
assert "id > (gamepadEvent ? 18 : 12)" in server
for name in ["GCInputButtonA","GCInputButtonB","GCInputButtonX","GCInputButtonY","GCInputLeftShoulder","GCInputRightShoulder","GCInputLeftTrigger","GCInputRightTrigger","GCInputDirectionPad","GCInputButtonMenu","GCInputButtonOptions","GCInputLeftThumbstickButton","GCInputRightThumbstickButton"]:
    assert name in native, f"Native input absent: {name}"
# Regressions: a connected Bluetooth/WebSocket controller must not be obscured
# by a PIN dialog. Manual dismissal must be reversible when offline.
assert "body.connected #overlay" in html, "Missing connected overlay auto-hide CSS"
assert "body.pairing-hidden #overlay" in html, "Missing manual dismissal CSS"
assert 'id="dismissPairing"' in html and 'id="showPairing"' in html
assert "byId('dismissPairing').onclick" in html
assert "byId('showPairing').onclick" in html
assert "document.body.classList.remove('pairing-hidden')" in html
js=re.search(r"<script>(.*?)</script>",html,re.S)
assert js, "Missing inline JS"
with tempfile.NamedTemporaryFile(mode="w", suffix=".js") as fp:
    fp.write(js.group(1))
    fp.flush()
    subprocess.run(["node", "--check", fp.name], check=True)
print("Controller UI protocol/static tests PASS")

# Wi-Fi server reliability/security regressions.
assert "UIApplicationWillEnterForegroundNotification" in server
assert "listenerGeneration" in server and "poll(&p,1,1000)" in server
assert "429 Too Many Requests" in server and "kMaxBadPins" in server
print("Wi-Fi server reliability checks PASS")
