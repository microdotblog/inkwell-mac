//
//  MBSidebarTableView.h
//  Inkwell
//
//  Created by Codex on 3/31/26.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface MBSidebarTableView : NSTableView

@property (copy, nullable) BOOL (^openSelectedItemHandler)(void);
@property (copy, nullable) BOOL (^focusDetailHandler)(void);
@property (copy, nullable) NSMenu* (^contextMenuHandler)(void);
@property (copy, nullable) void (^focusChangedHandler)(void);
@property (copy, nullable) BOOL (^moveSelectionFromRememberedRowHandler)(NSInteger direction);

@end

NS_ASSUME_NONNULL_END
