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

- (BOOL) hasSelection;
- (void) showSidebarItem:(MBEntry * _Nullable)item;
- (void) showReadingRecapHTML:(NSString*) html;

@end

NS_ASSUME_NONNULL_END
