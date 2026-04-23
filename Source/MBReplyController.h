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

- (instancetype) initWithClient:(MBClient * _Nullable)client token:(NSString * _Nullable)token;
- (void) showForWindow:(NSWindow *)parentWindow;

@end

NS_ASSUME_NONNULL_END
