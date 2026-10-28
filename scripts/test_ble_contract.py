#!/usr/bin/env python3
"""Static cross-language contract checks plus independent BLE packet test vectors.
This does NOT assert that CoreBluetooth can pair on a real device."""
from pathlib import Path
import plistlib
root=Path(__file__).resolve().parents[1]
ipad=(root/"receiver/BLEReceiver.mm").read_text()
phone=(root/"iphone-app/App.swift").read_text()
plist=plistlib.loads((root/"iphone-app/Info.plist").read_bytes())
bridge=(root/"iphone-app/NativeBridge.js").read_text()
for suffix in ("801","802","803"):
    uid=f"5CB83FF0-304B-4C67-87C9-0F2D12C31{suffix}"
    assert uid in ipad and uid in phone, f"UUID {uid} inconsistent"
assert plist["NSBluetoothAlwaysUsageDescription"]
assert "VCGamepadInject" in ipad and "VCGamepadSetActive" in ipad
assert "kFrameTimeout = 0.40" in ipad, "Missing neutral watchdog"
assert "writeWithoutResponse" in ipad and "canSendWriteWithoutResponse" in phone
assert "maximumWriteValueLength" in phone
assert "WebSocket=Socket" in bridge
assert "NSBluetoothAlwaysUsageDescription" not in bridge

# Reference sample: A + R2 + D-right, left stick +127, right diagonally (-64,+64)
mask=(1<<0)|(1<<7)|(1<<11)
frame=bytes((1,42,mask&255,(mask>>8)&255,127,0,192,64,0,255))
assert frame.hex()=="012a81087f00c04000ff"
assert len(frame)==10
assert int.from_bytes(frame[2:4],"little")==mask
assert int.from_bytes(frame[6:7],"little",signed=True)==-64

# Sequence wrap and stale replay semantics from native receiver.
def accepted(new,old):
    delta=(new-old)&255
    return delta!=0 and delta<128
assert accepted(0,255)
assert accepted(16,15)
assert not accepted(15,15)
assert not accepted(254,1)
print("BLE source contract and reference vectors PASS")
