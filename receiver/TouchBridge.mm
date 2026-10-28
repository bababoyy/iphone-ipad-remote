#import "TouchBridge.h"
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#include <cmath>

// In-process UIKit/HID simulation, uses private APIs; experimental on iPadOS 27.
@interface UITouch (VCPrivate)
- (void)setWindow:(UIWindow *)window;
- (void)setView:(UIView *)view;
- (void)setTapCount:(NSUInteger)n;
- (void)setTimestamp:(NSTimeInterval)timestamp;
- (void)setPhase:(UITouchPhase)phase;
- (void)_setLocationInWindow:(CGPoint)point resetPrevious:(BOOL)reset;
- (void)_setIsFirstTouchForView:(BOOL)first;
- (void)_setHidEvent:(CFTypeRef)event;
@end
@interface UIEvent (VCPrivate)
- (void)_clearTouches;
- (void)_addTouch:(UITouch *)touch forDelayedDelivery:(BOOL)delayed;
- (void)_setHIDEvent:(CFTypeRef)event;
@end
@interface UIApplication (VCPrivate)
- (UIEvent *)_touchesEvent;
@end

typedef struct { uint32_t hi, lo; } VCAbsoluteTime;
typedef CFTypeRef (*HandFn)(CFAllocatorRef, VCAbsoluteTime, uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,
                            double,double,double,double,double,Boolean,Boolean,uint32_t);
typedef CFTypeRef (*FingerFn)(CFAllocatorRef, VCAbsoluteTime, uint32_t,uint32_t,uint32_t,
                              double,double,double,double,double,double,double,double,double,double,
                              Boolean,Boolean,uint32_t);
typedef void (*SetFn)(CFTypeRef,uint32_t,int);
typedef void (*AppendFn)(CFTypeRef,CFTypeRef);
static HandFn handFn;
static FingerFn fingerFn;
static SetFn setFn;
static AppendFn appendFn;
static BOOL hidReady;
static dispatch_once_t hidOnce;

static void initializeHID(void) {
    dispatch_once(&hidOnce, ^{
        void *lib = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW | RTLD_LOCAL);
        if (!lib) lib = dlopen("/System/Library/PrivateFrameworks/IOKit.framework/IOKit", RTLD_NOW | RTLD_LOCAL);
        if (!lib) return;
        handFn = (HandFn)dlsym(lib,"IOHIDEventCreateDigitizerEvent");
        fingerFn = (FingerFn)dlsym(lib,"IOHIDEventCreateDigitizerFingerEventWithQuality");
        setFn = (SetFn)dlsym(lib,"IOHIDEventSetIntegerValue");
        appendFn = (AppendFn)dlsym(lib,"IOHIDEventAppendEvent");
        hidReady = handFn && fingerFn && setFn && appendFn;
        if (!hidReady) NSLog(@"[VCRemote] private HID methods not present");
    });
}

static NSMutableDictionary<NSNumber *, UITouch *> *contacts;
static UIWindow *targetWindow;

static UIWindow *gameWindow(void) {
    UIApplication *app = UIApplication.sharedApplication;
    if (app.keyWindow) return app.keyWindow;
    for (UIWindow *w in app.windows)
        if (!w.hidden && w.windowLevel == UIWindowLevelNormal) return w;
    return nil;
}

static CFTypeRef createHID(void) {
    initializeHID();
    if (!hidReady) return NULL;
    uint64_t clock = mach_absolute_time();
    VCAbsoluteTime t = {(uint32_t)(clock >> 32), (uint32_t)clock};
    CFTypeRef hand = handFn(kCFAllocatorDefault,t,3,0,0,2,0,0,0,0,0,0,false,true,0);
    if (!hand) return NULL;
    setFn(hand,(11u << 16) + 25,1); // isDisplayIntegrated
    for (NSNumber *key in contacts) {
        UITouch *touch = contacts[key];
        CGPoint p = [touch locationInView:targetWindow];
        bool down = touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled;
        uint32_t mask = touch.phase == UITouchPhaseMoved ? 4 : 3;
        CFTypeRef finger = fingerFn(kCFAllocatorDefault,t,
            (uint32_t)key.integerValue,(uint32_t)key.integerValue,mask,
            p.x,p.y,0,0,0,5,5,1,1,1,down,down,0);
        if (finger) {
            setFn(finger,(11u << 16) + 25,1);
            appendFn(hand,finger);
            CFRelease(finger);
        }
    }
    return hand;
}

