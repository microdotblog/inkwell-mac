//
//  MBHighlightsController.h
//  Inkwell
//
//  Created by Codex on 3/4/26.
//

#import <Cocoa/Cocoa.h>

@class MBClient;
@class MBEntry;
@class MBHighlight;

NS_ASSUME_NONNULL_BEGIN

@interface MBHighlightsController : NSWindowController

@property (nonatomic, assign, readonly) NSInteger entryID;
@property (nonatomic, copy, nullable) void (^highlightDeletedHandler)(MBHighlight* highlight);

- (instancetype) initWithClient:(MBClient*) client token:(NSString*) token;
- (void) updateForSelectedEntry:(MBEntry* _Nullable) entry;
- (void) showHighlightsForEntry:(MBEntry*) entry;
- (void) showHighlightsForEntryID:(NSInteger) entry_id;
- (void) reloadHighlights;

@end

NS_ASSUME_NONNULL_END
