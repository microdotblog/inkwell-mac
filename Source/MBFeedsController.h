//
//  MBFeedsController.h
//  Inkwell
//
//  Created by Codex on 3/10/26.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class MBClient;

@interface MBFeedsController : NSViewController

- (instancetype) initWithClient:(MBClient* _Nullable) client token:(NSString* _Nullable) token;
- (void) reloadFeeds;
- (void) updateSearchQuery:(NSString*) search_query;

@end

NS_ASSUME_NONNULL_END