static BOOL dispatchTouches(void) {
    UIApplication *app = UIApplication.sharedApplication;
    if (![app respondsToSelector:@selector(_touchesEvent)]) return NO;
    UIEvent *event = [app _touchesEvent];
    if (!event || ![event respondsToSelector:@selector(_clearTouches)] ||
        ![event respondsToSelector:@selector(_addTouch:forDelayedDelivery:)]) return NO;
    CFTypeRef hid = createHID();
    [event _clearTouches];
    if (hid && [event respondsToSelector:@selector(_setHIDEvent:)]) [event _setHIDEvent:hid];
    for (UITouch *touch in contacts.allValues) {
        if (hid && [touch respondsToSelector:@selector(_setHidEvent:)]) [touch _setHidEvent:hid];
        [event _addTouch:touch forDelayedDelivery:NO];
    }
    [app sendEvent:event];
    if (hid) CFRelease(hid);
    return YES;
}

BOOL VCInjectTouch(NSInteger identifier, char phase, double x, double y) {
    NSCAssert(NSThread.isMainThread,@"touch events require main thread");
    if (identifier < 1 || identifier > 12 || !std::isfinite(x) || !std::isfinite(y) ||
        x < 0 || x > 1 || y < 0 || y > 1) return NO;
    if (!contacts) contacts = [NSMutableDictionary dictionary];
    NSNumber *key = @(identifier);
    UITouch *touch = contacts[key];
    if (phase == 'b') {
        if (touch) return NO;
        if (!targetWindow) targetWindow = gameWindow();
        if (!targetWindow) return NO;
        CGPoint p = CGPointMake(x * targetWindow.bounds.size.width,
                                y * targetWindow.bounds.size.height);
        UIView *view = [targetWindow hitTest:p withEvent:nil];
        if (!view) return NO;
        touch = [[UITouch alloc] init];
        if (![touch respondsToSelector:@selector(setWindow:)] ||
            ![touch respondsToSelector:@selector(setView:)] ||
            ![touch respondsToSelector:@selector(setPhase:)] ||
            ![touch respondsToSelector:@selector(_setLocationInWindow:resetPrevious:)]) return NO;
        [touch setWindow:targetWindow];
        [touch setView:view];
        [touch setTapCount:1];
        [touch _setLocationInWindow:p resetPrevious:YES];
        [touch setPhase:UITouchPhaseBegan];
        if ([touch respondsToSelector:@selector(_setIsFirstTouchForView:)])
            [touch _setIsFirstTouchForView:YES];
        contacts[key] = touch;
    } else if (phase == 'm' || phase == 'e') {
        if (!touch || !targetWindow) return NO;
        CGPoint p = CGPointMake(x * targetWindow.bounds.size.width,
                                y * targetWindow.bounds.size.height);
        [touch _setLocationInWindow:p resetPrevious:NO];
        [touch setPhase:phase == 'm' ? UITouchPhaseMoved : UITouchPhaseEnded];
    } else return NO;
    [touch setTimestamp:NSProcessInfo.processInfo.systemUptime];
    BOOL ok = dispatchTouches();
    if (phase == 'e') {
        [contacts removeObjectForKey:key];
        if (!contacts.count) targetWindow = nil;
    } else [touch setPhase:UITouchPhaseStationary];
    return ok;
}

void VCReleaseAllTouches(void) {
    NSCAssert(NSThread.isMainThread,@"release requires main thread");
    NSArray *keys = contacts.allKeys.copy;
    for (NSNumber *key in keys) {
        UITouch *touch = contacts[key];
        CGPoint p = [touch locationInView:targetWindow];
        if (targetWindow && targetWindow.bounds.size.width > 0 &&
            targetWindow.bounds.size.height > 0) {
            VCInjectTouch(key.integerValue,'e',
                p.x/targetWindow.bounds.size.width,
                p.y/targetWindow.bounds.size.height);
        } else [contacts removeObjectForKey:key];
    }
    targetWindow = nil;
}
