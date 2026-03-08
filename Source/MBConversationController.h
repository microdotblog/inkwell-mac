//
//  MBConversationController.h
//  Inkwell
//
//  Created by Codex on 3/7/26.
//

#import <Cocoa/Cocoa.h>

@class MBClient;
@class MBEntry;

NS_ASSUME_NONNULL_BEGIN

@interface MBConversationController : NSWindowController

- (instancetype) initWithClient:(MBClient* _Nullable) client token:(NSString* _Nullable) token;
- (void) updateForSelectedEntry:(MBEntry* _Nullable) entry;
- (void) updateWithConversationPayload:(NSDictionary* _Nullable) conversation_payload;

@end

NS_ASSUME_NONNULL_END
