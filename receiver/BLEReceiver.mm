#import "BLEReceiver.h"
#import "VirtualGamepad.h"
#import <CoreBluetooth/CoreBluetooth.h>
#import <UIKit/UIKit.h>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>

// Dedicated experimental BLE transport. Wi-Fi server remains untouched.
// UUIDs must match iphone-app/BLECentral.swift.
static NSString *const kServiceUUID = @"5CB83FF0-304B-4C67-87C9-0F2D12C31801";
static NSString *const kAuthUUID = @"5CB83FF0-304B-4C67-87C9-0F2D12C31802";
static NSString *const kStateUUID = @"5CB83FF0-304B-4C67-87C9-0F2D12C31803";
static const NSTimeInterval kFrameTimeout = 0.40;
// Short radio hiccups only neutralize controls. The virtual controller is
// disconnected (which the game may notice) only after a long silence.
static const NSTimeInterval kGamepadDisconnectTimeout = 10.0;
// After this much silence, a different central may claim the controller slot
// with the correct PIN (e.g. the same iPhone after a BLE address rotation).
static const NSTimeInterval kSlotTakeoverTimeout = 3.0;

@interface VCBLEReceiver : NSObject <CBPeripheralManagerDelegate>
@property(nonatomic,strong) CBPeripheralManager *manager;
@property(nonatomic,strong) CBMutableCharacteristic *authChar;
@property(nonatomic,strong) CBMutableCharacteristic *stateChar;
@property(nonatomic,copy) NSString *pin;
@property(nonatomic,copy) NSUUID *authorized;
@property(nonatomic,strong) dispatch_source_t watchdog;
@property(nonatomic,assign) NSTimeInterval lastFrameAt;
@property(nonatomic,assign) BOOL liveInput;
@property(nonatomic,assign) BOOL gamepadRequested;
@property(nonatomic,assign) BOOL hasSequence;
@property(nonatomic,assign) uint8_t lastSequence;
@property(nonatomic,assign) NSInteger badPINAttempts;
@property(nonatomic,assign) NSTimeInterval cooldownUntil;
@end

