# VCRemote BLE native iPhone app

Foreground-only native app that wraps the existing universal controller HTML in WKWebView and replaces the WebSocket with a CoreBluetooth central. No Web Bluetooth API or hotspot needed.

Files: App.swift (UIKit/WebKit/CoreBluetooth), NativeBridge.js (WebSocket shim), Info.plist (permission), scripts/build_ble_ipa.sh (unsigned IPA build).

GitHub Actions produces an unsigned VCRemoteBLE-unsigned.ipa, which must be signed with the user's own IPA installer. Never distribute Apple signing credentials in CI.

On iPad: inject the Bluetooth-enabled dylib and add NSBluetoothAlwaysUsageDescription to the game's Info.plist before re-signing. On iPhone: sign the IPA, launch and allow Bluetooth, enter the six-digit game PIN. Keep both apps foregrounded and Bluetooth on. The iPad will advertise the service if it can initialize CoreBluetooth in the injected app.

LIMITATIONS: not verified on actual phones. A successful CI build only establishes syntax/linking. This first prototype uses a six-digit PIN over a GATT characteristic without end-to-end encryption: only use on trusted physical networks/environments. It sends 10-byte complete-state packets up to 30 times per second. On disconnection, the iPad watchdog releases all controls after 400 ms. The existing Wi-Fi mode is unchanged on its branch.
