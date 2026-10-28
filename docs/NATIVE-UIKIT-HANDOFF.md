# Codex handoff — UIKit native gamepad migration

Date: 2026-10-28. Base: experiment/ble-link. New branch: **experiment/native-uikit**.

## User feedback and decisions
- Existing Wi-Fi controller works; Bluetooth over CoreBluetooth **works on real iPhone/iPad hardware** (user confirmed gameplay controls behind PIN overlay).
- User disliked the WebView controller because text-selection/focus browser behavior and unpredictable layout. Requested true native UIKit instead.
- User is traveling and intends to take over later with Codex. Preserve existing BLE app; ship the native app in parallel.
- Keep iPad BLE receiver and 10-byte snapshot protocol unchanged unless there is concrete test evidence.

## This branch now contains
- iphone-app/App.swift: native UIViewController with native pairing dialog (× Close and Pair re-open), connection indicator, settings UI, BLE central. **No WKWebView or WebKit dependency**.
- iphone-app/ControllerState.swift: typed state with four analog axes + 16-bit button mask.
- iphone-app/GamepadCanvas.swift: custom UIKit-rendered gamepad with isMultipleTouchEnabled, per-UITouch ownership, touchesBegan/Moved/Ended/Cancelled; supports all 18 universal controls and simultaneous buttons and analogs.
- iphone-app/Info.plist: distinct bundle id **com.vcremote.native**, display name **VCRemote Native**, so verified BLE WebView IPA stays installed.
- scripts/build_ble_ipa.sh: compile three Swift files and package **VCRemoteNative-unsigned.ipa**, with NO HTML or JS resources.
- scripts/check_native_controller.py: source invariants for native controller.
- scripts/inspect_ipa.py: inspect unsigned IPA Mach-O, plist, required files, and absence of .html/.js and WKWebView.
- .github/workflows/build.yml: build iPhone native IPA and existing iPad dylib on this branch.

## Build verification
CI build on branch: https://github.com/bababoyy/iphone-ipad-remote/actions/runs/40684749783
Both jobs completed successfully, both artifacts available:
- VCRemoteNative-unsigned: iPhone unsigned IPA.
- VCRemote-arm64: iPad BLE dylib (unchanged underlying iPad BLE protocol and logic).

**IMPORTANT:** Successful CI build ≠ successful pairing, runtime functionality or ergonomic layout. First native app is untested on a physical iPhone. The previous Bluetooth WebView app IS user-tested and remains available on experiment/ble-link.

## Exact transport
The native app retains RemoteCentral BLE central implementation from original App.swift; updateController(_:) now accepts ControllerState rather than WebSocket-style text messages. The 30 Hz transport emits the same 10-byte state frame accepted by receiver/BLEReceiver.mm. PIN auth is still "A"+six digits, GATT write-with-response, and the iPad neutral watchdog still triggers after 400 ms silence.

App remains foreground only. Haptic taps use UIImpactFeedbackGenerator. UIController releases touches when app resigns active.

## Device acceptance test
1. Keep existing VCRemote BLE app installed and working. Install signed native IPA in parallel using the user's own signer.
2. Keep the **same known-good iPad BLE dylib**. iPad Vice City must include NSBluetoothAlwaysUsageDescription in host Info.plist.
3. Open Vice City, read PIN, open VCRemote Native, connect. Dialog must disappear on ready, Pair reopens, × hides without disconnect.
4. Test single analog and face button; simultaneously move both analogs; D-pad diagonals; shoulder triggers and simultaneous holds; START/SELECT/L3/R3. Confirm no stuck buttons on cancel/background.
5. Rotate phone to portrait/landscape; inspect for clipping/overlap, particularly near shoulder controls, center Start/Select, L3/R3.
6. Stress reconnect, BLE permission denial, loss of signal, app switching and iPad game restart.
7. Compare BLE responsiveness and haptics to previous app. Report hardware observations rather than speculating.

## Known possible improvements (not confirmed bugs)
- Custom-drawn UIKit geometry requires ergonomic device validation. The current layout is programmed relative to canvas bounds and has landscape-first and portrait fallback positions.
- The native D-pad uses individual cardinal hit regions and supports diagonals by dragging beyond a threshold. Test physical two-direction thumb drags and revise as necessary.
- Existing RemoteCentral does not notify UI immediately on every transient disconnect because it attempts auto-rescan; a native connection-state coordinator would improve feedback.
- Pairing uses a six-digit PIN without E2E encryption; harden authentication as a separate project.
- Sensitivity settings use a native UIAlertController with three presets (0.7, 1.0, 1.3) and a haptic toggle. Later use a richer native settings page and custom layout editor.
- The old browser assets remain in the repository because the **iPad Wi-Fi fallback dylib embeds controller/index.html**. They are not packaged into the native iPhone IPA.

## Workflow constraints
Do not alter main, experiment/virtual-gamepad, or experiment/ble-link to improve UIKit. Reuse the known-good 10-byte BLE protocol and iPad receiver. Run the GitHub Actions builds after changes, inspect *both* artifacts, and clearly distinguish compilation from on-device testing. No Apple signing credentials in CI.
