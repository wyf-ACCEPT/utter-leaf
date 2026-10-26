#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface ULHostReturn : NSObject
+ (BOOL)resumeCapturedHost:(NSString *)bundleIdentifier;
@end
NS_ASSUME_NONNULL_END
