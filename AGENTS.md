# VCRemote agent notes

Project: iPhone universal gamepad for iPad, through an injected classic GTA Vice City dylib.
Keep the project generic; no game-specific phone buttons are necessary.

## Known good
- main: experimental original touch-over-Wi-Fi version, user verified movement.
- experiment/virtual-gamepad: Wi-Fi + Apple GCVirtualController, user verified **every button works**.
- experiment/ble-link: GCVirtualController over BLE transport; both binaries compile in GitHub Actions, and user confirmed successful real-device Bluetooth pairing with game control. PIN overlay auto-hide/close fix still needs next on-device test.

## Working rules
1. Do not rewrite or disturb the proven Wi-Fi controller. Develop BLE on experiment/ble-link until real-device tests pass.
2. Build without a local Mac through the existing GitHub Actions workflow. Verify both jobs AND both artifacts, not just a green build.
3. BLE iPhone app uses the exact same controller/index.html packaged into a WKWebView. JS WebSocket shim -> WKScriptMessageHandler -> CBCentralManager. Avoid creating a second fork of the controller UI.
4. The iPad BLE receiver uses CBPeripheralManager and forwards to existing VirtualGamepad.mm. It is **not** a system Bluetooth HID profile.
5. BLE full controller snapshots are 10 bytes, 30 Hz target; server watchdog zeroes all controls after 400 ms. Never queue delayed joystick deltas.
6. iPad **host game's** Info.plist must contain NSBluetoothAlwaysUsageDescription before injection/install. This does not come from a dylib.
7. PIN is a weak, ephemeral six-digit GATT authentication mechanism; do not describe BLE as encrypted or secure. Add authenticated pairing in later iterations.
8. No Apple signing credentials should be added to CI. Produce unsigned IPA for local user signing.
9. Prefer small, reversible changes, tests, and on-device observations. Don't infer connection success from compilation or Apple framework enumeration.
10. Do not merge experimental code into main without confirmation and on-device test evidence.

Refer to docs/BLE-V1-DESIGN.md and docs/BLE-HANDOFF.md for architecture, current state and pending tests.

## Native UIKit experiment
- New experiment/native-uikit branch: replaces the iPhone WKWebView with custom UIKit GamepadCanvas and typed ControllerState, reuses iPad BLE receiver and 10-byte packet protocol.
- This branch produces VCRemoteNative-unsigned.ipa with a different bundle ID, so keep the proven BLE WebView app installed for fallback.
- Only iPhone files need updating for native work. Never modify the proven iPad BLE receiver without test evidence.
- Native Bluetooth and gamepad are not yet verified on real devices. UI must be tested for layout/ergonomics and 18 simultaneous controls.
