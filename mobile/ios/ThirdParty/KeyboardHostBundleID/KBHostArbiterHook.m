//
//  KBHostArbiterHook.m
//  KeyboardHostBundleID
//

#import "KBHostArbiterHook.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <os/lock.h>

// All private UIKit symbols are resolved at runtime so they never appear as
// static references. Names are kept as string constants.
static NSString *const kArbiterClientClassName   = @"_UIKeyboardArbiterClient";
static NSString *const kDestinationClassName     = @"_UIKeyboardArbiterClientInputDestination";
static NSString *const kEnabledSelectorName      = @"enabled";
static NSString *const kAutoSharedSelectorName   = @"automaticSharedArbiterClient";
static NSString *const kCheckConnSelectorName    = @"checkConnection";
static NSString *const kSwizzleSelectorName      = @"queue_keyboardChanged:onComplete:";
static NSString *const kSourceBundleIdKey        = @"_sourceBundleIdentifier";

static os_unfair_lock sHookLock = OS_UNFAIR_LOCK_INIT;
static NSString *_Nullable sLastCapturedBundleId = nil;
static uint64_t sCaptureGeneration = 0;
static uint64_t sInvalidationGeneration = 0;
static IMP _Nullable sOriginalIMP = NULL;
static BOOL sInstalled = NO;

#pragma mark - Validation

static BOOL IsAcceptableBundleId(NSString *_Nullable bid) {
    if (bid.length == 0) return NO;
    if (![bid containsString:@"."]) return NO;
    if ([bid isEqualToString:@"<null>"] || [bid isEqualToString:@"(null)"]) return NO;
    if ([bid isEqualToString:[NSBundle mainBundle].bundleIdentifier]) return NO;
    // Real system hosts also use com.apple.*. A namespace alone cannot
    // distinguish a host app from an internal UIKit identity.
    return YES;
}

static void CommitHostBundleId(NSString *_Nullable bid) {
    NSString *accepted = IsAcceptableBundleId(bid) ? [bid copy] : nil;

    os_unfair_lock_lock(&sHookLock);
    // An unknown/invalid destination invalidates the previous host too.
    sLastCapturedBundleId = accepted;
    sCaptureGeneration += 1;
    os_unfair_lock_unlock(&sHookLock);
}

#pragma mark - Trampolines

// Replacement for -[_UIKeyboardArbiterClientInputDestination queue_keyboardChanged:onComplete:].
// The bundle identifier lives on the `change` argument (arg1), not on `self`.
static void SwizzledKeyboardChanged(id self, SEL _cmd, id change, id completion) {
    NSString *bundleId = nil;
    if (change) {
        @try {
            id value = [change valueForKey:kSourceBundleIdKey];
            if ([value isKindOfClass:[NSString class]]) {
                bundleId = (NSString *)value;
            }
        } @catch (__unused NSException *e) {
            // Swallow KVC failures so the original IMP still runs.
        }
    }
    CommitHostBundleId(bundleId);
    if (sOriginalIMP) {
        ((void (*)(id, SEL, id, id))sOriginalIMP)(self, _cmd, change, completion);
    }
}

// Replacement for +[_UIKeyboardArbiterClient enabled]. iOS 26.4 gates the
// destination-changed dispatch on this class method; if it returns NO the
// trampoline above never fires. Force it to YES inside the keyboard process.
static BOOL AlwaysEnabledIMP(__unused id self, __unused SEL _cmd) {
    return YES;
}

#pragma mark - Install

