//
//  MBSidebarController.h
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import <Cocoa/Cocoa.h>

@class MBClient;
@class MBEntry;
@class MBSubscription;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MBSidebarDateFilter) {
	MBSidebarDateFilterToday = 0,
	MBSidebarDateFilterRecent = 1,
	MBSidebarDateFilterFading = 2
};

typedef NS_ENUM(NSInteger, MBSidebarSortOrder) {
	MBSidebarSortOrderNewestFirst = 0,
	MBSidebarSortOrderOldestFirst = 1
};

@interface MBSidebarController : NSViewController

@property (nonatomic, strong, nullable) MBClient *client;
@property (nonatomic, copy) NSArray<MBEntry *> *items;
@property (nonatomic, copy, nullable) void (^selectionChangedHandler)(MBEntry * _Nullable item);
@property (nonatomic, copy, nullable) void (^readingRecapHandler)(NSString* html);
@property (nonatomic, copy, nullable) void (^syncCompletedHandler)(void);
@property (nonatomic, copy, nullable) BOOL (^focusDetailHandler)(void);
@property (nonatomic, copy, nullable) void (^specialModeChangedHandler)(BOOL is_showing_special_mode);
@property (nonatomic, copy, nullable) NSString* token;
@property (nonatomic, assign) MBSidebarDateFilter dateFilter;
@property (nonatomic, assign) MBSidebarSortOrder sortOrder;
@property (nonatomic, copy) NSString* searchQuery;

- (void) reloadData;
- (void) loadCachedRecentEntries;
- (void) refreshData;
- (void) showMentions;
- (void) showBookmarks;
- (void) showAllPostsForSelectedSite;
- (void) showAllPostsForFeedID:(NSInteger)feedID siteName:(NSString *)siteName feedHost:(NSString *)feedHost;
- (void) showCurrentUserPostsForFeedID:(NSInteger)feedID siteName:(NSString *)siteName feedHost:(NSString *)feedHost;
- (void) showCurrentUserDraftsForFeedID:(NSInteger)feedID siteName:(NSString *)siteName feedHost:(NSString *)feedHost;
- (void) showCurrentUserPostsForDestination:(NSDictionary *)destination subscription:(MBSubscription * _Nullable)subscription;
- (void) showCurrentUserDraftsForDestination:(NSDictionary *)destination subscription:(MBSubscription * _Nullable)subscription;
- (void) reloadCurrentPostsFromServer;
- (void) clearSpecialMode;
- (void) focusAndSelectFirstItem;
- (BOOL) focusSidebar;
- (BOOL) isShowingBookmarks;
- (BOOL) isShowingSpecialMode;
- (BOOL) canShowAllPostsForSelectedSite;
- (BOOL) canToggleSelectedItemReadState;
- (BOOL) canMarkAllItemsAsRead;
- (BOOL) canToggleSelectedItemBookmarkedState;
- (BOOL) canShowReadingRecap;
- (BOOL) canReplyToSelectedMention;
- (BOOL) canEditSelectedPost;
- (NSDictionary * _Nullable) cachedDestinationForEntry:(MBEntry *)entry;
- (NSString*) readToggleMenuTitle;
- (NSString*) bookmarkToggleMenuTitle;
- (NSString*) readPostsVisibilityMenuTitle;
- (void) toggleSelectedItemReadState;
- (void) markAllItemsAsRead;
- (void) toggleSelectedItemBookmarkedState;
- (void) toggleReadPostsVisibility;
- (void) replyToSelectedMention;
- (IBAction) showReadingRecap:(id)sender;
- (MBEntry* _Nullable) selectedItem;

@end

NS_ASSUME_NONNULL_END
