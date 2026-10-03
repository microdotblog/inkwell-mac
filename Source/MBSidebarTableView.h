//
//  MBSidebarTableView.h
//  Inkwell
//
//  Created by Codex on 3/31/26.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface MBSidebarTableView : NSTableView

@property (copy, nullable) BOOL (^primaryActionHandler)(void);
@property (copy, nullable) BOOL (^focusDetailHandler)(void);
@property (copy, nullable) NSMenu* (^contextMenuHandler)(void);
@property (copy, nullable) BOOL (^moveSelectionFromRememberedRowHandler)(NSInteger direction);
@property (copy, readonly) NSArray* rowIdentifiers;

// Call after updating the data source, using stable, unique identifiers for its rows.
- (void) updateRowIdentifiers:(NSArray *)rowIdentifiers;

@end

NS_ASSUME_NONNULL_END
