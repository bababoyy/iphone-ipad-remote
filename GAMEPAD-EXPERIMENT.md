# VCRemote — universal Gamepad UI

**Branch:** `experiment/virtual-gamepad`  
**Status:** ARM64 build tested in CI; full button layout requires on-device testing.

## Design reference and attribution

The original HTML/CSS/JS is authored specifically for VCRemote, with layout inspiration (standard ABXY diamond, dual analogs, D-pad, L/R shoulders and menu buttons) from [KaifCoding/virtual-gamepad](https://github.com/KaifCoding/virtual-gamepad), an open-source MIT-licensed project. We did **not** copy project code or assets. Original MIT license: [LICENSE](https://github.com/KaifCoding/virtual-gamepad/blob/main/LICENSE). The layout is intentionally game-agnostic.

## Controls

| Button on iPhone | Apple `GCVirtualController` element | Protocol ID |
|---|---|---|
| Left stick | `GCInputLeftThumbstick` | 1 |
| Right stick | `GCInputRightThumbstick` | 2 |
| A, B, X, Y | `GCInputButtonA/B/X/Y` | 3–6 |
| L1, R1 | `GCInputLeftShoulder/GCInputRightShoulder` | 7–8 |
| L2, R2 | `GCInputLeftTrigger/GCInputRightTrigger` | 9–10 |
| D-pad ↑↓←→ | `GCInputDirectionPad` | 11–14 |
| START, SELECT | `GCInputButtonMenu/GCInputButtonOptions` | 15–16 |
| L3, R3 | `GCInputLeftThumbstickButton/GCInputRightThumbstickButton` | 17–18 |

The underlying GameController API is a **software virtual gamepad** (not Bluetooth or kernel HID). The iPad app must accept these input elements. A title may ignore some buttons even if the virtual controller connects.

## What changed from the first experimental build

- Universal ergonomically laid-out controller, landscape-first with portrait fallback.
- Standard gamepad mapping, rather than Vice City-specific FIRE/ACTION controls.
- Multiple concurrent pointers for analogs, D-pad, triggers and face buttons.
- D-pad diagonals, held buttons and reliable release on pointer cancellation/background/disconnect.
- In-page Settings: sensitivity 0.5×–1.5× and optional previous Touch fallback.
- Gamepad mode enabled automatically on connection. Phone Safari over hotspot.
- Page includes a view-only preview at `http://iPad-IP:8765/?preview=1` even before entering a PIN (no game input in this mode).

**Important for touch fallback:** The legacy Touch backend still maps only two sticks and IDs 3–6 (A/B/X/Y) to the original game-specific coordinates. L/R buttons, D-pad, L3/R3, START/SELECT need Virtual Gamepad mode.

## Install and test

1. Keep your verified working IPA and saved games backed up.
2. Open [GitHub Actions](https://github.com/bababoyy/iphone-ipad-remote/actions/workflows/build.yml?query=branch%3Aexperiment%2Fvirtual-gamepad), select a successful run on this branch, and download `VCRemote-arm64`.
3. Replace your *existing* injected `VCRemote.dylib`; re-sign and reinstall Vice City.
4. Connect to the iPad's local URL in iPhone Safari; enter the on-screen PIN.
5. Test A, B, X, Y; L1/L2/R1/R2; D-pad (including diagonal); START/SELECT; both sticks, L3/R3.
6. If something fails, state the specific button, not only "gamepad doesn't work"; the game might lack a binding for that input.

This is not adapted or ported source from KaifCoding: the original author is credited solely for UX inspiration.
