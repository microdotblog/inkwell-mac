#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName _Nonnull const MBAvatarLoaderDidLoadImageNotification;
FOUNDATION_EXPORT NSString* const MBAvatarLoaderURLStringUserInfoKey;

@interface MBAvatarLoader : NSObject

+ (instancetype) sharedLoader;
- (NSImage* _Nullable) cachedImageForURLString:(NSString*) url_string;
- (void) loadImageForURLString:(NSString*) url_string;

@end

NS_ASSUME_NONNULL_END
