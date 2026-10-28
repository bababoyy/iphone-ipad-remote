#!/usr/bin/env bash
set -euo pipefail
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
APP="$PWD/build/ipa/Payload/VCRemoteBLE.app"
mkdir -p "$APP"
cp iphone-app/Info.plist "$APP/Info.plist"
cp iphone-app/NativeBridge.js "$APP/NativeBridge.js"
cp controller/index.html "$APP/index.html"
xcrun --sdk iphoneos swiftc -target arm64-apple-ios17.0 -sdk "$SDK" \
  -parse-as-library -O -whole-module-optimization -framework UIKit -framework WebKit \
  -framework CoreBluetooth iphone-app/App.swift -o "$APP/VCRemoteBLE"
plutil -lint "$APP/Info.plist"
file "$APP/VCRemoteBLE"
(cd "$PWD/build/ipa" && /usr/bin/zip -qr VCRemoteBLE-unsigned.ipa Payload)
echo "Unsigned IPA ready: build/ipa/VCRemoteBLE-unsigned.ipa"
