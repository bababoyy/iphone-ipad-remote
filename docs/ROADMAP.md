# VCRemote roadmap

Last updated: 2026-11-04. Working branch: `claude/amazing-meitner-n2x1sh` (based on `experiment/native-uikit`).

The aim is to iterate on the iPhone controller **on a computer**, and to spend
real-device test sessions only where a device is the only way to know. Each
item says how it is verified:

- **PC**: checked locally / in the Linux CI job (`layout` job, seconds, no macOS minutes).
- **CI**: needs the macOS GitHub Actions build (compiles Swift / Objective-C++).
- **Device**: needs the signed app on a real iPhone and/or iPad.

A green CI build never proves pairing, touch feel or game input (see `AGENTS.md`).

## Status at a glance

| Track | State |
|---|---|
| Phase 0 – layout test environment | Done on this branch, pending CI (Swift compile) |
| Reliability fixes 1–4 (BLE watchdog, BLE slot, Wi-Fi listener, Wi-Fi PIN limit) | Committed, pending CI + device |
| Phase 1 – fix current layout | In progress: portrait layout done (PC) |
| Phases 2–4 | Planned |

## Phase 0 — layout test environment ✅ (pending CI)

Goal: one source of truth for the gamepad layout that both the app and the
computer preview read, so the SVG can never drift from the app.

- `iphone-app/layout.json`: positions (canvas fractions), radii rules, colours,
  shapes, hit slop, header size. Array order = draw order and touch priority.
- App: `scripts/embed_layout.py` embeds the JSON into
  `LayoutData.generated.swift`; `GamepadLayout.swift` decodes it;
  `GamepadCanvas.swift` and the header in `App.swift` read it.
- Computer: `scripts/gamepad_layout.py` (reference engine),
  `scripts/render_layout_svg.py` (SVG for iPhone SE, 17 Pro, 17 Pro Max,
  landscape + portrait, optional hit regions, issue report).
- Tests (PC): `tests/test_layout.py` checks the JSON reproduces the original
  hard-coded layout (`tests/layout_golden.json`), and
  `render_layout_svg.py --check` fails on any clipping/overlap/touch issue not
  listed in `tests/layout_known_issues.txt`.
- CI: new `layout` job on Ubuntu; the native IPA job now also runs on manual
  (`workflow_dispatch`) builds of any branch.

Exit criteria: `layout` job green ✅ locally; native IPA job compiles the new Swift
files (**CI**, outstanding); app looks unchanged on a device (**Device**, can be
folded into the Phase 1 device session).

## Phase 1 — fix the current layout (no new behaviour)

Known problems from the preview (`tests/layout_known_issues.txt`):

- ✅ Portrait (layout.json only): sticks moved to the bottom (y 79 %) and
  enlarged (r ≈ 56–66 pt, was 40); D-pad and ABXY above them (y 48 %);
  SELECT/START apart at 38 %/62 %; shoulders inside the screen and spaced
  (smaller pills in portrait). No CLIPPED/OVERLAP left on any device.
- ✅ L3/R3 moved outside the stick ring (L3 outer-left, R3 outer-right) in both
  orientations; this also removed the landscape L/L3 overlap without crowding
  the D-pad. Their touch regions still border the stick's (by design, the
  smaller control wins).
- All devices: shoulder and SELECT/START pills are drawn 1–4 pt wider than their
  circular touch region (ends do not respond); face buttons' touch regions
  overlap by 1–3 pt.
- Header: in portrait on iPhone SE "Not connected" is cut off by the Pair button.
- Landscape: 48 pt header is ~12 % of the height; consider a slimmer or
  auto-hiding bar.
- Not visible in SVG: defer system edge gestures
  (`preferredScreenEdgesDeferringSystemGestures`) so thumbs near the edges do not
  open Control Center / go home.

Work in `layout.json` first (**PC**), then `--update-baseline` and
`tests/test_layout.py --update`. Touch-region shape (pill vs circle) needs a
small change in `identify()` and in `analyse()` (**CI**).

Exit criteria: baseline has no CLIPPED/OVERLAP/UNTOUCHABLE entries; one device
session confirms look and that every control responds (**Device**).

## Phase 2 — interaction experiments

The SVG is static, so interaction is tried in a **browser prototype** that reads
the same `layout.json` and can be opened on the iPhone without signing an IPA
(touch only; no iPad connection).

- Floating left stick: the stick centre appears where the thumb lands on the
  left half.
- Right side as trackpad (relative drag → camera) vs. classic right stick,
  switchable for side-by-side comparison.

Pick a winner in the browser (**PC/phone browser**), port to `GamepadCanvas`
(**CI**), verify feel in-game (**Device**). Protocol and iPad side unchanged.

## Phase 3 — playing without looking

- Distinct haptic patterns per button / D-pad direction.
- Swipe-to-select face buttons (one zone, flick direction = A/B/X/Y).
- Gyro aim on the right stick while L2 is held (CoreMotion, iPhone only).

Only meaningful on hardware: batch into one **Device** session.

## Phase 4 — customisation

- Drag-and-resize layout editor writing a user copy of `layout.json`.
- Saved profiles ("Vice City", "Generic", "One-hand portrait").

Mostly **PC/CI** because the editor only edits the JSON the preview already renders.

## Parallel track — transport and stability

- Reliability fixes 1–4 (commit `c30f966`): CI compile (**CI**), then on iPad:
  BLE stall does not drop the controller; reconnect after phone app restart;
  Wi-Fi URL still answers after lock/unlock; wrong-PIN lockout (**Device**).
  Note: fixes 1–2 change the iPad BLE receiver, which `AGENTS.md` treats as
  proven; they were made at the owner's request and must be device-tested
  before replacing the known-good dylib.
- Send BLE snapshots immediately on change (keep the 30 Hz timer as heartbeat)
  to remove up to 33 ms of input latency (**CI** + **Device**).
- Merge proven branches into `main` once device evidence exists (owner decision,
  `AGENTS.md` rule 10).
