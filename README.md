# VCRemote — iPhone controller for iPad GTA Vice City

**Experimental source prototype. Not yet tested on an actual iPad.**

VCRemote uses iPhone Safari as a gamepad for the **classic iOS GTA: Vice City**. An injected iPad dylib serves a web controller on port 8765 and translates Wi-Fi control messages into in-process UIKit touch events. It does **not** emulate a real Bluetooth/MFi gamepad and has not been confirmed to work with iPadOS 27.

## Build without a Mac

1. Open **Actions → Build VCRemote dylib** and run the workflow (a push also triggers the workflow).
2. If the workflow succeeds, download the artifact named `VCRemote-arm64`.
3. Inject the `VCRemote.dylib` into your **own, legally obtained classic Vice City IPA**, re-sign and install it using your IPA tool. Do not inject into the Netflix/Definitive Edition without additional compatibility work.
4. Back up game saves first. If supported by your injection/signing workflow, add `NSLocalNetworkUsageDescription` to the game's Info.plist.
5. Start the game and note the temporary in-game badge: `http://<iPad IP>:8765` and a six-digit PIN.
6. Connect iPad to your iPhone's Personal Hotspot or both devices to the same trusted Wi-Fi. Open that URL in **iPhone Safari** and enter the PIN.
7. Use the **Settings** button in the phone page to calibrate the normalized touch coordinates to the actual positions of Vice City's touch controls. The sample defaults are illustrative.

The iPad must keep the game foregrounded. Hotspot does not require a functioning public Internet connection to pass local controller data, but the hotspot Wi-Fi link must remain active.

## Files

- `controller/index.html`: phone control UI, local HTML, no app install.
- `receiver/VCRemote.mm`: HTTP + WebSocket server, PIN, messages and game overlay.
- `receiver/TouchBridge.mm`: private UIKit / IOHID synthetic multitouch, likely sensitive to iPadOS version.
- `scripts/embed.py`: embeds page as a C header before compilation.
- `.github/workflows/build.yml`: macOS-hosted arm64 iOS build and artifact.

## Safety and limitations

LAN HTTP and WebSocket traffic are **not encrypted**; PIN authentication is not a substitute for a trusted LAN. Never forward TCP 8765 to the Internet. Private UIKit APIs can break or crash on iOS updates, especially app-only injection on iPadOS 27. If the server/page work but game input doesn't, the touch backend must be investigated on-device; this repo does not guarantee a working gamepad. Use only apps and binaries you are permitted to modify. No Rockstar files or game assets are distributed.

See the downloadable VCRemote prototype ZIP from the ChatGPT conversation for the original extended implementation. This repository contains a smaller independently compilable implementation for the first device tests.
