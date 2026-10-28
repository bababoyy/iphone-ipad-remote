#!/usr/bin/env python3
"""Validate iPhone ZIP artifact and required unsigned IPA contents."""
from pathlib import Path
from zipfile import ZipFile
import plistlib
ipa=Path("build/ipa/VCRemoteBLE-unsigned.ipa")
assert ipa.is_file(), "IPA missing"
prefix="Payload/VCRemoteBLE.app/"
with ZipFile(ipa) as z:
    assert z.testzip() is None
    names=set(z.namelist())
    for name in ("VCRemoteBLE","Info.plist","index.html","NativeBridge.js"):
        assert prefix+name in names, f"IPA missing {name}"
    app=plistlib.loads(z.read(prefix+"Info.plist"))
    assert app["CFBundleExecutable"]=="VCRemoteBLE"
    assert app["NSBluetoothAlwaysUsageDescription"]
    exe=z.read(prefix+"VCRemoteBLE")
    assert exe[:4] == bytes.fromhex("cffaedfe"), "Not an arm64 Mach-O executable"
    assert z.read(prefix+"index.html")==Path("controller/index.html").read_bytes()
print("Unsigned IPA package integrity PASS")
