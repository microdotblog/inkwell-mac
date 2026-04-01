//
//  MBNewFeedChoice.h
//  Inkwell
//
//  Created by Codex on 3/31/26.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface MBNewFeedChoice : NSObject

@property (copy) NSString* title;
@property (copy) NSString* feedURL;
@property (assign) BOOL isJSONFeed;

@end

NS_ASSUME_NONNULL_END
