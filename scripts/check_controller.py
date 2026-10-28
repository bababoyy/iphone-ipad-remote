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
js=re.search(r"<script>(.*?)</script>",html,re.S)
assert js, "Missing inline JS"
with tempfile.NamedTemporaryFile(mode="w", suffix=".js") as fp:
    fp.write(js.group(1))
    fp.flush()
    subprocess.run(["node", "--check", fp.name], check=True)
print("Controller UI protocol/static tests PASS")
