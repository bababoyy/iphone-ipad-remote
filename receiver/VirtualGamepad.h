#pragma once
#import <Foundation/Foundation.h>
// All functions require the UIKit main thread.
// This is an Apple GameController software device, not a kernel/Bluetooth HID device.
void VCGamepadSetActive(BOOL active);
void VCGamepadInject(NSInteger identifier, char phase, double x, double y);
void VCGamepadRelease(void);
