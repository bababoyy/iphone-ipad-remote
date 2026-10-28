# VCRemote Native iPhone app (UIKit)

Branch: experiment/native-uikit. This is a parallel successor to the WebView BLE prototype in experiment/ble-link. It has **no WKWebView, HTML or JavaScript packaged**. The iPad dylib and 10-byte GATT protocol are unchanged.

- App.swift: UIKit connection/status/PIN/Settings screens and existing CoreBluetooth Central.
- ControllerState.swift: typed atomic snapshot (4 analog axes + 16 button bits).
- GamepadCanvas.swift: native custom-painted controller and simultaneous multi-finger UIKit touch handlers. All 18 logical controls are supported.
- scripts/build_ble_ipa.sh: Xcode SDK command-line unsigned IPA build for GitHub Actions.
- scripts/inspect_ipa.py: checks bundle integrity and absence of WebView.

The native IPA has **a different bundle identifier** (com.vcremote.native) so it can coexist on the same iPhone with the verified old VCRemote BLE app. Keep the old app installed for fallback.

Controls: LS/RS; ABXY; L1/L2/R1/R2; D-pad, START/SELECT; L3/R3. Native haptics on buttons, sensitivity presets in UIKit Settings. Gamepad will stop sending inputs on app deactivation, and iPad has its existing 400 ms neutral watchdog.

## Testing

1. Use Actions on experiment/native-uikit, download artifact VCRemoteNative-unsigned, extract IPA and sign it via your usual iOS sideload method.
2. **Do not change iPad dylib** if your existing Bluetooth receiver works; both apps use the same BLE service UUID and 10-byte binary state contract.
3. Open GTA Vice City on iPad; open VCRemote Native iPhone app, enable Bluetooth, enter game PIN.
4. On Bluetooth connected the PIN dialog should close automatically. Press Pair to reopen, × to close it without disconnecting. You can play with the native gamepad immediately.
5. Test both analogs simultaneously, one analogue plus face-button, D-pad diagonals, shoulder buttons, Start/Select, L3/R3. Verify haptics, portrait rotation and reconnection.

Build success is not on-device UI validation. Known follow-up: ergonomic spacing, custom control size/position profiles, richer BLE diagnostics. DO NOT merge into the verified BLE branch until tested.
