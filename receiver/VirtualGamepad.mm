#import "VirtualGamepad.h"
#import <UIKit/UIKit.h>
#import <GameController/GameController.h>
#include <cmath>
#include <algorithm>

// Experimental headless GCVirtualController. Never swizzles global GCController
// behavior. Only loaded on the experiment/virtual-gamepad branch.
static GCVirtualController *virtualPad = nil;
static BOOL wanted = NO;
static BOOL connected = NO;
static BOOL dpadHeld[4] = {NO, NO, NO, NO}; // up, down, left, right

static void debugBadge(NSString *message) {
    UIWindow *window = UIApplication.sharedApplication.keyWindow;
    if (!window) window = UIApplication.sharedApplication.windows.firstObject;
    NSLog(@"[VCRemote/Gamepad] %@", message);
    if (!window) return;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(15, 72, 380, 34)];
    label.text = [@" VCRemote Gamepad: " stringByAppendingString:message];
    label.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightMedium];
    label.textColor = UIColor.whiteColor;
    label.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:.84];
    label.adjustsFontSizeToFitWidth = YES;
    label.layer.cornerRadius = 7;
    label.layer.masksToBounds = YES;
    [window addSubview:label];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 7*NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{ [label removeFromSuperview]; });
}

void VCGamepadRelease(void) {
    NSCAssert(NSThread.isMainThread, @"GameController must use main thread");
    if (!virtualPad || !connected) return;
    if (@available(iOS 17.0, *)) {
        [virtualPad setPosition:CGPointMake(0, 0) forDirectionPadElement:GCInputLeftThumbstick];
        [virtualPad setPosition:CGPointMake(0, 0) forDirectionPadElement:GCInputRightThumbstick];
        [virtualPad setPosition:CGPointMake(0, 0) forDirectionPadElement:GCInputDirectionPad];
        for (int i = 0; i < 4; ++i) dpadHeld[i] = NO;
        for (NSString *button in @[GCInputButtonA, GCInputButtonB,
                                   GCInputButtonX, GCInputButtonY,
                                   GCInputLeftTrigger, GCInputRightTrigger,
                                   GCInputLeftShoulder, GCInputRightShoulder,
                                   GCInputButtonMenu, GCInputButtonOptions,
                                   GCInputLeftThumbstickButton, GCInputRightThumbstickButton]) {
            [virtualPad setValue:0.0 forButtonElement:button];
        }
    }
}

void VCGamepadSetActive(BOOL active) {
    NSCAssert(NSThread.isMainThread, @"GameController must use main thread");
    if (!active) {
        wanted = NO;
        VCGamepadRelease();
        if (virtualPad) [virtualPad disconnect];
        connected = NO;
        return;
    }
    if (@available(iOS 17.0, *)) {
        // Supported.
    } else {
        debugBadge(@"Requires iPadOS 17+");
        return;
    }
    if (wanted) return;
    wanted = YES;
    if (!virtualPad) {
        GCVirtualControllerConfiguration *configuration =
            [[GCVirtualControllerConfiguration alloc] init];
        configuration.elements = [NSSet setWithArray:@[
            GCInputLeftThumbstick, GCInputRightThumbstick, GCInputDirectionPad,
            GCInputButtonA, GCInputButtonB, GCInputButtonX, GCInputButtonY,
            GCInputLeftTrigger, GCInputRightTrigger,
            GCInputLeftShoulder, GCInputRightShoulder,
            GCInputButtonMenu, GCInputButtonOptions,
            GCInputLeftThumbstickButton, GCInputRightThumbstickButton
        ]];
        if (@available(iOS 17.0, *)) configuration.hidden = YES; // iPhone supplies the visible interface
        virtualPad = [[GCVirtualController alloc] initWithConfiguration:configuration];
    }
    debugBadge(@"Connecting...");
    [virtualPad connectWithReplyHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!wanted) {
                [virtualPad disconnect];
                connected = NO;
                return;
            }
            if (error) {
                connected = NO;
                wanted = NO;
                debugBadge([NSString stringWithFormat:@"Failed: %@",error.localizedDescription]);
                return;
            }
            connected = YES;
            BOOL enumerated = [GCController.controllers containsObject:virtualPad.controller];
            debugBadge(enumerated ? @"Connected / enumerated" : @"Connected / not enumerated");
            NSLog(@"[VCRemote/Gamepad] GCController: %@; extended: %@; count=%lu",
                  virtualPad.controller, virtualPad.controller.extendedGamepad,
                  (unsigned long)GCController.controllers.count);
        });
    }];
}

void VCGamepadInject(NSInteger identifier, char phase, double x, double y) {
    NSCAssert(NSThread.isMainThread, @"GameController must use main thread");
    if (!wanted || !connected || !virtualPad) return;
    if (!std::isfinite(x) || !std::isfinite(y)) return;
    if (@available(iOS 17.0, *)) {
        if (identifier == 1 || identifier == 2) {
            NSString *element = identifier == 1 ? GCInputLeftThumbstick : GCInputRightThumbstick;
            CGPoint p = phase == 'e' ? CGPointMake(0, 0) :
                CGPointMake(std::max(-1.0, std::min(1.0, x)),
                            std::max(-1.0, std::min(1.0, y)));
            [virtualPad setPosition:p forDirectionPadElement:element];
        } else if (identifier >= 11 && identifier <= 14) {
            // Independent key holds permit e.g. UP + RIGHT simultaneously.
            dpadHeld[identifier - 11] = phase != 'e';
            CGPoint position = CGPointMake(
                (dpadHeld[3] ? 1.0 : 0.0) - (dpadHeld[2] ? 1.0 : 0.0),
                (dpadHeld[0] ? 1.0 : 0.0) - (dpadHeld[1] ? 1.0 : 0.0));
            [virtualPad setPosition:position forDirectionPadElement:GCInputDirectionPad];
        } else {
            NSString *button = nil;
            switch (identifier) {
                case 3: button = GCInputButtonA; break;
                case 4: button = GCInputButtonB; break;
                case 5: button = GCInputButtonX; break;
                case 6: button = GCInputButtonY; break;
                case 7: button = GCInputLeftShoulder; break;
                case 8: button = GCInputRightShoulder; break;
                case 9: button = GCInputLeftTrigger; break;
                case 10: button = GCInputRightTrigger; break;
                case 15: button = GCInputButtonMenu; break;
                case 16: button = GCInputButtonOptions; break;
                case 17: button = GCInputLeftThumbstickButton; break;
                case 18: button = GCInputRightThumbstickButton; break;
            }
            if (button) [virtualPad setValue:(phase == 'e' ? 0.0 : 1.0)
                          forButtonElement:button];
        }
    }
}
