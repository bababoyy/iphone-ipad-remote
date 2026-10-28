# Virtual Gamepad experiment (iPadOS 17+)

Branch: `experiment/virtual-gamepad`. The stable `main` branch is untouched.

## What this tests
Native Apple `GCVirtualController`, not kernel-level Bluetooth/USB HID. The injected dylib creates a hidden `GCController` through Apple's GameController framework, and incoming phone data changes gamepad axes/buttons using supported APIs.

Unlike the touch mode, this tests whether the **classic** GTA Vice City notices the virtual controller and consumes its MFi profile. Game-specific behavior is **not** verified.

## Test
1. From Actions, use the successful run **on this experiment branch**, not the previous main artifact.
2. Replace the injected dylib in your *own* Vice City IPA, re-sign and install; preserve a backup of the working IPA and game saves.
3. Open the game's local URL on iPhone Safari and connect with the PIN.
4. Start in **Touch** mode; confirm movement still works.
5. Select **Virtual Gamepad**. The iPad temporarily shows "Connected / enumerated" if GameController has registered the virtual device.
6. Try the left/right analog sticks, FIRE, ACTION, SPRINT, BRAKE. If there is no movement, return to Touch. A "Connected" badge proves registration, **not** that Vice City uses the device.

### Trial mapping
| Phone | Virtual input |
|---|---|
| Left stick | GCInputLeftThumbstick |
| Right stick | GCInputRightThumbstick |
| FIRE | GCInputRightTrigger |
| ACTION | GCInputButtonA |
| SPRINT | GCInputButtonB |
| BRAKE | GCInputLeftTrigger |

The exact Vice City action mapping remains unverified. Analog Y is inverted because Safari screen coordinates grow downward while gamepad vertical positive points upward.

### Safety
Gamepad is created lazily when selected and disconnected on Touch selection or WebSocket close. Existing touch fallback remains. No permission or global HID privileges are required. If Vice City only enumerates controllers at launch, the dynamic connect notification may be insufficient: report that observation for a follow-up startup-mode experiment.

Do not present this as a physical HID device and do not use the virtual controller's presence as proof the game accepted gamepad input.
