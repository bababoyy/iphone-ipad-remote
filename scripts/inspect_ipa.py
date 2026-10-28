#!/usr/bin/env python3
"""Validate native iPhone IPA: NO HTML/JS/WKWebView packaged."""
from pathlib import Path
from zipfile import ZipFile
import plistlib
ipa=Path("build/ipa/VCRemoteNative-unsigned.ipa")
assert ipa.is_file(), "Native IPA missing"
prefix="Payload/VCRemoteNative.app/"
with ZipFile(ipa) as z:
    assert z.testzip() is None
    names=set(z.namelist())
    for name in ("VCRemoteNative","Info.plist"):
        assert prefix+name in names, f"IPA missing {name}"
    assert all(not name.endswith((".html",".js")) for name in names), "Web files shipped"
    app=plistlib.loads(z.read(prefix+"Info.plist"))
    assert app["CFBundleExecutable"]=="VCRemoteNative"
    assert app["CFBundleIdentifier"]=="com.vcremote.native"
    assert app["NSBluetoothAlwaysUsageDescription"]
    exe=z.read(prefix+"VCRemoteNative")
    assert exe[:4]==bytes.fromhex("cffaedfe"), "Not arm64 Mach-O"
    assert b"WKWebView" not in exe, "Unexpected WKWebView in native binary"
print("Native UIKit IPA integrity PASS")
