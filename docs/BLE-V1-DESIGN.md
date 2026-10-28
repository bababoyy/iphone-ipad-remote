# VCRemote BLE v1 design — Bitchat-inspired direct controller transport

Status: **design only, no BLE executable in this branch yet**. Base: `experiment/virtual-gamepad` (verified working by user). Preserve the existing WebSocket/hotspot build as a fallback.

## Objective

Let iPhone 17 Pro control GTA Vice City on iPad Air M3 through Bluetooth LE without personal hotspot, Wi-Fi association, an Internet connection, or any third device. **Do not emulate a Bluetooth gamepad at the OS level**: retain the proven on-iPad `GCVirtualController` injection. Only the transport between phone UI and injected dylib changes.

## Bitchat references (source of ideas, not source copied)

Source repository: https://github.com/permissionlesstech/bitchat (Unlicense).

- `bitchat/Services/BLE/BLEService+LinkLayerCentralRole.swift`: peer discovery, connect/disconnect, characteristic handling, `canSendWriteWithoutResponse` backpressure handling.
- `bitchat/Services/BLE/BLEService+LinkLayerPeripheralRole.swift`: GATT characteristic with `.writeWithoutResponse` + `.notify`, advertising, inbound writes.
- `docs/BLE-ARCHITECTURE-V3.md`: separation of the link (radio) from transport and message semantics; deterministic tests.
- General behavior worth adapting: opportunistic reconnection and link-state UI; **not** its mesh routing, multi-hop, fragmentation, gossip, Nostr, encryption protocol, store-and-forward, file transfer, packet retention, or historical retries.

## Why a native iPhone app is needed

