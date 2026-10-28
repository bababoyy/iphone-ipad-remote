#pragma once
// Starts a foreground-only CoreBluetooth GATT peripheral on the game's main thread.
// The PIN comes from VCRemote's existing ephemeral session PIN.
void VCBLEStart(const char *pin);
