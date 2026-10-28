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
        for (NSString *button in @[GCInputButtonA, GCInputButtonB,
                                   GCInputButtonX, GCInputButtonY,
                                   GCInputLeftTrigger, GCInputRightTrigger,
                                   GCInputLeftShoulder, GCInputRightShoulder]) {
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
            GCInputLeftThumbstick, GCInputRightThumbstick,
            GCInputButtonA, GCInputButtonB, GCInputButtonX, GCInputButtonY,
            GCInputLeftTrigger, GCInputRightTrigger,
            GCInputLeftShoulder, GCInputRightShoulder
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
        } else {
            // Trial mapping, not a confirmed Vice City MFi button layout.
            NSString *button = nil;
            switch (identifier) {
                case 3: button = GCInputRightTrigger; break; // FIRE
                case 4: button = GCInputButtonA; break;      // ACTION
                case 5: button = GCInputButtonB; break;      // SPRINT
                case 6: button = GCInputLeftTrigger; break;  // BRAKE
            }
            if (button) [virtualPad setValue:(phase == 'e' ? 0.0 : 1.0)
                          forButtonElement:button];
        }
    }
}