iOS 27 Safari has **no built-in Web Bluetooth API** (https://caniuse.com/web-bluetooth). A webpage cannot directly call `CBCentralManager`. Build a small iPhone app (`WKWebView` embedding the existing universal controller HTML, plus `WKScriptMessageHandler` bridging controls to CoreBluetooth). Keep the same HTML design; do not reproduce the buttons in SwiftUI.

An alternative is a special third-party browser/extension with a BLE bridge, but not the default or a dependency for this repo.

## Transport layout

```text
iPhone native IPA                              iPad Vice City injected dylib
┌─────────────────────────────────┐           ┌─────────────────────────────────┐
│ Existing universal HTML in      │           │ CBPeripheralManager             │
│ WKWebView                       │           │ advertises VCRemote GATT UUID  │
│       │ JS-to-native bridge     │           │       │ write characteristic      │
│       ▼                         │           │       ▼                         │
│ Controller state aggregator     │ --BLE-->  │ Latest-state decoder + timeout  │
│ CBCentralManager                │           │       │                         │
│ latest-only, write-no-response  │           │       ▼                         │
│ scan, pairing and reconnect     │ <--ACK--  │ Existing VCGamepadInject        │
└─────────────────────────────────┘           │ existing GCVirtualController    │
                                              └─────────────────────────────────┘
```

Roles: **iPad = GATT peripheral**, **iPhone = central**. Use a repo-specific 128-bit UUID for the service and another UUID for the characteristic (write, write-without-response, notify). The iPad publishes while the game is foregrounded. The iPhone scans for that UUID and connects to one selected device; scanning and connection should occur only at the user's request or during a bounded reconnect attempt.

### Binary state frame (proposal)

Prefer small *full-controller-state snapshots* to individual touch-down/up messages. This corrects missed button releases after packet loss.

10-byte LE packet:
- Byte 0: `0x01` protocol version
- Byte 1: rolling sequence number
- Bytes 2–3: 16-bit button bitset, little-endian (A/B/X/Y, LB/RB/LT/RT, D-pad U/D/L/R, START/SELECT, L3/R3)
- Bytes 4–7: signed 8-bit left X/Y and right X/Y axes, `[-127,127]`
- Bytes 8–9: unsigned 8-bit L2/R2 pressures, `[0,255]` (initially on/off)

Packets are at most 10 bytes, fitting even the small default BLE ATT payload. All semantic control mapping is performed only once in the app's JS/native bridge; do not expose game-specific button labels.

The iPad discards out-of-order/duplicate sequence numbers on the current session, and applies a frame atomically on the main thread. When no state frame arrives for a measured fail-safe window (prototype suggestion 250–400 ms), **release every button and zero all sticks**. Disconnect similarly releases inputs immediately.

iPhone samples latest state, targeting 30 Hz initially, comparing observed latency and drop rate to existing hotspot mode. 60 Hz can be tested, but never assume the radio schedules it reliably. Under CoreBluetooth `canSendWriteWithoutResponse == false`, keep only the **newest state snapshot**, not an unbounded FIFO. A queued old joystick state must never play late. Periodically transmit a neutral state as a heartbeat while idle.

### Connection, PIN, authorization

- iPad advertises only a service UUID and nonsecret device label (do not put the PIN in advertisements).
- iPhone lists nearby matches, user selects the iPad, enters the existing session PIN once.
- Auth is handled **before accepting controller frames**. For the prototype, use a challenge and authenticated response, or an OS-encrypted characteristic if supported; never silently assume a 6-digit PIN provides strong cryptographic security.
- On invalid auth, refuse frames; limit retry rate. Only one authorized controller at a time. Expire a session on disconnect/timeouts and require re-auth.
- Do not log PINs or authenticated control data.
- For a stronger future version: QR-scanned high-entropy pairing key, authenticated encryption, and device binding. BLE notification ACK should indicate ready/authenticated state.
- No BLE scanning/advertising when Bluetooth is off or permission denied; show a clear UI state.

### iOS permissions and practical constraints

- Both iPhone app and modified Vice City IPA must declare `NSBluetoothAlwaysUsageDescription` in `Info.plist` (https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSBluetoothAlwaysUsageDescription). Since the iPad BLE code lives in an injected dylib, **the host game's Info.plist must be patched before installing**.
- Prefer foreground-only operation for the initial controller. Background BLE on iOS is restricted and throttled; while gaming, iPhone app stays foreground and screen unlocked.
- A successful GATT connection is not the same thing as a successfully injected GameController. Show separate statuses: discovered / connected / authenticated / receiving / controller active.
- BLE may not be lower-latency than direct hotspot Wi-Fi. Compare latency, jitter, packet loss and battery using repeatable measurements.

## Implementation steps, in safe order

1. Create a native iOS application project or Xcode-CLI target on this branch, embedding current `controller/index.html` in a `WKWebView`; test native bridge via a mocked BLE transport first.
2. Add iPhone `CBCentralManager` scan/connect/discover/write; measure success/error/connection state and show it in existing top status.
3. Add iPad `CBPeripheralManager` advertising, GATT service, auth and state frame decoder in a new file, without editing the existing Wi-Fi path.
4. Add 10-byte state codec with pure byte-array unit tests, sequence wrap tests, neutral timeout, lost-release test, and backpressure/coalescing test. Explicitly test that `A` pressed + `A` released never becomes stuck if one frame drops.
5. Make GitHub Actions build **two** artifacts on this branch: iPad `VCRemote.dylib` and an unsigned iPhone `VCRemoteBLE.ipa` (for user-side signing/sideloading). No Apple Developer credentials stored in GitHub.
6. Test on device: discover iPad without hotspot/Wi-Fi, authenticate, move both sticks + ABXY/shoulders/D-pad, stress simultaneous buttons, kill app/restart/lock screen, range edges, and ensure safety releases.
7. Compare observed responsiveness with Wi-Fi. Keep a visible Wi-Fi fallback until BLE is validated in real gameplay.

## Acceptance criteria

- On-device Bluetooth-only operation, with mobile data and personal hotspot disabled.
- iPhone natively discovers iPad, asks for the correct PIN, connects.
- Game responds via existing `GCVirtualController` pathway; every one of the 18 universal controls works.
- No stuck movement on BLE drop or app exit. Latest inputs supersede older ones.
- Game doesn't crash if Bluetooth is unavailable/denied.
- Wi-Fi/Touch build remains usable and unchanged on `main`.
- Both GitHub Actions artifacts compile, are downloaded and locally verified on real devices.

## Out of scope for v1

Bitchat mesh relay, other peoples' phones, message forwarding, network-wide anonymity, Nostr, offline queues, and native OS Bluetooth HID accessory emulation.

## References

- https://github.com/permissionlesstech/bitchat/blob/main/WHITEPAPER.md
- https://github.com/permissionlesstech/bitchat/blob/main/bitchat/Services/BLE/BLEService+LinkLayerCentralRole.swift
- https://github.com/permissionlesstech/bitchat/blob/main/bitchat/Services/BLE/BLEService+LinkLayerPeripheralRole.swift
- https://developer.apple.com/documentation/corebluetooth
- https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html
- https://caniuse.com/web-bluetooth
