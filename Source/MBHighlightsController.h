//
//  MBHighlightsController.h
//  Inkwell
//
//  Created by Codex on 3/4/26.
//

#import <Cocoa/Cocoa.h>

@class MBClient;

NS_ASSUME_NONNULL_BEGIN

@interface MBHighlightsController : NSWindowController

@property (nonatomic, assign, readonly) NSInteger entryID;

- (instancetype) initWithClient:(MBClient*) client token:(NSString*) token;
- (void) showHighlightsForEntryID:(NSInteger) entry_id;
- (void) reloadHighlights;

@end

NS_ASSUME_NONNULL_END
