//
//  MBConversationController.h
//  Inkwell
//
//  Created by Codex on 3/7/26.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface MBConversationController : NSWindowController

- (void) updateWithConversationPayload:(NSDictionary* _Nullable) conversation_payload;

@end

NS_ASSUME_NONNULL_END
