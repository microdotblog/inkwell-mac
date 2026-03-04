//
//  MBSidebarController.h
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import <Cocoa/Cocoa.h>

@class MBClient;
@class MBEntry;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MBSidebarDateFilter) {
	MBSidebarDateFilterToday = 0,
	MBSidebarDateFilterRecent = 1,
	MBSidebarDateFilterFading = 2
};

@interface MBSidebarController : NSViewController

@property (nonatomic, strong, nullable) MBClient *client;
@property (nonatomic, copy) NSArray<MBEntry *> *items;
@property (nonatomic, copy, nullable) void (^selectionChangedHandler)(MBEntry * _Nullable item);
@property (nonatomic, copy, nullable) NSString* token;
@property (nonatomic, assign) MBSidebarDateFilter dateFilter;
@property (nonatomic, copy) NSString* searchQuery;

- (void) reloadData;
- (void) refreshData;
- (void) focusAndSelectFirstItem;

@end

NS_ASSUME_NONNULL_END
