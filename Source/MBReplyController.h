//
//  MBReplyController.h
//  Inkwell
//
//  Created by Codex on 4/23/26.
//

#import <Cocoa/Cocoa.h>

@class MBClient;

NS_ASSUME_NONNULL_BEGIN

@interface MBReplyController : NSWindowController

@property (nonatomic, copy, nullable) dispatch_block_t didCloseHandler;
@property (nonatomic, copy, nullable) dispatch_block_t didPostReplyHandler;

- (instancetype) initWithClient:(MBClient * _Nullable)client token:(NSString * _Nullable)token;
- (void) showForWindow:(NSWindow *)parentWindow postID:(NSString *)postID prefillText:(NSString *)prefillText;

@end

NS_ASSUME_NONNULL_END
