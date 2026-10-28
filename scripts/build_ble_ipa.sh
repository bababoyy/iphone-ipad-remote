#!/usr/bin/env bash
set -euo pipefail
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
APP="$PWD/build/ipa/Payload/VCRemoteNative.app"
rm -rf "$PWD/build/ipa"
mkdir -p "$APP"
cp iphone-app/Info.plist "$APP/Info.plist"
xcrun --sdk iphoneos swiftc -target arm64-apple-ios17.0 -sdk "$SDK" \
  -parse-as-library -O -whole-module-optimization -framework UIKit \
  -framework CoreBluetooth \
  iphone-app/App.swift iphone-app/ControllerState.swift iphone-app/GamepadCanvas.swift \
  -o "$APP/VCRemoteNative"
plutil -lint "$APP/Info.plist"
file "$APP/VCRemoteNative"
(cd "$PWD/build/ipa" && /usr/bin/zip -qr VCRemoteNative-unsigned.ipa Payload)
echo "Unsigned native UIKit IPA: build/ipa/VCRemoteNative-unsigned.ipa"
