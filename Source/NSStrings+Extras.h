#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSString (Extras)

+ (NSString*) mb_openInBrowserString;
+ (BOOL) mb_openURLStringInBrowser:(NSString*) url_string;

@end

NS_ASSUME_NONNULL_END