@implementation KBHostArbiterHook
+ (NSDictionary<NSString *, NSNumber *> *)diagnostics {
    Class clientClass = NSClassFromString(kArbiterClientClassName);
    Class destinationClass = NSClassFromString(kDestinationClassName);
    SEL getter = NSSelectorFromString(kAutoSharedSelectorName);
    id client = [clientClass respondsToSelector:getter] ? ((id (*)(id, SEL))objc_msgSend)(clientClass, getter) : nil;
    return @{ @"installed": @(sInstalled), @"original": @(sOriginalIMP != NULL),
        @"enabledMethod": @(class_getClassMethod(clientClass, NSSelectorFromString(kEnabledSelectorName)) != NULL),
        @"destinationMethod": @(class_getInstanceMethod(destinationClass, NSSelectorFromString(kSwizzleSelectorName)) != NULL),
        @"client": @(client != nil), @"ping": @([client respondsToSelector:NSSelectorFromString(kCheckConnSelectorName)]) };
}

+ (void)load {
    if (@available(iOS 26.4, *)) {
        [self installHooks];
    }
}

+ (void)installHooks {
    os_unfair_lock_lock(&sHookLock);
    if (sInstalled) {
        os_unfair_lock_unlock(&sHookLock);
        return;
    }
    sInstalled = YES;
    os_unfair_lock_unlock(&sHookLock);

    // Step 1: force +[_UIKeyboardArbiterClient enabled] to return YES so the
    // arbiter dispatches destination-changed callbacks into our swizzle.
    Class clientCls = NSClassFromString(kArbiterClientClassName);
    if (clientCls) {
        SEL enabledSel = NSSelectorFromString(kEnabledSelectorName);
        Method enabledMethod = class_getClassMethod(clientCls, enabledSel);
        if (enabledMethod) {
            method_setImplementation(enabledMethod, (IMP)&AlwaysEnabledIMP);
        }
    }

    // Step 2: swap the destination's queue_keyboardChanged:onComplete: IMP.
    Class destCls = NSClassFromString(kDestinationClassName);
    if (!destCls) return;
    SEL sel = NSSelectorFromString(kSwizzleSelectorName);
    Method method = class_getInstanceMethod(destCls, sel);
    if (!method) return;
    sOriginalIMP = method_getImplementation(method);
    method_setImplementation(method, (IMP)&SwizzledKeyboardChanged);
}

+ (void)activeArbiterCheck {
    if (@available(iOS 26.4, *)) {
        // fall through
    } else {
        return;
    }

    Class cls = NSClassFromString(kArbiterClientClassName);
    if (!cls) return;

    SEL getter = NSSelectorFromString(kAutoSharedSelectorName);
    if (![cls respondsToSelector:getter]) return;

    id (*getMsg)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    id client = getMsg(cls, getter);
    if (!client) return; // lazy initialization not complete yet; try again later

    SEL ping = NSSelectorFromString(kCheckConnSelectorName);
    if ([client respondsToSelector:ping]) {
        void (*pingMsg)(id, SEL) = (void (*)(id, SEL))objc_msgSend;
        pingMsg(client, ping);
    }
}

+ (nullable NSString *)lastCapturedHostBundleId {
    os_unfair_lock_lock(&sHookLock);
    NSString *bid = [sLastCapturedBundleId copy];
    os_unfair_lock_unlock(&sHookLock);
    return IsAcceptableBundleId(bid) ? bid : nil;
}

+ (uint64_t)captureGeneration {
    os_unfair_lock_lock(&sHookLock);
    uint64_t generation = sCaptureGeneration;
    os_unfair_lock_unlock(&sHookLock);
    return generation;
}

+ (nullable NSString *)hostBundleIdCapturedAfterGeneration:(uint64_t)generation {
    os_unfair_lock_lock(&sHookLock);
    BOOL fresh = sCaptureGeneration != generation && sInvalidationGeneration <= generation;
    NSString *bid = fresh ? [sLastCapturedBundleId copy] : nil;
    os_unfair_lock_unlock(&sHookLock);
    return bid;
}

+ (void)invalidateCache {
    os_unfair_lock_lock(&sHookLock);
    sLastCapturedBundleId = nil;
    sCaptureGeneration += 1;
    sInvalidationGeneration = sCaptureGeneration;
    os_unfair_lock_unlock(&sHookLock);
}

@end
