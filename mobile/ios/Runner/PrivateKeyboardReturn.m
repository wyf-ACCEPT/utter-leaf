#import "PrivateKeyboardReturn.h"
#import <objc/message.h>

@implementation ULHostReturn
+ (BOOL)resumeCapturedHost:(NSString *)bundleIdentifier {
    // The caller supplies only the current tap's App Group ticket, never a URL-supplied arbitrary target.
    if (bundleIdentifier.length == 0 || [bundleIdentifier hasPrefix:@"network.utterleaf."]) return NO;
    Class cls = NSClassFromString(@"LSApplicationWorkspace");
    SEL getter = NSSelectorFromString(@"defaultWorkspace");
    if (!cls || ![cls respondsToSelector:getter]) return NO;
    id workspace = ((id (*)(id, SEL))objc_msgSend)(cls, getter);
    SEL open = NSSelectorFromString(@"openApplicationWithBundleID:");
    if (!workspace || ![workspace respondsToSelector:open]) return NO;
    @try {
        return ((BOOL (*)(id, SEL, NSString *))objc_msgSend)(workspace, open, bundleIdentifier);
    } @catch (__unused NSException *exception) {
        return NO;
    }
}
@end
