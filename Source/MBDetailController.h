//
//  MBDetailController.h
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import <Cocoa/Cocoa.h>

@class MBEntry;

NS_ASSUME_NONNULL_BEGIN

@interface MBDetailController : NSViewController

@property (nonatomic, copy, nullable) void (^selectionChangedHandler)(BOOL has_selection);
@property (nonatomic, copy, nullable) NSArray* (^highlightsProvider)(NSInteger entry_id);
@property (nonatomic, copy, nullable) BOOL (^focusSidebarHandler)(void);

- (BOOL) hasSelection;
- (BOOL) focusDetailPane;
- (void) showSidebarItem:(MBEntry * _Nullable)item;
- (void) showReadingRecapHTML:(NSString*) html;
- (void) requestSelectionHighlightPayloadWithCompletion:(void (^)(NSDictionary* _Nullable payload)) completion;
- (void) clearSelection;
- (void) refreshHighlights;
- (void) applyPreferredTextSettings;

@end

NS_ASSUME_NONNULL_END
