# Codex handoff — VCRemote Bluetooth

Date: 2026-10-28. User is traveling, will transfer work to Codex later. This is a repository checkpoint; there is no background job in progress.

## User confirmed
1. iPhone to iPad over hotspot, touch-injection: movement works.
2. iPhone to iPad over hotspot, Apple GCVirtualController: **all universal controls work**.
3. Bluetooth: **WORKING ON REAL DEVICES** according to user: PIN authentication succeeds and controls *behind* the pairing overlay move the game. Exact latency and all individual buttons have not yet been independently measured.
4. A UI defect was found: the PIN overlay remained in front even after BLE succeeded because connected-state CSS was missing. Fixed by adding connected auto-hide, manual × dismissal and a Pair reopening button. Re-validate with the next IPA build.

## Source of truth
- Repo: bababoyy/iphone-ipad-remote, branch experiment/ble-link.
- Working web UI: controller/index.html. Avoid duplicate versions.
- iPhone: iphone-app/App.swift, iphone-app/NativeBridge.js, iphone-app/Info.plist.
- iPad: receiver/BLEReceiver.mm + .h, receiver/VirtualGamepad.mm + .h.
- Wi-Fi: receiver/VCRemote.mm and receiver/TouchBridge.mm (fallback).
- CI: .github/workflows/build.yml (two jobs, unsigned IPA + dylib).
- Reference architecture: docs/BLE-V1-DESIGN.md (some aspirational sections, implementation may differ).
- Inspiration: permissionlesstech/bitchat, specifically its BLE central/peripheral-role separation and reconnection/backpressure ideas; no Bitchat code copied.

## Current BLE wire protocol (implemented)
- iPad advertises service 5CB83FF0-304B-4C67-87C9-0F2D12C31801
- Auth characteristic 5CB83FF0-304B-4C67-87C9-0F2D12C31802, write WITH response; write seven ASCII bytes: 'A' + the six-digit game PIN. GATT success is the auth ACK.
- State characteristic 5CB83FF0-304B-4C67-87C9-0F2D12C31803, write WITHOUT response; 10 bytes:
  - [0] version 0x01
  - [1] modulo-256 sequence
  - [2..3] 16-bit button bits little-endian; bit 0 = A, B, X, Y, L1, R1, L2, R2, UP, DOWN, LEFT, RIGHT, START, SELECT, L3, R3 (in order)
  - [4..7] four signed Q7 axes: left X/Y and right X/Y (screen Y already inverted by HTML)
  - [8..9] binary L2/R2 pressures (0 or 255); the initial native receiver uses button bit values.
- iPhone sends complete snapshots at target 30 Hz, discards stale backlog when write-no-response is unavailable. iPad ignores duplicate/out-of-order sequences, releases on >400 ms silence.

## Build artifacts
GitHub Actions is configured to create:
- VCRemote-arm64: iPad dylib; inject into owned Vice City IPA. iPad *game host* Info.plist MUST add NSBluetoothAlwaysUsageDescription before signing.
- VCRemoteBLE-unsigned: unsigned iPhone IPA; use user-side signer and install. No Mac required for building.
The IPA embeds controller/index.html and NativeBridge.js. It contains a native CoreBluetooth central; it is NOT Safari Web Bluetooth.

## Real-device test order
1. Keep verified Wi-Fi IPA/dylib backup and saves.
2. Sign/install both BLE artifacts. Patch iPad host game Info.plist; allow Bluetooth access when prompted.
3. With Wi-Fi and hotspot off but Bluetooth on, open Vice City on iPad, then VCRemote BLE on iPhone.
4. Enter PIN from Vice City screen and verify discovery/auth.
5. Test both analogs, ABXY, L/R triggers/shoulders, D-pad diagonal, L3/R3 and Start/Select.
6. Pause and background iPhone app; controller should neutralize promptly. Test radio toggles, distance, reconnect, IPA restart.
7. Compare BLE motion smoothness and latency/jitter to existing hotspot implementation.
8. Save console logs of failures and only then iterate. CI success does not guarantee CoreBluetooth advertising from an injected host game.

## Known caveats to investigate
- iPad GameController connect is asynchronous; frames arriving before registration are discarded until the next snapshot.
- iPad BLE receiver retains authorized central's UUID until game relaunch; after a 400 ms input timeout it disables the virtual controller but keeps GATT authorization. A different phone may not connect until restart.
- PIN over unencrypted GATT characteristic is not cryptographic authenticated pairing; protect this in future.
- iPhone app uses Swift compiler via CLI rather than a generated Xcode project. It should be signed by user tools; verify actual installation and launch.
- Swift UI status currently only reports ready/failure; richer scan/reconnect telemetry would help debugging.
- Touch fallback is available from the Wi-Fi build, not the BLE native app (which operates exclusively in virtual gamepad mode).
- BLE update interval/connection parameters are ultimately controlled by iOS and are not guaranteed to match 30 Hz timer.
- If BLE advertisement from an injected host app fails, try foreground permission and host plist first, then verify CoreBluetooth entitlements/OS restrictions; don't assume generic hardware pairing.

## Next safe iteration
- Add on-device logs or visible BLE state diagnostics (radio state -> advertising -> discovered -> connected -> PIN ACK -> state received -> GCVirtualController connected).
- Test the complete workflow and fix concrete device-reported problems rather than redesigning working UI.
- Optional: protocol fuzzing/test vectors, session authorization hardening, run-time transport selection in single app, conditional BLE power management, minimal latency metrics.