@implementation VCBLEReceiver
- (instancetype)initWithPIN:(NSString *)pin {
    if ((self = [super init])) {
        _pin = [pin copy];
        _manager = [[CBPeripheralManager alloc] initWithDelegate:self queue:dispatch_get_main_queue()];
        __weak VCBLEReceiver *weakSelf = self;
        _watchdog = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
        dispatch_source_set_timer(_watchdog,
            dispatch_time(DISPATCH_TIME_NOW,100 * NSEC_PER_MSEC),
            100 * NSEC_PER_MSEC, 25 * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(_watchdog, ^{
            VCBLEReceiver *strongSelf = weakSelf;
            if (!strongSelf) return;
            NSTimeInterval silence = NSProcessInfo.processInfo.systemUptime - strongSelf.lastFrameAt;
            if (strongSelf.liveInput && silence > kFrameTimeout) {
                // Neutralize only; keep the virtual controller connected so a
                // brief BLE stall does not look like a controller unplug.
                strongSelf.liveInput = NO;
                VCGamepadRelease();
                NSLog(@"[VCRemote/BLE] Controller timeout: all controls released");
            }
            if (strongSelf.gamepadRequested && silence > kGamepadDisconnectTimeout) {
                strongSelf.gamepadRequested = NO;
                VCGamepadSetActive(NO);
                NSLog(@"[VCRemote/BLE] Long silence: virtual controller disconnected");
            }
        });
        dispatch_resume(_watchdog);
    }
    return self;
}
- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)manager {
    if (manager.state != CBManagerStatePoweredOn) {
        self.authorized = nil;
        self.liveInput = NO;
        self.gamepadRequested = NO;
        VCGamepadSetActive(NO);
        NSLog(@"[VCRemote/BLE] Bluetooth unavailable: %ld",(long)manager.state);
        return;
    }
    CBUUID *serviceId = [CBUUID UUIDWithString:kServiceUUID];
    self.authChar = [[CBMutableCharacteristic alloc]
        initWithType:[CBUUID UUIDWithString:kAuthUUID]
        properties:CBCharacteristicPropertyWrite
        value:nil
        permissions:CBAttributePermissionsWriteable];
    self.stateChar = [[CBMutableCharacteristic alloc]
        initWithType:[CBUUID UUIDWithString:kStateUUID]
        properties:CBCharacteristicPropertyWriteWithoutResponse
        value:nil
        permissions:CBAttributePermissionsWriteable];
    CBMutableService *service = [[CBMutableService alloc] initWithType:serviceId primary:YES];
    service.characteristics = @[self.authChar,self.stateChar];
    [manager addService:service];
}
- (void)peripheralManager:(CBPeripheralManager *)manager didAddService:(CBService *)service error:(NSError *)error {
    if (error) {
        NSLog(@"[VCRemote/BLE] Failed to publish service: %@",error);
        return;
    }
    [manager startAdvertising:@{
        CBAdvertisementDataServiceUUIDsKey:@[[CBUUID UUIDWithString:kServiceUUID]],
        CBAdvertisementDataLocalNameKey:@"VCRemote iPad"
    }];
}
- (void)peripheralManagerDidStartAdvertising:(CBPeripheralManager *)manager error:(NSError *)error {
    NSLog(@"[VCRemote/BLE] %@",error ? [NSString stringWithFormat:@"Advertising failed: %@",error] : @"Advertising");
}
- (void)peripheralManager:(CBPeripheralManager *)manager didReceiveWriteRequests:(NSArray<CBATTRequest *> *)requests {
    for (CBATTRequest *request in requests) {
        NSString *uuid = request.characteristic.UUID.UUIDString;
        if ([uuid caseInsensitiveCompare:kAuthUUID] == NSOrderedSame) {
            BOOL validLength = request.value.length == 7;
            const uint8_t *bytes = (const uint8_t *)request.value.bytes;
            BOOL validPin = validLength && bytes[0] == 'A' &&
                memcmp(bytes + 1,self.pin.UTF8String,6) == 0;
            NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
            BOOL allowed = now >= self.cooldownUntil;
            // The slot is also free once the authorized central has gone quiet.
            // CoreBluetooth gives a peripheral no disconnect callback, and the
            // iPhone may come back under a new identifier after reconnecting.
            BOOL staleSlot = now - self.lastFrameAt > kSlotTakeoverTimeout;
            BOOL freeSlot = !self.authorized || staleSlot ||
                [self.authorized isEqual:request.central.identifier];
            if (validPin && allowed && freeSlot) {
                if (self.authorized && ![self.authorized isEqual:request.central.identifier])
                    NSLog(@"[VCRemote/BLE] Silent controller replaced by new central");
                self.authorized = request.central.identifier;
                self.lastFrameAt = now;
                self.hasSequence = NO;
                self.badPINAttempts = 0;
                self.liveInput = NO;
                // An auth write-with-response is the authorization acknowledgement.
                [manager respondToRequest:request withResult:CBATTErrorSuccess];
                NSLog(@"[VCRemote/BLE] Controller authorized");
            } else {
                if (!validPin) {
                    self.badPINAttempts += 1;
                    if (self.badPINAttempts >= 5) {
                        self.cooldownUntil = now + 15;
                        self.badPINAttempts = 0;
                    }
                }
                [manager respondToRequest:request withResult:CBATTErrorInsufficientAuthorization];
                NSLog(@"[VCRemote/BLE] Authorization denied");
            }
            continue;
        }
        if ([uuid caseInsensitiveCompare:kStateUUID] != NSOrderedSame ||
            !self.authorized || ![self.authorized isEqual:request.central.identifier] ||
            request.value.length != 10) continue;
        const uint8_t *b = (const uint8_t *)request.value.bytes;
        if (b[0] != 1) continue;
        uint8_t sequence = b[1];
        uint8_t advance = (uint8_t)(sequence - self.lastSequence);
        if (self.hasSequence && (advance == 0 || advance >= 128)) continue;
        self.hasSequence = YES;
        self.lastSequence = sequence;
        self.lastFrameAt = NSProcessInfo.processInfo.systemUptime;
        if (!self.liveInput) {
            self.liveInput = YES;
            self.gamepadRequested = YES;
            VCGamepadSetActive(YES); // no-op while already connected/connecting
        }
        // Snapshot semantics: each new frame overwrites ALL controls, fixing lost
        // release events without retaining an obsolete queue of joystick deltas.
        int8_t axis[4] = {
            (int8_t)b[4],(int8_t)b[5],(int8_t)b[6],(int8_t)b[7]
        };
        VCGamepadInject(1,'m',axis[0] / 127.0,axis[1] / 127.0);
        VCGamepadInject(2,'m',axis[2] / 127.0,axis[3] / 127.0);
        uint16_t buttons = (uint16_t)b[2] | ((uint16_t)b[3] << 8);
        for (int i = 0; i < 16; ++i) {
            BOOL down = (buttons & (1u << i)) != 0;
            VCGamepadInject(i+3,down?'b':'e',0,0);
        }
    }
}
@end

static VCBLEReceiver *gBLEReceiver = nil;
void VCBLEStart(const char *pin) {
    NSCAssert(NSThread.isMainThread,@"VCBLEStart needs main thread");
    if (gBLEReceiver || !pin || strlen(pin) != 6) return;
    gBLEReceiver = [[VCBLEReceiver alloc] initWithPIN:[NSString stringWithUTF8String:pin]];
    NSLog(@"[VCRemote/BLE] CoreBluetooth receiver initialized");
}
