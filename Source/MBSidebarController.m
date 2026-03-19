//
//  MBSidebarController.m
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import "MBSidebarController.h"
#import "MBAvatarLoader.h"
#import "MBClient.h"
#import "MBEntry.h"
#import "MBPathUtilities.h"
#import "MBPodcastController.h"
#import "MBRoundedImageView.h"
#import "MBSidebarCell.h"
#import "MBSubscription.h"
#import "NSStrings+Extras.h"

static NSUserInterfaceItemIdentifier const InkwellSidebarCellIdentifier = @"InkwellSidebarCell";
static NSUserInterfaceItemIdentifier const InkwellSidebarRowIdentifier = @"InkwellSidebarRow";
static CGFloat const InkwellSidebarAvatarSize = 26.0;
static CGFloat const InkwellSidebarAvatarInset = 3.0;
static CGFloat const InkwellSidebarTextInset = 10.0;
static CGFloat const InkwellSidebarRightInset = 10.0;
static CGFloat const InkwellSidebarRowBackgroundHorizontalInset = 10.0;
static CGFloat const InkwellSidebarRowBackgroundVerticalInset = 2.5;
static CGFloat const InkwellSidebarVerticalSpacing = 8.0;
static CGFloat const InkwellSidebarTitleFontSize = 14.0;
static CGFloat const InkwellSidebarSubtitleFontSize = 14.0;
static CGFloat const InkwellSidebarDateFontSize = 13.0;
static CGFloat const InkwellSidebarRecapBoxHeight = 42.0;
static CGFloat const InkwellSidebarBookmarksBoxHeight = 46.0;
static CGFloat const InkwellSidebarPodcastPaneHeight = 118.0;
static NSTimeInterval const InkwellSidebarRecapPollInterval = 3.0;
static NSInteger const InkwellSidebarRecapMaxAttempts = 20;
static NSString* const InkwellPlansURLString = @"https://micro.blog/account/plans";
static NSString* const InkwellRecentEntriesCacheFilename = @"RecentEntries.json";
static NSString* const InkwellSidebarSelectedEntryCacheFilename = @"SidebarSelectedEntry.json";
static NSString* const InkwellHideReadPostsDefaultsKey = @"HideReadPosts";
static NSString* const InkwellSidebarSortOrderDefaultsKey = @"SidebarSortOrder";
static NSString* const InkwellSelectedUnfocusedColorName = @"color_selected_unfocused_text";
static NSString* const InkwellUnreadBackgroundColorName = @"color_unread_background";
static NSString* const InkwellUnreadBorderColorName = @"color_unread_border";

typedef NS_ENUM(NSInteger, MBSidebarContentMode) {
	MBSidebarContentModeFeeds = 0,
	MBSidebarContentModeBookmarks = 1,
	MBSidebarContentModeAllPosts = 2
};

@interface MBSidebarTableView : NSTableView

@property (copy, nullable) BOOL (^openSelectedItemHandler)(void);
@property (copy, nullable) BOOL (^focusDetailHandler)(void);
@property (copy, nullable) NSMenu* (^contextMenuHandler)(void);
@property (copy, nullable) void (^focusChangedHandler)(void);

@end

@implementation MBSidebarTableView

- (void) keyDown:(NSEvent*) event
{
	NSString* characters = event.charactersIgnoringModifiers ?: @"";
	if (characters.length > 0) {
		unichar key_code = [characters characterAtIndex:0];
		NSEventModifierFlags modifier_flags = (event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask);
		BOOL has_disallowed_modifiers = ((modifier_flags & (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl | NSEventModifierFlagShift)) != 0);
		BOOL is_return_key = (key_code == NSCarriageReturnCharacter || key_code == NSNewlineCharacter || key_code == NSEnterCharacter);
		if (is_return_key && self.openSelectedItemHandler != nil && self.openSelectedItemHandler()) {
			return;
		}

		BOOL is_right_arrow_key = (key_code == NSRightArrowFunctionKey);
		if (!has_disallowed_modifiers && is_right_arrow_key && self.focusDetailHandler != nil && self.focusDetailHandler()) {
			return;
		}
	}

	[super keyDown:event];
}

- (BOOL) becomeFirstResponder
{
	BOOL did_become_first_responder = [super becomeFirstResponder];
	if (did_become_first_responder && self.focusChangedHandler != nil) {
		self.focusChangedHandler();
	}

	return did_become_first_responder;
}

- (BOOL) resignFirstResponder
{
	BOOL did_resign_first_responder = [super resignFirstResponder];
	if (did_resign_first_responder && self.focusChangedHandler != nil) {
		self.focusChangedHandler();
	}

	return did_resign_first_responder;
}

- (NSMenu*) menuForEvent:(NSEvent*) event
{
	if (self.contextMenuHandler == nil) {
		return [super menuForEvent:event];
	}

	NSPoint point_in_window = event.locationInWindow;
	NSPoint point_in_table = [self convertPoint:point_in_window fromView:nil];
	NSInteger row = [self rowAtPoint:point_in_table];
	if (row < 0 || row >= self.numberOfRows) {
		return nil;
	}

	NSIndexSet* index_set = [NSIndexSet indexSetWithIndex:(NSUInteger) row];
	[self selectRowIndexes:index_set byExtendingSelection:NO];

	NSMenu* menu = self.contextMenuHandler();
	if (menu != nil) {
		return menu;
	}

	return [super menuForEvent:event];
}

@end

@interface MBSidebarRowView : NSTableRowView

@property (nonatomic, strong) NSColor* customBackgroundColor;
@property (nonatomic, strong) NSColor* customBorderColor;
@property (nonatomic, strong) NSColor* customSelectionBackgroundColor;

@end

@implementation MBSidebarRowView

- (void) setCustomBackgroundColor:(NSColor *)custom_background_color
{
	if ((_customBackgroundColor == custom_background_color) || [_customBackgroundColor isEqual:custom_background_color]) {
		return;
	}

	_customBackgroundColor = custom_background_color;
	[self setNeedsDisplay:YES];
}

- (void) setCustomSelectionBackgroundColor:(NSColor*) custom_selection_background_color
{
	if ((_customSelectionBackgroundColor == custom_selection_background_color) || [_customSelectionBackgroundColor isEqual:custom_selection_background_color]) {
		return;
	}

	_customSelectionBackgroundColor = custom_selection_background_color;
	[self setNeedsDisplay:YES];
}

- (void) setCustomBorderColor:(NSColor*) custom_border_color
{
	if ((_customBorderColor == custom_border_color) || [_customBorderColor isEqual:custom_border_color]) {
		return;
	}

	_customBorderColor = custom_border_color;
	[self setNeedsDisplay:YES];
}

- (void) drawBackgroundInRect:(NSRect)dirty_rect
{
	[super drawBackgroundInRect:dirty_rect];
	#pragma unused(dirty_rect)
	NSColor* fill_color = self.customSelectionBackgroundColor;
	if (fill_color == nil) {
		fill_color = self.customBackgroundColor;
	}

	if (fill_color == nil) {
		return;
	}

	NSRect fill_rect = NSInsetRect(self.bounds, InkwellSidebarRowBackgroundHorizontalInset, InkwellSidebarRowBackgroundVerticalInset);
	NSBezierPath* background_path = [NSBezierPath bezierPathWithRoundedRect:fill_rect xRadius:10.0 yRadius:10.0];
	[fill_color setFill];
	[background_path fill];
	if (self.customBorderColor != nil) {
		[self.customBorderColor setStroke];
		background_path.lineWidth = 1.0;
		[background_path stroke];
	}
}

- (void) drawSelectionInRect:(NSRect)dirty_rect
{
	if (self.customSelectionBackgroundColor != nil) {
		#pragma unused(dirty_rect)
		return;
	}

	[super drawSelectionInRect:dirty_rect];
}

@end

@interface MBSidebarController () <NSTableViewDataSource, NSTableViewDelegate, NSMenuItemValidation>

@property (assign) BOOL hasLoadedRemoteItems;
@property (assign) BOOL isFetching;
@property (assign) NSInteger selectedRowForStyling;
@property (strong) NSTableView *tableView;
@property (strong) NSScrollView* tableScrollView;
@property (strong) MBPodcastController* podcastController;
@property (strong) NSView* podcastContainerView;
@property (strong) NSLayoutConstraint* podcastHeightConstraint;
@property (strong, nullable) MBEntry* currentPodcastEntry;
@property (copy) NSArray<MBEntry *> *allItems;
@property (copy) NSArray<MBEntry *> *bookmarkItems;
@property (copy) NSArray<MBEntry *> *allPostsItems;
@property (copy) NSDictionary<NSString *, NSString *> *iconURLByHost;
@property (strong) MBAvatarLoader* avatarLoader;
@property (strong) NSImage *defaultAvatarImage;
@property (strong) NSMenu* contextMenu;
@property (strong) NSBox* recapBoxView;
@property (strong) NSButton* recapButton;
@property (strong) NSTextField* recapCountLabel;
@property (strong) NSTextField* bookmarksTitleLabel;
@property (strong) NSButton* bookmarksClearButton;
@property (strong) NSLayoutConstraint* recapBoxHeightConstraint;
@property (strong) NSLayoutConstraint* recapToTableTopConstraint;
@property (assign) BOOL isRecapFetching;
@property (assign) BOOL isFetchingBookmarks;
@property (assign) BOOL isFetchingAllPosts;
@property (assign) NSInteger recapRequestIdentifier;
@property (assign) NSInteger bookmarksRequestIdentifier;
@property (assign) NSInteger allPostsRequestIdentifier;
@property (weak) NSWindow* observedWindowForSelectionStyling;
@property (strong) NSView* premiumRequiredView;
@property (assign) BOOL hideReadPosts;
@property (assign) BOOL isPreservingSelectionDuringReload;
@property (assign) BOOL suppressSelectionChangedHandler;
@property (assign) MBSidebarContentMode contentMode;
@property (assign) NSInteger allPostsFeedID;
@property (copy) NSString* allPostsSiteName;
@property (copy) NSString* allPostsFeedHost;
@property (copy) NSSet* preservedVisibleEntryIDsForHiddenReadPosts;

- (void) markSelectedItemAsReadIfNeeded:(MBEntry *)item atRow:(NSInteger)row;
- (void) updateCachedReadState:(BOOL)is_read forEntryID:(NSInteger)entry_id;
- (void) updateCachedReadState:(BOOL) is_read forEntryIDs:(NSArray*) entry_ids;
- (void) updateCachedBookmarkedState:(BOOL)is_bookmarked forEntryID:(NSInteger)entry_id;
- (void) reloadRowForEntryID:(NSInteger)entry_id preferredRow:(NSInteger)preferred_row;
- (void) reloadTablePreservingSelectionForEntryID:(NSInteger) entry_id notifySelectionIfUnchanged:(BOOL) notify_if_unchanged;
- (void) applyFiltersAndReloadPreservingSelectionEntryID:(NSInteger) preferred_entry_id;
- (NSInteger) preferredSelectionEntryIDForReload;
- (NSInteger) currentSelectedEntryID;
- (BOOL) restoreSelectionForEntryID:(NSInteger)entry_id notifySelectionIfUnchanged:(BOOL) notify_if_unchanged;
- (NSInteger) rowForEntryID:(NSInteger)entry_id;
- (BOOL) isRowSelectedForStyling:(NSInteger) row tableView:(NSTableView*) table_view;
- (void) configureRowView:(MBSidebarRowView*) row_view forRow:(NSInteger) row tableView:(NSTableView*) table_view;
- (NSInteger) savedSelectedEntryID;
- (void) clearSavedSelectedEntryID;
- (void) saveSelectedEntryIDForCurrentSelection;
- (void) deselectSidebarSelectionPreservingDetail;
- (void) clearPreservedHiddenReadState;
- (void) scrollTableToTop;
- (void) refreshSelectionStylingForSelectedRow:(NSInteger) selected_row;
- (void) startObservingWindowKeyState;
- (void) stopObservingWindowKeyState;
- (void) windowKeyStateDidChange:(NSNotification*) notification;
- (BOOL) hasEmphasizedSelectionForTableView:(NSTableView*) table_view;
- (BOOL) openSelectedItemInBrowser;
- (NSString*) readToggleMenuTitleForSelectedItem:(MBEntry* _Nullable) selected_item;
- (NSString*) bookmarkToggleMenuTitleForSelectedItem:(MBEntry* _Nullable) selected_item;
- (void) updateRecapUI;
- (void) updatePremiumRequiredView;
- (void) setRecapFetching:(BOOL)is_fetching;
- (void) finishReadingRecapPollingForRequestIdentifier:(NSInteger) request_identifier;
- (void) fetchBookmarksIfNeeded;
- (void) fetchBookmarks;
- (void) fetchAllPostsIfNeeded;
- (void) fetchAllPosts;
- (void) ensureSpecialModeSelectionIfNeeded;
- (void) resetBookmarksModeState;
- (void) resetAllPostsModeState;
- (void) cacheRecentEntries;
- (NSURL* _Nullable) recentEntriesCacheURL;
- (NSURL* _Nullable) selectedEntryCacheURL;
- (NSDictionary*) serializedRecentEntriesPayload;
- (NSDictionary*) dictionaryFromEntry:(MBEntry*) entry;
- (MBEntry* _Nullable) entryFromDictionary:(NSDictionary*) dictionary;
- (MBEntry* _Nullable) cachedSelectedEntry;
- (void) cacheSelectedEntry:(MBEntry*) entry;
- (void) removeCachedSelectedEntry;
- (void) showCachedSelectedEntryIfNeeded;
- (NSString*) normalizedContentHTMLString:(NSString*) string;
- (NSString*) iso8601StringFromDate:(NSDate* _Nullable) date;
- (NSArray*) allFadingItems;
- (NSArray*) allFadingEntryIDs;
- (NSArray*) cachedItemsForFeedID:(NSInteger) feed_id;
- (NSArray*) filteredItemsForReadVisibility:(NSArray*) items selectedEntryID:(NSInteger)selected_entry_id;
- (NSArray*) sortedItems:(NSArray*) items;
- (NSComparisonResult) compareEntry:(MBEntry*) first_entry toEntry:(MBEntry*) second_entry;
- (NSString*) recapCountStringForPostsCount:(NSInteger)post_count;
- (NSAttributedString*) premiumRequiredMessageAttributedString;
- (BOOL) shouldShowPremiumRequiredView;
- (BOOL) shouldShowSpecialModeBanner;
- (BOOL) isShowingAllPostsMode;
- (NSString*) specialModeBannerTitle;
- (NSString*) siteNameForEntry:(MBEntry*) entry;
- (NSString*) feedHostForEntry:(MBEntry*) entry;
- (BOOL) isPremiumUser;
- (BOOL) savedHideReadPosts;
- (MBSidebarSortOrder) savedSortOrder;
- (NSString*) podcastArtworkURLStringForEntry:(MBEntry*) entry;
- (void) setPodcastPaneVisible:(BOOL) is_visible;
- (void) updatePodcastPaneForSelectedItem:(MBEntry* _Nullable) selected_item;
- (NSMenu*) sidebarContextMenu;
- (IBAction) toggleSelectedItemReadStateAction:(id)sender;
- (IBAction) toggleSelectedItemBookmarkedStateAction:(id)sender;
- (IBAction) openSelectedItemInBrowserAction:(id)sender;
- (IBAction) copySelectedItemLinkAction:(id)sender;
- (IBAction) clearSpecialModeAction:(id)sender;
- (IBAction) openPlansAction:(id)sender;
- (void) pollReadingRecapForEntryIDs:(NSArray*) entry_ids attempt:(NSInteger)attempt requestIdentifier:(NSInteger)request_identifier;
- (void) avatarImageDidLoad:(NSNotification*) notification;
- (void) reloadRowsForAvatarURLString:(NSString*) url_string;
- (void) reloadRowsForIconURLString:(NSString*) url_string;
- (NSArray<MBEntry *> *) sidebarItemsForBookmarks:(NSArray*) items;
- (NSArray<MBEntry *> *) sidebarItemsForEntries:(NSArray*) entries subscriptionTitle:(NSString*) subscription_title feedHost:(NSString*) feed_host unreadEntryIDs:(NSSet* _Nullable) unread_entry_ids;
- (MBEntry* _Nullable) sidebarItemForEntryDictionary:(NSDictionary*) entry subscriptionTitle:(NSString*) subscription_title feedHost:(NSString*) feed_host unreadEntryIDs:(NSSet* _Nullable) unread_entry_ids;
- (NSString*) displayDateStringForCurrentMode:(NSDate* _Nullable) date;
- (NSString*) allPostsDisplayDateString:(NSDate* _Nullable) date;
- (NSString*) bookmarksDisplayDateString:(NSDate* _Nullable) date;

@end

@implementation MBSidebarController

- (instancetype) init
{
	self = [super initWithNibName:nil bundle:nil];
	if (self) {
		[MBPathUtilities cleanupLegacyFiles];
		self.dateFilter = MBSidebarDateFilterToday;
		self.hideReadPosts = [self savedHideReadPosts];
		_sortOrder = [self savedSortOrder];
		self.searchQuery = @"";
		self.selectedRowForStyling = -1;
		self.allItems = @[];
		self.bookmarkItems = @[];
		self.allPostsItems = @[];
		self.iconURLByHost = @{};
		self.avatarLoader = [MBAvatarLoader sharedLoader];
		self.items = @[];
		self.contentMode = MBSidebarContentModeFeeds;
		self.allPostsSiteName = @"";
		self.allPostsFeedHost = @"";
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(avatarImageDidLoad:) name:MBAvatarLoaderDidLoadImageNotification object:self.avatarLoader];
	}
	return self;
}

- (void) dealloc
{
	[self stopObservingWindowKeyState];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:MBAvatarLoaderDidLoadImageNotification object:self.avatarLoader];
}

- (void) viewDidAppear
{
	[super viewDidAppear];
	[self startObservingWindowKeyState];
	[self refreshSelectionStylingForSelectedRow:self.tableView.selectedRow];
}

- (void) viewWillDisappear
{
	[self stopObservingWindowKeyState];
	[super viewWillDisappear];
}

- (void) loadView
{
	NSView *container_view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 260.0, 600.0)];
	container_view.translatesAutoresizingMaskIntoConstraints = NO;

	NSBox* recap_box = [[NSBox alloc] initWithFrame:NSZeroRect];
	recap_box.translatesAutoresizingMaskIntoConstraints = NO;
	recap_box.boxType = NSBoxCustom;
	recap_box.borderColor = [NSColor separatorColor];
	recap_box.borderWidth = 1.0;
	recap_box.cornerRadius = 0.0;
	recap_box.fillColor = [[NSColor controlBackgroundColor] colorWithAlphaComponent:0.5];
	recap_box.hidden = YES;

	NSButton* recap_button = [NSButton buttonWithTitle:@"Reading Recap" target:self action:@selector(showReadingRecap:)];
	recap_button.translatesAutoresizingMaskIntoConstraints = NO;
	recap_button.bezelStyle = NSBezelStyleRounded;
	recap_button.controlSize = NSControlSizeSmall;
	recap_button.font = [NSFont systemFontOfSize:13.0];

	NSTextField* recap_label = [NSTextField labelWithString:@""];
	recap_label.translatesAutoresizingMaskIntoConstraints = NO;
	recap_label.font = [NSFont systemFontOfSize:13.0];
	recap_label.textColor = [NSColor secondaryLabelColor];
	recap_label.lineBreakMode = NSLineBreakByTruncatingTail;
	recap_label.maximumNumberOfLines = 1;
	recap_label.usesSingleLineMode = YES;
	[recap_label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
	[recap_label setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

	[recap_box addSubview:recap_button];
	[recap_box addSubview:recap_label];

	NSTextField* bookmarks_label = [NSTextField labelWithString:@""];
	bookmarks_label.translatesAutoresizingMaskIntoConstraints = NO;
	bookmarks_label.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
	bookmarks_label.textColor = [NSColor labelColor];
	bookmarks_label.lineBreakMode = NSLineBreakByTruncatingTail;
	bookmarks_label.maximumNumberOfLines = 1;
	bookmarks_label.usesSingleLineMode = YES;
	[bookmarks_label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
	[bookmarks_label setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
	bookmarks_label.hidden = YES;

	NSButton* clear_button = [NSButton buttonWithTitle:@"Clear" target:self action:@selector(clearSpecialModeAction:)];
	clear_button.translatesAutoresizingMaskIntoConstraints = NO;
	clear_button.bezelStyle = NSBezelStyleRounded;
	clear_button.controlSize = NSControlSizeSmall;
	clear_button.font = [NSFont systemFontOfSize:13.0];
	[clear_button setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
	[clear_button setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
	clear_button.hidden = YES;

	[recap_box addSubview:bookmarks_label];
	[recap_box addSubview:clear_button];

	__weak typeof(self) weak_self = self;
	MBPodcastController* podcast_controller = [[MBPodcastController alloc] init];
	[self addChildViewController:podcast_controller];
	podcast_controller.playbackStateChangedHandler = ^(BOOL is_playing) {
		#pragma unused(is_playing)
		MBSidebarController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		[strong_self updatePodcastPaneForSelectedItem:[strong_self selectedItem]];
	};

	NSView* podcast_view = podcast_controller.view;
	podcast_view.translatesAutoresizingMaskIntoConstraints = NO;
	podcast_view.hidden = YES;

	MBSidebarTableView *table_view = [[MBSidebarTableView alloc] initWithFrame:NSZeroRect];
	table_view.translatesAutoresizingMaskIntoConstraints = NO;
	table_view.delegate = self;
	table_view.dataSource = self;
	table_view.headerView = nil;
	table_view.allowsEmptySelection = YES;
	table_view.intercellSpacing = NSMakeSize(0.0, 5.0);
	table_view.style = NSTableViewStyleSourceList;
	table_view.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
	table_view.openSelectedItemHandler = ^BOOL {
		return [weak_self openSelectedItemInBrowser];
	};
	table_view.focusDetailHandler = ^BOOL {
		MBSidebarController* strong_self = weak_self;
		if (strong_self == nil || strong_self.focusDetailHandler == nil) {
			return NO;
		}

		return strong_self.focusDetailHandler();
	};
	table_view.contextMenuHandler = ^NSMenu* {
		return [weak_self sidebarContextMenu];
	};
	table_view.focusChangedHandler = ^{
		dispatch_async(dispatch_get_main_queue(), ^{
			MBSidebarController* strong_self = weak_self;
			if (strong_self == nil || strong_self.tableView == nil) {
				return;
			}

			NSInteger selected_row = strong_self.tableView.selectedRow;
			[strong_self refreshSelectionStylingForSelectedRow:selected_row];
		});
	};

	NSTableColumn *source_column = [[NSTableColumn alloc] initWithIdentifier:@"SourceColumn"];
	source_column.resizingMask = NSTableColumnAutoresizingMask;
	[table_view addTableColumn:source_column];

	NSScrollView *scroll_view = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	scroll_view.translatesAutoresizingMaskIntoConstraints = NO;
	scroll_view.drawsBackground = NO;
	scroll_view.hasVerticalScroller = YES;
	scroll_view.borderType = NSNoBorder;
	scroll_view.documentView = table_view;

	NSView* premium_required_view = [[NSView alloc] initWithFrame:NSZeroRect];
	premium_required_view.translatesAutoresizingMaskIntoConstraints = NO;
	premium_required_view.hidden = YES;

	NSTextField* premium_required_label = [NSTextField labelWithAttributedString:[self premiumRequiredMessageAttributedString]];
	premium_required_label.translatesAutoresizingMaskIntoConstraints = NO;
	premium_required_label.alignment = NSTextAlignmentCenter;
	premium_required_label.lineBreakMode = NSLineBreakByWordWrapping;
	premium_required_label.maximumNumberOfLines = 0;

	NSButton* plans_button = [NSButton buttonWithTitle:@"Micro.blog Plans" target:self action:@selector(openPlansAction:)];
	plans_button.translatesAutoresizingMaskIntoConstraints = NO;
	plans_button.bezelStyle = NSBezelStyleRounded;
	plans_button.controlSize = NSControlSizeRegular;
	NSImage* micro_icon = [NSImage imageNamed:@"icon_micro"];
	if (micro_icon != nil) {
		NSImage* button_icon = [micro_icon copy];
		button_icon.size = NSMakeSize(16.0, 16.0);
		plans_button.image = button_icon;
		plans_button.imagePosition = NSImageLeading;
		plans_button.imageHugsTitle = YES;
	}

	[premium_required_view addSubview:premium_required_label];
	[premium_required_view addSubview:plans_button];

	[container_view addSubview:recap_box];
	[container_view addSubview:scroll_view];
	[container_view addSubview:podcast_view];
	[container_view addSubview:premium_required_view];
	NSLayoutConstraint* recap_height_constraint = [recap_box.heightAnchor constraintEqualToConstant:0.0];
	NSLayoutConstraint* recap_to_table_top_constraint = [scroll_view.topAnchor constraintEqualToAnchor:recap_box.bottomAnchor constant:0.0];
	NSLayoutConstraint* podcast_height_constraint = [podcast_view.heightAnchor constraintEqualToConstant:0.0];
	[NSLayoutConstraint activateConstraints:@[
		[recap_box.topAnchor constraintEqualToAnchor:container_view.safeAreaLayoutGuide.topAnchor constant:-1.0],
		[recap_box.leadingAnchor constraintEqualToAnchor:container_view.leadingAnchor constant:-1.0],
		[recap_box.trailingAnchor constraintEqualToAnchor:container_view.trailingAnchor constant:1.0],
		recap_height_constraint,
			[recap_button.leadingAnchor constraintEqualToAnchor:recap_box.leadingAnchor constant:12.0],
			[recap_button.centerYAnchor constraintEqualToAnchor:recap_box.centerYAnchor],
			[recap_label.leadingAnchor constraintEqualToAnchor:recap_button.trailingAnchor constant:12.0],
			[recap_label.centerYAnchor constraintEqualToAnchor:recap_box.centerYAnchor],
			[recap_label.trailingAnchor constraintLessThanOrEqualToAnchor:recap_box.trailingAnchor constant:-14.0],
			[bookmarks_label.leadingAnchor constraintEqualToAnchor:recap_box.leadingAnchor constant:12.0],
			[bookmarks_label.centerYAnchor constraintEqualToAnchor:recap_box.centerYAnchor],
			[bookmarks_label.trailingAnchor constraintLessThanOrEqualToAnchor:clear_button.leadingAnchor constant:-12.0],
			[clear_button.trailingAnchor constraintEqualToAnchor:recap_box.trailingAnchor constant:-12.0],
			[clear_button.centerYAnchor constraintEqualToAnchor:recap_box.centerYAnchor],
		recap_to_table_top_constraint,
		[scroll_view.bottomAnchor constraintEqualToAnchor:podcast_view.topAnchor],
		[scroll_view.leadingAnchor constraintEqualToAnchor:container_view.leadingAnchor],
		[scroll_view.trailingAnchor constraintEqualToAnchor:container_view.trailingAnchor],
		[podcast_view.leadingAnchor constraintEqualToAnchor:container_view.leadingAnchor],
		[podcast_view.trailingAnchor constraintEqualToAnchor:container_view.trailingAnchor],
		[podcast_view.bottomAnchor constraintEqualToAnchor:container_view.bottomAnchor],
		podcast_height_constraint,
		[premium_required_view.topAnchor constraintEqualToAnchor:container_view.safeAreaLayoutGuide.topAnchor constant:18.0],
		[premium_required_view.leadingAnchor constraintEqualToAnchor:container_view.leadingAnchor],
		[premium_required_view.trailingAnchor constraintEqualToAnchor:container_view.trailingAnchor],
		[premium_required_label.topAnchor constraintEqualToAnchor:premium_required_view.topAnchor],
		[premium_required_label.leadingAnchor constraintEqualToAnchor:premium_required_view.leadingAnchor constant:20.0],
		[premium_required_label.trailingAnchor constraintEqualToAnchor:premium_required_view.trailingAnchor constant:-20.0],
		[plans_button.topAnchor constraintEqualToAnchor:premium_required_label.bottomAnchor constant:16.0],
		[plans_button.leadingAnchor constraintEqualToAnchor:premium_required_label.leadingAnchor],
		[plans_button.heightAnchor constraintGreaterThanOrEqualToConstant:36.0],
		[plans_button.bottomAnchor constraintEqualToAnchor:premium_required_view.bottomAnchor]
	]];

	self.recapBoxView = recap_box;
	self.recapButton = recap_button;
	self.recapCountLabel = recap_label;
	self.bookmarksTitleLabel = bookmarks_label;
	self.bookmarksClearButton = clear_button;
	self.recapBoxHeightConstraint = recap_height_constraint;
	self.recapToTableTopConstraint = recap_to_table_top_constraint;
	self.podcastController = podcast_controller;
	self.podcastContainerView = podcast_view;
	self.podcastHeightConstraint = podcast_height_constraint;
	self.tableView = table_view;
	self.tableScrollView = scroll_view;
	self.premiumRequiredView = premium_required_view;
	self.view = container_view;
	[self updateRecapUI];
	[self updatePremiumRequiredView];
	[self updatePodcastPaneForSelectedItem:nil];
}

- (void) loadCachedRecentEntries
{
	if (self.contentMode != MBSidebarContentModeFeeds) {
		return;
	}

	NSURL* cache_url = [self recentEntriesCacheURL];
	if (cache_url != nil) {
		NSData* data = [NSData dataWithContentsOfURL:cache_url options:0 error:nil];
		if (data.length > 0) {
			id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
			NSArray* serialized_items = nil;
			NSDictionary* icons_by_host = nil;
			if ([payload isKindOfClass:[NSDictionary class]]) {
				serialized_items = [(NSDictionary*) payload objectForKey:@"items"];
				icons_by_host = [(NSDictionary*) payload objectForKey:@"icons_by_host"];
			}
			else if ([payload isKindOfClass:[NSArray class]]) {
				serialized_items = (NSArray*) payload;
			}

			if ([serialized_items isKindOfClass:[NSArray class]]) {
				NSMutableArray* cached_items = [NSMutableArray array];
				for (id object in serialized_items) {
					if (![object isKindOfClass:[NSDictionary class]]) {
						continue;
					}

					MBEntry* entry = [self entryFromDictionary:(NSDictionary*) object];
					if (entry == nil) {
						continue;
					}

					[cached_items addObject:entry];
				}

				if (cached_items.count > 0) {
					self.allItems = [cached_items copy];
					if ([icons_by_host isKindOfClass:[NSDictionary class]]) {
						self.iconURLByHost = [self normalizedIconURLByHostFromMap:(NSDictionary*) icons_by_host];
						[self.client primeFeedIconsCacheWithMap:self.iconURLByHost];
					}
					[self applyFiltersAndReload];
				}
			}
		}
	}

	[self showCachedSelectedEntryIfNeeded];
}

- (void) reloadData
{
	[self applyFiltersAndReload];
	if (self.contentMode == MBSidebarContentModeBookmarks) {
		[self fetchBookmarksIfNeeded];
	}
	else if (self.contentMode == MBSidebarContentModeAllPosts) {
		[self fetchAllPostsIfNeeded];
	}
	else {
		[self fetchEntriesIfNeeded];
	}
}

- (void) refreshData
{
	if (self.contentMode == MBSidebarContentModeBookmarks) {
		[self fetchBookmarks];
		return;
	}
	if (self.contentMode == MBSidebarContentModeAllPosts) {
		[self fetchAllPosts];
		return;
	}

	self.hasLoadedRemoteItems = NO;
	[self updateRecapUI];
	[self fetchEntriesIfNeeded];
}

- (void) showBookmarks
{
	if (self.client == nil || self.token.length == 0) {
		return;
	}

	BOOL was_showing_special_mode = [self isShowingSpecialMode];
	if (self.contentMode != MBSidebarContentModeBookmarks) {
		[self clearPreservedHiddenReadState];
		[self resetAllPostsModeState];
		self.contentMode = MBSidebarContentModeBookmarks;
	}

	[self applyFiltersAndReload];
	[self ensureSpecialModeSelectionIfNeeded];
	[self fetchBookmarks];
	if (!was_showing_special_mode && self.specialModeChangedHandler != nil) {
		self.specialModeChangedHandler(YES);
	}
}

- (void) showAllPostsForSelectedSite
{
	if (self.client == nil || self.token.length == 0) {
		return;
	}

	MBEntry* selected_item = [self selectedItem];
	if (selected_item == nil || selected_item.feedID <= 0) {
		return;
	}

	BOOL was_showing_special_mode = [self isShowingSpecialMode];
	if (self.contentMode != MBSidebarContentModeAllPosts) {
		[self clearPreservedHiddenReadState];
		[self resetBookmarksModeState];
		self.contentMode = MBSidebarContentModeAllPosts;
	}

	self.allPostsFeedID = selected_item.feedID;
	self.allPostsSiteName = [self siteNameForEntry:selected_item];
	self.allPostsFeedHost = [self feedHostForEntry:selected_item];
	self.allPostsItems = [self cachedItemsForFeedID:selected_item.feedID];
	[self applyFiltersAndReload];
	[self ensureSpecialModeSelectionIfNeeded];
	[self fetchAllPosts];
	if (!was_showing_special_mode && self.specialModeChangedHandler != nil) {
		self.specialModeChangedHandler(YES);
	}
}

- (void) clearSpecialMode
{
	if (self.contentMode == MBSidebarContentModeFeeds) {
		return;
	}

	NSInteger preferred_entry_id = [self savedSelectedEntryID];
	[self clearPreservedHiddenReadState];
	[self resetBookmarksModeState];
	[self resetAllPostsModeState];
	self.contentMode = MBSidebarContentModeFeeds;
	[self applyFiltersAndReloadPreservingSelectionEntryID:preferred_entry_id];
	if (self.specialModeChangedHandler != nil) {
		self.specialModeChangedHandler(NO);
	}
}

- (BOOL) isShowingBookmarks
{
	return (self.contentMode == MBSidebarContentModeBookmarks);
}

- (BOOL) isShowingSpecialMode
{
	return (self.contentMode != MBSidebarContentModeFeeds);
}

- (BOOL) canShowAllPostsForSelectedSite
{
	MBEntry* selected_item = [self selectedItem];
	return (selected_item != nil && selected_item.feedID > 0 && self.client != nil && self.token.length > 0);
}

- (void) focusAndSelectFirstItem
{
	if (self.tableView == nil) {
		return;
	}

	if ([self shouldShowPremiumRequiredView]) {
		return;
	}

	if (self.items.count > 0) {
		NSIndexSet *index_set = [NSIndexSet indexSetWithIndex:0];
		[self.tableView selectRowIndexes:index_set byExtendingSelection:NO];
		self.selectedRowForStyling = 0;
		[self.tableView scrollRowToVisible:0];
		[self notifySelectionChanged];
	}
	else {
		self.selectedRowForStyling = -1;
	}

	[self focusSidebar];
}

- (BOOL) focusSidebar
{
	if (self.tableView == nil) {
		return NO;
	}

	NSWindow* window = self.view.window;
	if (window == nil) {
		return NO;
	}

	return [window makeFirstResponder:self.tableView];
}

- (BOOL) canToggleSelectedItemReadState
{
	MBEntry* selected_item = [self selectedItem];
	return (selected_item != nil && selected_item.entryID > 0 && self.client != nil && self.token.length > 0);
}

- (BOOL) canMarkAllItemsAsRead
{
	if (self.client == nil || self.token.length == 0) {
		return NO;
	}

	for (MBEntry* item in self.items) {
		if (item.entryID > 0 && !item.isRead) {
			return YES;
		}
	}

	return NO;
}

- (BOOL) canToggleSelectedItemBookmarkedState
{
	MBEntry* selected_item = [self selectedItem];
	return (selected_item != nil && selected_item.entryID > 0 && self.client != nil && self.token.length > 0);
}

- (NSString*) readToggleMenuTitle
{
	return [self readToggleMenuTitleForSelectedItem:[self selectedItem]];
}

- (NSString*) bookmarkToggleMenuTitle
{
	return [self bookmarkToggleMenuTitleForSelectedItem:[self selectedItem]];
}

- (NSString*) readPostsVisibilityMenuTitle
{
	if (self.hideReadPosts) {
		return @"Show Read Posts";
	}

	return @"Hide Read Posts";
}

- (void) toggleSelectedItemReadState
{
	[self toggleSelectedItemReadStateAction:nil];
}

- (void) markAllItemsAsRead
{
	if (![self canMarkAllItemsAsRead]) {
		return;
	}

	NSMutableArray* unread_entry_ids = [NSMutableArray array];
	for (MBEntry* item in self.items) {
		if (item.entryID > 0 && !item.isRead) {
			[unread_entry_ids addObject:@(item.entryID)];
		}
	}

	if (unread_entry_ids.count == 0) {
		return;
	}

	NSArray* entry_ids_to_mark_read = [unread_entry_ids copy];
	__weak typeof(self) weak_self = self;
	[self.client markEntriesAsRead:entry_ids_to_mark_read token:self.token completion:^(NSError * _Nullable error) {
		if (error != nil) {
			return;
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			MBSidebarController* strong_self = weak_self;
			if (strong_self == nil) {
				return;
			}

			[strong_self updateCachedReadState:YES forEntryIDs:entry_ids_to_mark_read];
			[strong_self applyFiltersAndReload];
			[strong_self refreshData];
		});
	}];
}

- (void) toggleSelectedItemBookmarkedState
{
	[self toggleSelectedItemBookmarkedStateAction:nil];
}

- (void) toggleReadPostsVisibility
{
	self.hideReadPosts = !self.hideReadPosts;
	[[NSUserDefaults standardUserDefaults] setBool:self.hideReadPosts forKey:InkwellHideReadPostsDefaultsKey];
	if (self.hideReadPosts) {
		self.preservedVisibleEntryIDsForHiddenReadPosts = nil;
	}
	else {
		[self clearPreservedHiddenReadState];
	}

	[self applyFiltersAndReload];
}

- (MBEntry* _Nullable) selectedItem
{
	NSInteger selected_row = self.tableView.selectedRow;
	if (selected_row < 0 || selected_row >= self.items.count) {
		return nil;
	}

	MBEntry* item = self.items[selected_row];
	if (![item isKindOfClass:[MBEntry class]]) {
		return nil;
	}

	return item;
}

- (void) setPodcastPaneVisible:(BOOL) is_visible
{
	if (self.podcastContainerView == nil || self.podcastHeightConstraint == nil) {
		return;
	}

	self.podcastContainerView.hidden = !is_visible;
	self.podcastHeightConstraint.constant = is_visible ? InkwellSidebarPodcastPaneHeight : 0.0;
}

- (NSString*) podcastArtworkURLStringForEntry:(MBEntry*) entry
{
	NSString* avatar_url = [entry.avatarURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (avatar_url.length > 0) {
		return avatar_url;
	}

	NSString* feed_host = [self normalizedHostString:entry.feedHost ?: @""];
	if (feed_host.length == 0) {
		return @"";
	}

	NSString* icon_url_string = self.iconURLByHost[feed_host];
	return [icon_url_string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

- (void) updatePodcastPaneForSelectedItem:(MBEntry* _Nullable) selected_item
{
	BOOL is_playing = self.podcastController.isPlaying;
	BOOL has_selected_audio_enclosure = [selected_item hasAudioEnclosure];
	if (has_selected_audio_enclosure) {
		BOOL should_replace_podcast_entry = (!is_playing || self.currentPodcastEntry == nil || self.currentPodcastEntry.entryID == selected_item.entryID);
		if (should_replace_podcast_entry) {
			self.currentPodcastEntry = selected_item;
			self.podcastController.entry = selected_item;
			self.podcastController.artworkURLString = [self podcastArtworkURLStringForEntry:selected_item];
		}

		[self setPodcastPaneVisible:YES];
		return;
	}

	if (is_playing) {
		if (self.currentPodcastEntry != nil) {
			self.podcastController.entry = self.currentPodcastEntry;
			self.podcastController.artworkURLString = [self podcastArtworkURLStringForEntry:self.currentPodcastEntry];
		}

		[self setPodcastPaneVisible:YES];
		return;
	}

	self.currentPodcastEntry = nil;
	self.podcastController.entry = nil;
	self.podcastController.artworkURLString = @"";
	[self setPodcastPaneVisible:NO];
}

- (void) reloadTablePreservingSelectionForEntryID:(NSInteger) entry_id notifySelectionIfUnchanged:(BOOL) notify_if_unchanged
{
	if (self.tableView == nil) {
		self.selectedRowForStyling = -1;
		return;
	}

	NSInteger previous_selected_row = self.tableView.selectedRow;
	NSInteger target_row = [self rowForEntryID:entry_id];
	if (target_row < 0 || target_row >= (NSInteger) self.items.count) {
		target_row = -1;
	}

	if (target_row >= 0) {
		self.selectedRowForStyling = target_row;
	}
	else {
		self.selectedRowForStyling = -1;
	}

	self.isPreservingSelectionDuringReload = YES;
	[self.tableView reloadData];

	BOOL did_restore_selection = [self restoreSelectionForEntryID:entry_id notifySelectionIfUnchanged:notify_if_unchanged];
	if (!did_restore_selection && self.tableView.selectedRow >= 0) {
		[self.tableView deselectAll:nil];
		self.selectedRowForStyling = -1;
	}
	else {
		NSInteger selected_row = self.tableView.selectedRow;
		if (selected_row >= 0 && selected_row < self.items.count) {
			self.selectedRowForStyling = selected_row;
		}
		else if (!did_restore_selection) {
			self.selectedRowForStyling = -1;
		}
	}

	self.isPreservingSelectionDuringReload = NO;
	NSInteger current_selected_row = self.tableView.selectedRow;
	[self refreshSelectionStylingForSelectedRow:current_selected_row];
	if (!did_restore_selection && previous_selected_row >= 0 && current_selected_row < 0) {
		[self notifySelectionChanged];
	}
}

- (void) fetchEntriesIfNeeded
{
	if (self.client == nil || self.token.length == 0) {
		return;
	}

	if (self.isFetching || self.hasLoadedRemoteItems) {
		return;
	}

	self.isFetching = YES;
	[self updateRecapUI];
	__block BOOL did_fetch_icons = NO;
	[self.client fetchFeedEntriesWithToken:self.token completion:^(NSArray<MBSubscription *> * _Nullable subscriptions, NSArray<NSDictionary<NSString *,id> *> * _Nullable entries, NSSet * _Nullable unread_entry_ids, BOOL is_finished, NSError * _Nullable error) {
		if (is_finished) {
			self.isFetching = NO;
			[self updateRecapUI];
		}

		if (error != nil) {
			return;
		}

		NSArray<MBEntry *> *sidebar_items = [self sidebarItemsForEntries:entries ?: @[] subscriptions:subscriptions ?: @[] unreadEntryIDs:unread_entry_ids];
		self.hasLoadedRemoteItems = YES;
		self.allItems = sidebar_items;
		[self applyFiltersAndReload];

		if (!did_fetch_icons) {
			did_fetch_icons = YES;
			[self fetchFeedIcons];
		}

		if (is_finished) {
			[self cacheRecentEntries];
		}

		if (is_finished && self.syncCompletedHandler != nil) {
			self.syncCompletedHandler();
		}
	}];
}

- (void) fetchBookmarksIfNeeded
{
	if (self.bookmarkItems.count > 0 || self.isFetchingBookmarks) {
		return;
	}

	[self fetchBookmarks];
}

- (void) fetchBookmarks
{
	if (self.client == nil || self.token.length == 0 || self.isFetchingBookmarks) {
		return;
	}

	self.isFetchingBookmarks = YES;
	self.bookmarksRequestIdentifier += 1;
	NSInteger request_identifier = self.bookmarksRequestIdentifier;
	__weak typeof(self) weak_self = self;
	[self.client fetchRecentBookmarksWithToken:self.token completion:^(NSArray* _Nullable items, NSError* _Nullable error) {
		MBSidebarController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		if (request_identifier != strong_self.bookmarksRequestIdentifier) {
			return;
		}

		strong_self.isFetchingBookmarks = NO;
		if (error != nil || strong_self.contentMode != MBSidebarContentModeBookmarks) {
			return;
		}

		strong_self.bookmarkItems = [strong_self sidebarItemsForBookmarks:items ?: @[]];
		[strong_self applyFiltersAndReload];
		[strong_self ensureSpecialModeSelectionIfNeeded];
	}];
}

- (void) fetchAllPostsIfNeeded
{
	if (self.allPostsItems.count > 0 || self.isFetchingAllPosts) {
		return;
	}

	[self fetchAllPosts];
}

- (void) fetchAllPosts
{
	if (self.client == nil || self.token.length == 0 || self.isFetchingAllPosts || self.allPostsFeedID <= 0) {
		return;
	}

	self.isFetchingAllPosts = YES;
	self.allPostsRequestIdentifier += 1;
	NSInteger request_identifier = self.allPostsRequestIdentifier;
	NSString* site_name = [self.allPostsSiteName copy];
	NSString* feed_host = [self.allPostsFeedHost copy];
	__weak typeof(self) weak_self = self;
	[self.client fetchAllEntriesForFeedID:self.allPostsFeedID token:self.token completion:^(NSArray* _Nullable entries, NSSet* _Nullable unread_entry_ids, BOOL is_finished, NSError* _Nullable error) {
		MBSidebarController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		if (request_identifier != strong_self.allPostsRequestIdentifier) {
			return;
		}

		if (is_finished) {
			strong_self.isFetchingAllPosts = NO;
		}

		if (error != nil || strong_self.contentMode != MBSidebarContentModeAllPosts || strong_self.allPostsFeedID <= 0) {
			return;
		}

		strong_self.allPostsItems = [strong_self sidebarItemsForEntries:entries ?: @[] subscriptionTitle:site_name feedHost:feed_host unreadEntryIDs:unread_entry_ids];
		[strong_self applyFiltersAndReload];
		[strong_self ensureSpecialModeSelectionIfNeeded];
	}];
}

- (void) ensureSpecialModeSelectionIfNeeded
{
	if (![self isShowingSpecialMode] || self.tableView == nil) {
		return;
	}

	if (self.items.count == 0 || self.tableView.selectedRow >= 0) {
		return;
	}

	NSIndexSet* index_set = [NSIndexSet indexSetWithIndex:0];
	[self.tableView selectRowIndexes:index_set byExtendingSelection:NO];
	self.selectedRowForStyling = 0;
	[self.tableView scrollRowToVisible:0];
	[self notifySelectionChanged];
}

- (void) resetBookmarksModeState
{
	self.isFetchingBookmarks = NO;
	self.bookmarksRequestIdentifier += 1;
}

- (void) resetAllPostsModeState
{
	self.isFetchingAllPosts = NO;
	self.allPostsRequestIdentifier += 1;
	self.allPostsItems = @[];
	self.allPostsFeedID = 0;
	self.allPostsSiteName = @"";
	self.allPostsFeedHost = @"";
}

- (void) fetchFeedIcons
{
	if (self.client == nil || self.token.length == 0) {
		return;
	}

	[self.client fetchFeedIconsWithToken:self.token completion:^(NSDictionary<NSString *,NSString *> * _Nullable icons_by_host, NSError * _Nullable error) {
		if (error != nil) {
			return;
		}

		self.iconURLByHost = [self normalizedIconURLByHostFromMap:icons_by_host ?: @{}];
		[self cacheRecentEntries];
		[self.tableView reloadData];
	}];
}

- (NSURL* _Nullable) recentEntriesCacheURL
{
	return [MBPathUtilities appFileURLForSearchPathDirectory:NSCachesDirectory filename:InkwellRecentEntriesCacheFilename createDirectoryIfNeeded:YES];
}

- (NSURL* _Nullable) selectedEntryCacheURL
{
	return [MBPathUtilities appFileURLForSearchPathDirectory:NSCachesDirectory filename:InkwellSidebarSelectedEntryCacheFilename createDirectoryIfNeeded:YES];
}

- (void) cacheRecentEntries
{
	NSURL* cache_url = [self recentEntriesCacheURL];
	if (cache_url == nil) {
		return;
	}

	NSDictionary* payload = [self serializedRecentEntriesPayload];
	NSData* data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
	if (data.length == 0) {
		return;
	}

	[data writeToURL:cache_url atomically:YES];
}

- (MBEntry* _Nullable) cachedSelectedEntry
{
	NSInteger saved_entry_id = [self savedSelectedEntryID];
	if (saved_entry_id <= 0) {
		return nil;
	}

	NSURL* cache_url = [self selectedEntryCacheURL];
	if (cache_url == nil) {
		return nil;
	}

	NSData* data = [NSData dataWithContentsOfURL:cache_url options:0 error:nil];
	if (data.length == 0) {
		return nil;
	}

	id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
	if (![payload isKindOfClass:[NSDictionary class]]) {
		return nil;
	}

	NSDictionary* entry_dictionary = nil;
	NSDictionary* payload_dictionary = (NSDictionary*) payload;
	if ([payload_dictionary[@"entry"] isKindOfClass:[NSDictionary class]]) {
		entry_dictionary = payload_dictionary[@"entry"];
	}
	else {
		entry_dictionary = payload_dictionary;
	}

	MBEntry* entry = [self entryFromDictionary:entry_dictionary];
	if (entry == nil || entry.entryID != saved_entry_id) {
		return nil;
	}

	return entry;
}

- (void) cacheSelectedEntry:(MBEntry*) entry
{
	if (![entry isKindOfClass:[MBEntry class]] || entry.entryID <= 0 || entry.isBookmarkEntry) {
		return;
	}

	NSURL* cache_url = [self selectedEntryCacheURL];
	if (cache_url == nil) {
		return;
	}

	NSDictionary* entry_dictionary = [self dictionaryFromEntry:entry];
	if (entry_dictionary.count == 0) {
		return;
	}

	NSData* data = [NSJSONSerialization dataWithJSONObject:entry_dictionary options:0 error:nil];
	if (data.length == 0) {
		return;
	}

	[data writeToURL:cache_url atomically:YES];
}

- (void) removeCachedSelectedEntry
{
	NSURL* cache_url = [self selectedEntryCacheURL];
	if (cache_url == nil) {
		return;
	}

	[[NSFileManager defaultManager] removeItemAtURL:cache_url error:nil];
}

- (void) showCachedSelectedEntryIfNeeded
{
	if (self.contentMode != MBSidebarContentModeFeeds || self.selectionChangedHandler == nil) {
		return;
	}

	MBEntry* cached_entry = [self cachedSelectedEntry];
	if (cached_entry == nil) {
		return;
	}

	MBEntry* selected_item = [self selectedItem];
	if (selected_item != nil && selected_item.entryID > 0 && selected_item.entryID != cached_entry.entryID) {
		return;
	}

	[self updatePodcastPaneForSelectedItem:cached_entry];
	self.selectionChangedHandler(cached_entry);
}

- (NSDictionary*) serializedRecentEntriesPayload
{
	NSMutableArray* serialized_items = [NSMutableArray array];
	for (id object in self.allItems ?: @[]) {
		if (![object isKindOfClass:[MBEntry class]]) {
			continue;
		}

		NSDictionary* dictionary = [self dictionaryFromEntry:(MBEntry*) object];
		if (dictionary.count == 0) {
			continue;
		}

		[serialized_items addObject:dictionary];
	}

	return @{
		@"version": @1,
		@"items": serialized_items,
		@"icons_by_host": self.iconURLByHost ?: @{}
	};
}

- (NSDictionary*) dictionaryFromEntry:(MBEntry*) entry
{
	if (![entry isKindOfClass:[MBEntry class]] || entry.entryID <= 0) {
		return @{};
	}

	NSMutableDictionary* dictionary = [NSMutableDictionary dictionary];
	dictionary[@"title"] = entry.title ?: @"";
	dictionary[@"url"] = entry.url ?: @"";
	dictionary[@"subscription_title"] = entry.subscriptionTitle ?: @"";
	dictionary[@"summary"] = entry.summary ?: @"";
	dictionary[@"text"] = entry.text ?: @"";
	dictionary[@"source"] = entry.source ?: @"";
	dictionary[@"author"] = entry.author ?: @"";
	dictionary[@"avatar_url"] = entry.avatarURL ?: @"";
	dictionary[@"enclosure_url"] = entry.enclosureURL ?: @"";
	dictionary[@"enclosure_type"] = entry.enclosureType ?: @"";
	dictionary[@"itunes_duration"] = entry.itunesDuration ?: @"";
	dictionary[@"entry_id"] = @(entry.entryID);
	dictionary[@"feed_id"] = @(entry.feedID);
	dictionary[@"feed_host"] = entry.feedHost ?: @"";
	dictionary[@"is_read"] = @(entry.isRead);
	dictionary[@"is_bookmarked"] = @(entry.isBookmarked);
	dictionary[@"is_bookmark_entry"] = @(entry.isBookmarkEntry);

	NSString* date_string = [self iso8601StringFromDate:entry.date];
	if (date_string.length > 0) {
		dictionary[@"date"] = date_string;
	}

	return [dictionary copy];
}

- (MBEntry* _Nullable) entryFromDictionary:(NSDictionary*) dictionary
{
	if (![dictionary isKindOfClass:[NSDictionary class]]) {
		return nil;
	}

	NSInteger entry_id = [self integerValueFromObject:dictionary[@"entry_id"]];
	if (entry_id <= 0) {
		entry_id = [self integerValueFromObject:dictionary[@"id"]];
	}
	if (entry_id <= 0) {
		return nil;
	}

	NSDictionary* enclosure_dictionary = [dictionary[@"enclosure"] isKindOfClass:[NSDictionary class]] ? dictionary[@"enclosure"] : nil;
	MBEntry* entry = [[MBEntry alloc] init];
	entry.title = [self stringValueFromObject:dictionary[@"title"]];
	entry.url = [self stringValueFromObject:dictionary[@"url"]];
	entry.subscriptionTitle = [self stringValueFromObject:dictionary[@"subscription_title"]];
	entry.summary = [self stringValueFromObject:dictionary[@"summary"]];
	entry.text = [self normalizedContentHTMLString:[self stringValueFromObject:dictionary[@"text"]]];
	entry.source = [self stringValueFromObject:dictionary[@"source"]];
	entry.author = [self stringValueFromObject:dictionary[@"author"]];
	entry.avatarURL = [self stringValueFromObject:dictionary[@"avatar_url"]];
	entry.enclosureURL = [self stringValueFromObject:dictionary[@"enclosure_url"]];
	if (entry.enclosureURL.length == 0) {
		entry.enclosureURL = [self stringValueFromObject:enclosure_dictionary[@"enclosure_url"]];
	}
	entry.enclosureType = [self stringValueFromObject:dictionary[@"enclosure_type"]];
	if (entry.enclosureType.length == 0) {
		entry.enclosureType = [self stringValueFromObject:enclosure_dictionary[@"enclosure_type"]];
	}
	entry.itunesDuration = [self stringValueFromObject:dictionary[@"itunes_duration"]];
	if (entry.itunesDuration.length == 0) {
		entry.itunesDuration = [self stringValueFromObject:enclosure_dictionary[@"itunes_duration"]];
	}
	entry.entryID = entry_id;
	entry.feedID = [self integerValueFromObject:dictionary[@"feed_id"]];
	entry.feedHost = [self stringValueFromObject:dictionary[@"feed_host"]];
	entry.isRead = [self boolValueFromObject:dictionary[@"is_read"]];
	entry.isBookmarked = [self boolValueFromObject:dictionary[@"is_bookmarked"]];
	entry.isBookmarkEntry = [self boolValueFromObject:dictionary[@"is_bookmark_entry"]];

	NSString* date_string = [self stringValueFromObject:dictionary[@"date"]];
	if (date_string.length > 0) {
		entry.date = [self dateFromISO8601String:date_string];
	}

	return entry;
}

- (NSString*) iso8601StringFromDate:(NSDate* _Nullable) date
{
	if (date == nil) {
		return @"";
	}

	static NSISO8601DateFormatter* date_formatter;
	static dispatch_once_t once_token;
	dispatch_once(&once_token, ^{
		date_formatter = [[NSISO8601DateFormatter alloc] init];
		date_formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
	});

	return [date_formatter stringFromDate:date] ?: @"";
}

- (NSDictionary<NSString *, NSString *> *) normalizedIconURLByHostFromMap:(NSDictionary<NSString *, NSString *> *)icons_by_host
{
	if (icons_by_host.count == 0) {
		return @{};
	}

	NSMutableDictionary<NSString *, NSString *> *normalized_icons_by_host = [NSMutableDictionary dictionary];
	for (NSString *host_value in icons_by_host) {
		NSString *normalized_host = [self normalizedHostString:host_value];
		if (normalized_host.length == 0) {
			continue;
		}

		NSString *url_value = icons_by_host[host_value];
		if (url_value.length == 0) {
			continue;
		}

		normalized_icons_by_host[normalized_host] = url_value;
	}

	return [normalized_icons_by_host copy];
}

- (NSString *) normalizedHostFromURLString:(NSString *)string
{
	if (string.length == 0) {
		return @"";
	}

	NSURLComponents *components = [NSURLComponents componentsWithString:string];
	NSString *host_value = components.host ?: @"";
	if (host_value.length == 0) {
		NSString *possible_url_string = [NSString stringWithFormat:@"https://%@", string];
		NSURLComponents *host_only_components = [NSURLComponents componentsWithString:possible_url_string];
		host_value = host_only_components.host ?: @"";
	}

	return [self normalizedHostString:host_value];
}

- (NSString *) normalizedHostString:(NSString *)host_string
{
	if (host_string.length == 0) {
		return @"";
	}

	NSString *normalized_host = [[host_string lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([normalized_host hasPrefix:@"www."]) {
		normalized_host = [normalized_host substringFromIndex:4];
	}
	if ([normalized_host hasSuffix:@"."]) {
		normalized_host = [normalized_host substringToIndex:(normalized_host.length - 1)];
	}

	return normalized_host;
}

- (NSImage *) avatarImageForEntry:(MBEntry *)entry
{
	NSString* avatar_url = [entry.avatarURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (avatar_url.length > 0) {
		NSImage* cached_image = [self.avatarLoader cachedImageForURLString:avatar_url];
		if (cached_image != nil) {
			return cached_image;
		}

		[self.avatarLoader loadImageForURLString:avatar_url];
		return [self fallbackAvatarImage];
	}

	NSString *feed_host = [self normalizedHostString:entry.feedHost ?: @""];
	if (feed_host.length == 0) {
		return [self fallbackAvatarImage];
	}

	NSString *icon_url_string = self.iconURLByHost[feed_host];
	if (icon_url_string.length > 0) {
		NSImage* cached_image = [self.avatarLoader cachedImageForURLString:icon_url_string];
		if (cached_image != nil) {
			return cached_image;
		}

		[self.avatarLoader loadImageForURLString:icon_url_string];
	}

	return [self fallbackAvatarImage];
}

- (void) avatarImageDidLoad:(NSNotification*) notification
{
	NSString* url_string = [self stringValueFromObject:notification.userInfo[MBAvatarLoaderURLStringUserInfoKey]];
	if (url_string.length == 0) {
		return;
	}

	[self reloadRowsForAvatarURLString:url_string];
	[self reloadRowsForIconURLString:url_string];
}

- (void) reloadRowsForAvatarURLString:(NSString*) url_string
{
	if (url_string.length == 0 || self.items.count == 0) {
		return;
	}

	NSMutableIndexSet* row_indexes = [NSMutableIndexSet indexSet];
	NSUInteger item_count = self.items.count;
	for (NSUInteger i = 0; i < item_count; i++) {
		MBEntry* entry = self.items[i];
		NSString* entry_avatar_url = [entry.avatarURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		if ([entry_avatar_url isEqualToString:url_string]) {
			[row_indexes addIndex:i];
		}
	}

	if (row_indexes.count == 0) {
		return;
	}

	NSIndexSet* column_indexes = [NSIndexSet indexSetWithIndex:0];
	[self.tableView reloadDataForRowIndexes:row_indexes columnIndexes:column_indexes];
}

- (NSImage *) fallbackAvatarImage
{
	if (self.defaultAvatarImage != nil) {
		return self.defaultAvatarImage;
	}

	NSSize image_size = NSMakeSize(InkwellSidebarAvatarSize, InkwellSidebarAvatarSize);
	NSImage *fallback_image = [[NSImage alloc] initWithSize:image_size];
	[fallback_image lockFocus];
	[[NSColor colorWithWhite:0.78 alpha:1.0] setFill];
	NSRectFill(NSMakeRect(0.0, 0.0, image_size.width, image_size.height));
	[fallback_image unlockFocus];

	self.defaultAvatarImage = fallback_image;
	return fallback_image;
}

- (void) reloadRowsForIconURLString:(NSString*) url_string
{
	if (url_string.length == 0 || self.items.count == 0) {
		return;
	}

	NSMutableIndexSet* row_indexes = [NSMutableIndexSet indexSet];
	NSUInteger item_count = self.items.count;
	for (NSUInteger i = 0; i < item_count; i++) {
		MBEntry* entry = self.items[i];
		NSString* entry_host = [self normalizedHostString:entry.feedHost ?: @""];
		NSString* icon_url_string = self.iconURLByHost[entry_host] ?: @"";
		if ([icon_url_string isEqualToString:url_string]) {
			[row_indexes addIndex:i];
		}
	}

	if (row_indexes.count == 0) {
		return;
	}

	NSIndexSet* column_indexes = [NSIndexSet indexSetWithIndex:0];
	[self.tableView reloadDataForRowIndexes:row_indexes columnIndexes:column_indexes];
}

- (void) setDateFilter:(MBSidebarDateFilter)date_filter
{
	if (_dateFilter == date_filter) {
		return;
	}

	[self clearPreservedHiddenReadState];
	_dateFilter = date_filter;
	if (_dateFilter != MBSidebarDateFilterFading && self.isRecapFetching) {
		self.recapRequestIdentifier += 1;
		[self finishReadingRecapPollingForRequestIdentifier:self.recapRequestIdentifier];
	}
	[self applyFiltersAndReload];
	[self scrollTableToTop];
}

- (void) setSearchQuery:(NSString*) search_query
{
	NSString* normalized_query = [search_query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (normalized_query == nil) {
		normalized_query = @"";
	}

	if ([_searchQuery isEqualToString:normalized_query]) {
		return;
	}

	[self clearPreservedHiddenReadState];
	_searchQuery = [normalized_query copy];
	[self applyFiltersAndReload];
}

- (void) setSortOrder:(MBSidebarSortOrder) sort_order
{
	if (_sortOrder == sort_order) {
		return;
	}

	_sortOrder = sort_order;
	[[NSUserDefaults standardUserDefaults] setInteger:sort_order forKey:InkwellSidebarSortOrderDefaultsKey];
	[self applyFiltersAndReload];
}

- (void) applyFiltersAndReload
{
	[self applyFiltersAndReloadPreservingSelectionEntryID:[self preferredSelectionEntryIDForReload]];
}

- (void) applyFiltersAndReloadPreservingSelectionEntryID:(NSInteger) preferred_entry_id
{
	NSInteger selected_entry_id = [self currentSelectedEntryID];
	BOOL is_searching = (self.contentMode == MBSidebarContentModeFeeds && self.searchQuery.length > 0);
	NSArray* filtered_items = nil;
	if (self.contentMode == MBSidebarContentModeBookmarks) {
		filtered_items = [self.bookmarkItems copy];
	}
	else if (self.contentMode == MBSidebarContentModeAllPosts) {
		filtered_items = [self.allPostsItems copy];
	}
	else if (is_searching) {
		filtered_items = [self filteredItemsForSearchQuery:self.searchQuery];
	}
	else {
		filtered_items = [self filteredItemsForDateFilter:self.dateFilter];
	}
	NSArray* sorted_items = [self sortedItems:(filtered_items ?: @[])];
	if ([self isShowingSpecialMode]) {
		self.items = [sorted_items copy] ?: @[];
	}
	else {
		self.items = [self filteredItemsForReadVisibility:sorted_items selectedEntryID:selected_entry_id];
		if (self.hideReadPosts && self.preservedVisibleEntryIDsForHiddenReadPosts == nil) {
			NSMutableSet* visible_entry_ids = [NSMutableSet set];
			for (MBEntry* entry in self.items) {
				if (entry.entryID > 0) {
					[visible_entry_ids addObject:@(entry.entryID)];
				}
			}
			self.preservedVisibleEntryIDsForHiddenReadPosts = [visible_entry_ids copy];
		}
	}

	[self reloadTablePreservingSelectionForEntryID:preferred_entry_id notifySelectionIfUnchanged:YES];
	if (is_searching || [self isShowingSpecialMode]) {
		[self scrollTableToTop];
	}
	[self updateRecapUI];
	[self updatePremiumRequiredView];
}

- (NSInteger) preferredSelectionEntryIDForReload
{
	MBEntry* selected_item = [self selectedItem];
	if (selected_item != nil && selected_item.entryID > 0 && !selected_item.isBookmarkEntry) {
		return selected_item.entryID;
	}

	if (self.contentMode == MBSidebarContentModeBookmarks) {
		return 0;
	}

	return [self savedSelectedEntryID];
}

- (NSInteger) currentSelectedEntryID
{
	NSInteger selected_row = self.tableView.selectedRow;
	if (selected_row >= 0 && selected_row < self.items.count) {
		MBEntry* selected_item = self.items[(NSUInteger) selected_row];
		if ([selected_item isKindOfClass:[MBEntry class]] && selected_item.entryID > 0) {
			return selected_item.entryID;
		}
	}

	return 0;
}

- (BOOL) restoreSelectionForEntryID:(NSInteger)entry_id notifySelectionIfUnchanged:(BOOL) notify_if_unchanged
{
	if (entry_id <= 0 || self.tableView == nil || self.items.count == 0) {
		return NO;
	}

	NSInteger row = [self rowForEntryID:entry_id];
	if (row < 0 || row >= self.items.count) {
		return NO;
	}

	NSInteger previous_selected_row = self.tableView.selectedRow;
	NSIndexSet* index_set = [NSIndexSet indexSetWithIndex:(NSUInteger) row];
	[self.tableView selectRowIndexes:index_set byExtendingSelection:NO];
	self.selectedRowForStyling = row;
	BOOL is_restoring_saved_selection = (previous_selected_row < 0 && entry_id == [self savedSelectedEntryID]);
	if (is_restoring_saved_selection) {
		[self.tableView layoutSubtreeIfNeeded];

		CGFloat visible_height = 0.0;
		if (self.tableScrollView != nil) {
			visible_height = NSHeight(self.tableScrollView.contentView.bounds);
		}
		if (visible_height <= 0.0) {
			visible_height = NSHeight(self.tableView.bounds);
		}

		NSRect row_rect = [self.tableView rectOfRow:row];
		if (visible_height > 0.0 && NSMaxY(row_rect) <= visible_height) {
			[self scrollTableToTop];
		}
		else {
			[self.tableView scrollRowToVisible:row];
		}
	}
	else {
		[self.tableView scrollRowToVisible:row];
	}

	if (notify_if_unchanged && previous_selected_row == row) {
		[self notifySelectionChanged];
	}

	return YES;
}

- (NSInteger) rowForEntryID:(NSInteger)entry_id
{
	if (entry_id <= 0 || self.items.count == 0) {
		return -1;
	}

	NSUInteger item_count = self.items.count;
	for (NSUInteger i = 0; i < item_count; i++) {
		MBEntry* item = self.items[i];
		if (item.entryID == entry_id) {
			return (NSInteger) i;
		}
	}

	return -1;
}

- (BOOL) isRowSelectedForStyling:(NSInteger) row tableView:(NSTableView*) table_view
{
	BOOL is_selected_row = (row == self.selectedRowForStyling);
	if (!is_selected_row) {
		is_selected_row = (table_view.selectedRow == row);
	}
	if (!is_selected_row) {
		is_selected_row = [table_view isRowSelected:row];
	}

	return is_selected_row;
}

- (void) configureRowView:(MBSidebarRowView*) row_view forRow:(NSInteger) row tableView:(NSTableView*) table_view
{
	if (row_view == nil) {
		return;
	}

	BOOL is_selected_row = [self isRowSelectedForStyling:row tableView:table_view];
	if (is_selected_row || row < 0 || row >= self.items.count) {
		BOOL has_emphasized_selection = [self hasEmphasizedSelectionForTableView:table_view];
		if (is_selected_row) {
			row_view.customSelectionBackgroundColor = has_emphasized_selection ? [NSColor selectedContentBackgroundColor] : [NSColor unemphasizedSelectedContentBackgroundColor];
		}
		else {
			row_view.customSelectionBackgroundColor = nil;
		}
		row_view.customBackgroundColor = nil;
		row_view.customBorderColor = nil;
		return;
	}

	row_view.customSelectionBackgroundColor = nil;
	MBEntry* item = self.items[(NSUInteger) row];
	if (self.contentMode == MBSidebarContentModeBookmarks) {
		row_view.customBackgroundColor = nil;
		row_view.customBorderColor = nil;
		return;
	}

	if (item.isRead) {
		row_view.customBackgroundColor = nil;
		row_view.customBorderColor = nil;
	}
	else {
		row_view.customBackgroundColor = [NSColor colorNamed:InkwellUnreadBackgroundColorName];
		row_view.customBorderColor = [NSColor colorNamed:InkwellUnreadBorderColorName];
//		row_view.customBorderColor = [NSColor colorWithRed:0.80 green:0.84 blue:0.91 alpha:0.58];
	}
}

- (NSInteger) savedSelectedEntryID
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	if ([defaults objectForKey:InkwellSidebarSelectedEntryIDDefaultsKey] == nil) {
		return 0;
	}

	return [defaults integerForKey:InkwellSidebarSelectedEntryIDDefaultsKey];
}

- (void) clearSavedSelectedEntryID
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	[defaults removeObjectForKey:InkwellSidebarSelectedEntryIDDefaultsKey];
	[self removeCachedSelectedEntry];
}

- (void) saveSelectedEntryIDForCurrentSelection
{
	NSInteger selected_row = self.tableView.selectedRow;
	if (selected_row < 0 || selected_row >= self.items.count) {
		[self clearSavedSelectedEntryID];
		return;
	}

	if ([self isShowingSpecialMode]) {
		return;
	}

	MBEntry* selected_item = self.items[(NSUInteger) selected_row];
	if (![selected_item isKindOfClass:[MBEntry class]] || selected_item.entryID <= 0 || selected_item.isBookmarkEntry) {
		return;
	}

	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	[defaults setInteger:selected_item.entryID forKey:InkwellSidebarSelectedEntryIDDefaultsKey];
	[self cacheSelectedEntry:selected_item];
}

- (void) deselectSidebarSelectionPreservingDetail
{
	if (self.tableView == nil || self.tableView.selectedRow < 0) {
		return;
	}

	self.suppressSelectionChangedHandler = YES;
	[self.tableView deselectAll:nil];
	[self updatePodcastPaneForSelectedItem:nil];
}

- (void) scrollTableToTop
{
	if (self.tableView == nil) {
		return;
	}

	if (self.tableView.numberOfRows > 0) {
		[self.tableView scrollRowToVisible:0];
		return;
	}

	if (self.tableScrollView == nil) {
		return;
	}

	NSClipView* content_view = self.tableScrollView.contentView;
	[content_view scrollToPoint:NSMakePoint(0.0, 0.0)];
	[self.tableScrollView reflectScrolledClipView:content_view];
}

- (void) updateRecapUI
{
	BOOL should_show_special_mode = [self shouldShowSpecialModeBanner];
	BOOL should_show_recap = !should_show_special_mode && (self.dateFilter == MBSidebarDateFilterFading) && ![self shouldShowPremiumRequiredView];
	if (self.recapBoxView != nil) {
		self.recapBoxView.hidden = !(should_show_recap || should_show_special_mode);
	}
	if (self.recapBoxHeightConstraint != nil) {
		if (should_show_special_mode) {
			self.recapBoxHeightConstraint.constant = InkwellSidebarBookmarksBoxHeight;
		}
		else {
			self.recapBoxHeightConstraint.constant = should_show_recap ? InkwellSidebarRecapBoxHeight : 0.0;
		}
	}
	if (self.recapToTableTopConstraint != nil) {
		self.recapToTableTopConstraint.constant = (should_show_recap || should_show_special_mode) ? 8.0 : 0.0;
	}

	NSInteger fading_count = [self allFadingItems].count;
	if (self.recapCountLabel != nil) {
		self.recapCountLabel.stringValue = [self recapCountStringForPostsCount:fading_count];
	}
	if (self.recapButton != nil) {
		self.recapButton.enabled = should_show_recap && [self canShowReadingRecap];
		self.recapButton.hidden = !should_show_recap;
	}
	if (self.recapCountLabel != nil) {
		self.recapCountLabel.hidden = !should_show_recap;
	}
	if (self.bookmarksTitleLabel != nil) {
		self.bookmarksTitleLabel.hidden = !should_show_special_mode;
		self.bookmarksTitleLabel.stringValue = should_show_special_mode ? [self specialModeBannerTitle] : @"";
	}
	if (self.bookmarksClearButton != nil) {
		self.bookmarksClearButton.hidden = !should_show_special_mode;
	}
}

- (void) updatePremiumRequiredView
{
	BOOL should_show_premium_required_view = [self shouldShowPremiumRequiredView];
	if (self.tableScrollView != nil) {
		self.tableScrollView.hidden = should_show_premium_required_view;
	}
	if (self.premiumRequiredView != nil) {
		self.premiumRequiredView.hidden = !should_show_premium_required_view;
	}
}

- (void) setRecapFetching:(BOOL)is_fetching
{
	_isRecapFetching = is_fetching;
	[self updateRecapUI];
}

- (NSArray*) allFadingItems
{
	return [self filteredItemsForDateFilter:MBSidebarDateFilterFading];
}

- (NSArray*) allFadingEntryIDs
{
	NSArray* fading_items = [self allFadingItems];
	if (fading_items.count == 0) {
		return @[];
	}

	NSMutableArray* entry_ids = [NSMutableArray array];
	for (MBEntry* entry in fading_items) {
		if (entry.entryID > 0) {
			[entry_ids addObject:@(entry.entryID)];
		}
	}

	return [entry_ids copy];
}

- (NSArray*) cachedItemsForFeedID:(NSInteger) feed_id
{
	if (feed_id <= 0 || self.allItems.count == 0) {
		return @[];
	}

	NSMutableArray* filtered_items = [NSMutableArray array];
	for (MBEntry* item in self.allItems) {
		if (item.feedID == feed_id) {
			[filtered_items addObject:item];
		}
	}

	return [filtered_items copy];
}

- (NSString*) recapCountStringForPostsCount:(NSInteger)post_count
{
	if (post_count == 1) {
		return @"1 older post, grouped";
	}

	return [NSString stringWithFormat:@"%ld older posts, grouped", (long) post_count];
}

- (NSAttributedString*) premiumRequiredMessageAttributedString
{
	NSString* text = @"The Fading tab and Reading Recap feature are only available to Micro.blog Premium subscribers.";
	NSFont* regular_font = [NSFont systemFontOfSize:13.0];
	NSFont* bold_font = [NSFont boldSystemFontOfSize:13.0];
	NSMutableAttributedString* attributed_text = [[NSMutableAttributedString alloc] initWithString:text attributes:@{
		NSFontAttributeName: regular_font,
		NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
	}];

	NSRange fading_range = [text rangeOfString:@"Fading"];
	if (fading_range.location != NSNotFound) {
		[attributed_text addAttribute:NSFontAttributeName value:bold_font range:fading_range];
	}

	NSRange reading_recap_range = [text rangeOfString:@"Reading Recap"];
	if (reading_recap_range.location != NSNotFound) {
		[attributed_text addAttribute:NSFontAttributeName value:bold_font range:reading_recap_range];
	}

	return [attributed_text copy];
}

- (BOOL) canShowReadingRecap
{
	if (self.contentMode != MBSidebarContentModeFeeds) {
		return NO;
	}

	if (![self isPremiumUser]) {
		return NO;
	}

	if (self.client == nil || self.token.length == 0 || self.isRecapFetching) {
		return NO;
	}

	if (!self.hasLoadedRemoteItems || self.isFetching) {
		return NO;
	}

	return ([self allFadingEntryIDs].count > 0);
}

- (BOOL) shouldShowPremiumRequiredView
{
	if (self.contentMode != MBSidebarContentModeFeeds) {
		return NO;
	}

	return (self.dateFilter == MBSidebarDateFilterFading) && ![self isPremiumUser];
}

- (BOOL) shouldShowSpecialModeBanner
{
	return [self isShowingSpecialMode];
}

- (BOOL) isShowingAllPostsMode
{
	return (self.contentMode == MBSidebarContentModeAllPosts);
}

- (NSString*) specialModeBannerTitle
{
	if (self.contentMode == MBSidebarContentModeBookmarks) {
		return @"Showing recent bookmarks";
	}

	NSString* site_name = [self.allPostsSiteName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (site_name.length == 0) {
		site_name = @"this site";
	}

	return [NSString stringWithFormat:@"Showing posts from %@", site_name];
}

- (NSString*) siteNameForEntry:(MBEntry*) entry
{
	NSString* site_name = [entry.subscriptionTitle stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (site_name.length > 0) {
		return site_name;
	}

	NSString* feed_host = [self feedHostForEntry:entry];
	if (feed_host.length > 0) {
		return feed_host;
	}

	NSString* url_string = [entry.url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (url_string.length > 0) {
		return [self normalizedHostFromURLString:url_string];
	}

	return @"";
}

- (NSString*) feedHostForEntry:(MBEntry*) entry
{
	NSString* feed_host = [entry.feedHost stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (feed_host.length > 0) {
		return feed_host;
	}

	NSString* url_string = [entry.url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (url_string.length == 0) {
		return @"";
	}

	return [self normalizedHostFromURLString:url_string];
}

- (BOOL) isPremiumUser
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	if ([defaults objectForKey:InkwellIsPremiumDefaultsKey] == nil) {
		return YES;
	}

	return [defaults boolForKey:InkwellIsPremiumDefaultsKey];
}

- (BOOL) savedHideReadPosts
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	if ([defaults objectForKey:InkwellHideReadPostsDefaultsKey] == nil) {
		return NO;
	}

	return [defaults boolForKey:InkwellHideReadPostsDefaultsKey];
}

- (MBSidebarSortOrder) savedSortOrder
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	if ([defaults objectForKey:InkwellSidebarSortOrderDefaultsKey] == nil) {
		return MBSidebarSortOrderNewestFirst;
	}

	NSInteger raw_value = [defaults integerForKey:InkwellSidebarSortOrderDefaultsKey];
	if (raw_value == MBSidebarSortOrderOldestFirst) {
		return MBSidebarSortOrderOldestFirst;
	}

	return MBSidebarSortOrderNewestFirst;
}

- (IBAction) showReadingRecap:(id)sender
{
	#pragma unused(sender)
	if (![self canShowReadingRecap]) {
		return;
	}

	NSArray* entry_ids = [self allFadingEntryIDs];
	self.recapRequestIdentifier += 1;
	NSInteger request_identifier = self.recapRequestIdentifier;
	[self setRecapFetching:YES];
	[self.client beginManualNetworkingActivity];
	[self pollReadingRecapForEntryIDs:entry_ids attempt:1 requestIdentifier:request_identifier];
}

- (IBAction) clearSpecialModeAction:(id)sender
{
	#pragma unused(sender)
	[self clearSpecialMode];
}

- (IBAction) openPlansAction:(id)sender
{
	#pragma unused(sender)
	NSURL* plans_url = [NSURL URLWithString:InkwellPlansURLString];
	if (plans_url == nil) {
		return;
	}

	[[NSWorkspace sharedWorkspace] openURL:plans_url];
}

- (void) finishReadingRecapPollingForRequestIdentifier:(NSInteger) request_identifier
{
	if (request_identifier != self.recapRequestIdentifier || !self.isRecapFetching) {
		return;
	}

	[self.client endManualNetworkingActivity];
	[self setRecapFetching:NO];
}

- (void) pollReadingRecapForEntryIDs:(NSArray*) entry_ids attempt:(NSInteger)attempt requestIdentifier:(NSInteger)request_identifier
{
	if (request_identifier != self.recapRequestIdentifier) {
		return;
	}

	if (attempt > InkwellSidebarRecapMaxAttempts) {
		[self finishReadingRecapPollingForRequestIdentifier:request_identifier];
		return;
	}

	[self.client fetchReadingRecapForEntryIDs:entry_ids token:self.token completion:^(NSInteger status_code, NSString* _Nullable html, NSError* _Nullable error) {
		if (request_identifier != self.recapRequestIdentifier) {
			return;
		}

		if (error != nil) {
			[self finishReadingRecapPollingForRequestIdentifier:request_identifier];
			return;
		}

		if (status_code == 200) {
			[self finishReadingRecapPollingForRequestIdentifier:request_identifier];
			if (self.readingRecapHandler != nil) {
				self.readingRecapHandler(html ?: @"");
			}
			return;
		}

		if (status_code != 202) {
			[self finishReadingRecapPollingForRequestIdentifier:request_identifier];
			return;
		}

		if (attempt >= InkwellSidebarRecapMaxAttempts) {
			[self finishReadingRecapPollingForRequestIdentifier:request_identifier];
			return;
		}

		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (InkwellSidebarRecapPollInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			[self pollReadingRecapForEntryIDs:entry_ids attempt:(attempt + 1) requestIdentifier:request_identifier];
		});
	}];
}

- (NSArray<MBEntry *> *) filteredItemsForDateFilter:(MBSidebarDateFilter)date_filter
{
	if (self.allItems.count == 0) {
		return @[];
	}

	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSDate *start_of_today = [calendar startOfDayForDate:[NSDate date]];
	NSDate *start_of_tomorrow = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:start_of_today options:0];
	NSDate *start_of_two_days_ago = [calendar dateByAddingUnit:NSCalendarUnitDay value:-2 toDate:start_of_today options:0];
	NSDate *start_of_six_days_ago = [calendar dateByAddingUnit:NSCalendarUnitDay value:-6 toDate:start_of_today options:0];
	NSMutableArray<MBEntry *> *filtered_items = [NSMutableArray array];

	for (MBEntry *entry in self.allItems) {
		NSDate *entry_date = entry.date;
		if (entry_date == nil) {
			continue;
		}

		BOOL should_include = NO;
		switch (date_filter) {
			case MBSidebarDateFilterToday:
				should_include = ([entry_date compare:start_of_today] != NSOrderedAscending) && ([entry_date compare:start_of_tomorrow] == NSOrderedAscending);
				break;

			case MBSidebarDateFilterRecent:
				should_include = ([entry_date compare:start_of_two_days_ago] != NSOrderedAscending) && ([entry_date compare:start_of_today] == NSOrderedAscending);
				break;

			case MBSidebarDateFilterFading:
				should_include = ([entry_date compare:start_of_six_days_ago] != NSOrderedAscending) && ([entry_date compare:start_of_two_days_ago] == NSOrderedAscending);
				break;
		}

		if (should_include) {
			[filtered_items addObject:entry];
		}
	}

	return [filtered_items copy];
}

- (NSArray<MBEntry *> *) filteredItemsForSearchQuery:(NSString*) search_query
{
	if (self.allItems.count == 0 || search_query.length == 0) {
		return @[];
	}

	NSStringCompareOptions compare_options = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
	NSMutableArray<MBEntry *> *filtered_items = [NSMutableArray array];

	for (MBEntry *entry in self.allItems) {
		NSString* title_value = entry.title ?: @"";
		NSString* text_value = entry.text ?: @"";
		NSString* subscription_title_value = entry.subscriptionTitle ?: @"";
		BOOL matches_query = [title_value rangeOfString:search_query options:compare_options].location != NSNotFound;
		if (!matches_query) {
			matches_query = [text_value rangeOfString:search_query options:compare_options].location != NSNotFound;
		}
		if (!matches_query) {
			matches_query = [subscription_title_value rangeOfString:search_query options:compare_options].location != NSNotFound;
		}

		if (matches_query) {
			[filtered_items addObject:entry];
		}
	}

	return [filtered_items copy];
}

- (void) clearPreservedHiddenReadState
{
	self.preservedVisibleEntryIDsForHiddenReadPosts = nil;
}

- (NSArray*) filteredItemsForReadVisibility:(NSArray*) items selectedEntryID:(NSInteger)selected_entry_id
{
	if (!self.hideReadPosts || items.count == 0) {
		return [items copy];
	}

	NSMutableArray* filtered_items = [NSMutableArray array];
	for (MBEntry* entry in items) {
		BOOL is_selected_entry = (selected_entry_id > 0 && entry.entryID == selected_entry_id);
		BOOL is_preserved_visible_entry = (entry.entryID > 0 && [self.preservedVisibleEntryIDsForHiddenReadPosts containsObject:@(entry.entryID)]);
		if (!entry.isRead || is_selected_entry || is_preserved_visible_entry) {
			[filtered_items addObject:entry];
		}
	}

	return [filtered_items copy];
}

- (NSArray*) sortedItems:(NSArray*) items
{
	if (items.count < 2) {
		return [items copy];
	}

	return [items sortedArrayUsingComparator:^NSComparisonResult(id first_object, id second_object) {
		MBEntry* first_entry = [first_object isKindOfClass:[MBEntry class]] ? first_object : nil;
		MBEntry* second_entry = [second_object isKindOfClass:[MBEntry class]] ? second_object : nil;
		if (first_entry == nil || second_entry == nil) {
			return NSOrderedSame;
		}

		return [self compareEntry:first_entry toEntry:second_entry];
	}];
}

- (NSComparisonResult) compareEntry:(MBEntry*) first_entry toEntry:(MBEntry*) second_entry
{
	NSDate* first_date = first_entry.date;
	NSDate* second_date = second_entry.date;
	if (first_date != nil && second_date != nil) {
		NSComparisonResult date_result = [first_date compare:second_date];
		if (date_result != NSOrderedSame) {
			if (self.sortOrder == MBSidebarSortOrderNewestFirst) {
				return (date_result == NSOrderedAscending) ? NSOrderedDescending : NSOrderedAscending;
			}
			return date_result;
		}
	}
	else if (first_date != nil || second_date != nil) {
		return (first_date != nil) ? NSOrderedAscending : NSOrderedDescending;
	}

	if (first_entry.entryID != second_entry.entryID) {
		if (self.sortOrder == MBSidebarSortOrderNewestFirst) {
			return (first_entry.entryID > second_entry.entryID) ? NSOrderedAscending : NSOrderedDescending;
		}
		return (first_entry.entryID < second_entry.entryID) ? NSOrderedAscending : NSOrderedDescending;
	}

	NSString* first_title = first_entry.title ?: @"";
	NSString* second_title = second_entry.title ?: @"";
	return [first_title localizedCaseInsensitiveCompare:second_title];
}

- (NSArray<MBEntry *> *) sidebarItemsForEntries:(NSArray<NSDictionary<NSString *, id> *> *)entries subscriptions:(NSArray<MBSubscription *> *)subscriptions unreadEntryIDs:(NSSet * _Nullable)unread_entry_ids
{
	NSMutableArray<MBEntry *> *sidebar_items = [NSMutableArray array];
	NSMutableDictionary<NSNumber *, NSString *> *subscription_titles_by_feed_id = [NSMutableDictionary dictionary];
	NSMutableDictionary<NSNumber *, NSString *> *feed_hosts_by_feed_id = [NSMutableDictionary dictionary];

	for (MBSubscription *subscription in subscriptions) {
		if (subscription.feedID <= 0) {
			continue;
		}

		NSString *subscription_title = [self normalizedPreviewString:subscription.title ?: @""];
		if (subscription_title.length > 0) {
			subscription_titles_by_feed_id[@(subscription.feedID)] = subscription_title;
		}

		NSString *site_host = [self normalizedHostFromURLString:subscription.siteURL ?: @""];
		if (site_host.length == 0) {
			site_host = [self normalizedHostFromURLString:subscription.feedURL ?: @""];
		}
		if (site_host.length > 0) {
			feed_hosts_by_feed_id[@(subscription.feedID)] = site_host;
		}
	}

	for (NSDictionary<NSString *, id> *entry in entries) {
		NSInteger feed_id_value = [self integerValueFromObject:entry[@"feed_id"]];
		NSString *subscription_title = subscription_titles_by_feed_id[@(feed_id_value)] ?: @"";
		NSString *feed_host = feed_hosts_by_feed_id[@(feed_id_value)] ?: @"";
		MBEntry* sidebar_entry = [self sidebarItemForEntryDictionary:entry subscriptionTitle:subscription_title feedHost:feed_host unreadEntryIDs:unread_entry_ids];
		if (sidebar_entry != nil) {
			[sidebar_items addObject:sidebar_entry];
		}
	}

	return [sidebar_items copy];
}

- (NSArray<MBEntry *> *) sidebarItemsForEntries:(NSArray*) entries subscriptionTitle:(NSString*) subscription_title feedHost:(NSString*) feed_host unreadEntryIDs:(NSSet* _Nullable) unread_entry_ids
{
	NSMutableArray* sidebar_items = [NSMutableArray array];
	for (id object in entries) {
		if (![object isKindOfClass:[NSDictionary class]]) {
			continue;
		}

		MBEntry* sidebar_entry = [self sidebarItemForEntryDictionary:(NSDictionary*) object subscriptionTitle:subscription_title feedHost:feed_host unreadEntryIDs:unread_entry_ids];
		if (sidebar_entry != nil) {
			if (sidebar_entry.feedID <= 0) {
				sidebar_entry.feedID = self.allPostsFeedID;
			}
			if (sidebar_entry.feedHost.length == 0) {
				sidebar_entry.feedHost = feed_host ?: @"";
			}
			[sidebar_items addObject:sidebar_entry];
		}
	}

	return [sidebar_items copy];
}

- (MBEntry* _Nullable) sidebarItemForEntryDictionary:(NSDictionary*) entry subscriptionTitle:(NSString*) subscription_title feedHost:(NSString*) feed_host unreadEntryIDs:(NSSet* _Nullable) unread_entry_ids
{
	NSString* title_value = [self normalizedPreviewString:[self stringValueFromObject:entry[@"title"]]];
	NSString* summary_value = [self normalizedPreviewString:[self stringValueFromObject:entry[@"summary"]]];
	NSString* author_value = [self normalizedPreviewString:[self stringValueFromObject:entry[@"author"]]];
	NSString* content_html_value = [self stringValueFromObject:entry[@"content_html"]];
	if (content_html_value.length == 0) {
		content_html_value = [self stringValueFromObject:entry[@"content"]];
	}
	content_html_value = [self normalizedContentHTMLString:content_html_value];
	NSDictionary* enclosure_dictionary = [entry[@"enclosure"] isKindOfClass:[NSDictionary class]] ? entry[@"enclosure"] : nil;
	NSString* enclosure_url_value = [self stringValueFromObject:enclosure_dictionary[@"enclosure_url"]];
	NSString* enclosure_type_value = [self stringValueFromObject:enclosure_dictionary[@"enclosure_type"]];
	NSString* itunes_duration_value = [self stringValueFromObject:enclosure_dictionary[@"itunes_duration"]];
	NSString* source_value = [self normalizedPreviewString:[self stringValueFromObject:entry[@"source"]]];
	NSDate* entry_date = [self dateValueFromEntry:entry];
	NSInteger entry_id_value = [self integerValueFromObject:entry[@"id"]];
	id read_object = entry[@"is_read"] ?: entry[@"read"];
	BOOL is_read_value = [self boolValueFromObject:read_object];
	id bookmarked_object = entry[@"is_bookmarked"] ?: entry[@"is_starred"];
	if (bookmarked_object == nil) {
		bookmarked_object = entry[@"bookmarked"] ?: entry[@"starred"];
	}
	BOOL is_bookmarked_value = [self boolValueFromObject:bookmarked_object];
	if (unread_entry_ids != nil && entry_id_value > 0) {
		is_read_value = ![unread_entry_ids containsObject:@(entry_id_value)];
	}

	NSString* resolved_source = source_value;
	if (resolved_source.length == 0) {
		resolved_source = author_value;
	}
	if (resolved_source.length == 0) {
		resolved_source = @"";
	}

	MBEntry* sidebar_entry = [[MBEntry alloc] init];
	sidebar_entry.title = title_value;
	sidebar_entry.url = [self stringValueFromObject:entry[@"url"]];
	sidebar_entry.subscriptionTitle = subscription_title ?: @"";
	sidebar_entry.summary = summary_value;
	sidebar_entry.text = content_html_value;
	sidebar_entry.source = resolved_source;
	sidebar_entry.author = author_value;
	sidebar_entry.enclosureURL = enclosure_url_value;
	sidebar_entry.enclosureType = enclosure_type_value;
	sidebar_entry.itunesDuration = itunes_duration_value;
	sidebar_entry.entryID = entry_id_value;
	sidebar_entry.feedID = [self integerValueFromObject:entry[@"feed_id"]];
	sidebar_entry.feedHost = feed_host ?: @"";
	sidebar_entry.date = entry_date;
	sidebar_entry.isRead = is_read_value;
	sidebar_entry.isBookmarked = is_bookmarked_value;

	return sidebar_entry;
}

- (NSArray<MBEntry *> *) sidebarItemsForBookmarks:(NSArray*) items
{
	NSMutableArray<MBEntry *> *sidebar_items = [NSMutableArray array];

	for (id object in items) {
		if (![object isKindOfClass:[NSDictionary class]]) {
			continue;
		}

		NSDictionary* item = (NSDictionary*) object;
		NSDictionary* author = nil;
		if ([item[@"author"] isKindOfClass:[NSDictionary class]]) {
			author = (NSDictionary*) item[@"author"];
		}

		NSString* author_name = [self normalizedPreviewString:[self stringValueFromObject:author[@"name"]]];
		NSString* author_avatar = [self stringValueFromObject:author[@"avatar"]];
		NSString* url_string = [self stringValueFromObject:item[@"url"]];
		NSString* summary_value = [self normalizedPreviewString:[self stringValueFromObject:item[@"summary"]]];
		NSInteger entry_id_value = [self integerValueFromObject:item[@"id"]];
		NSDate* entry_date = [self dateValueFromEntry:item];

		if (author_name.length == 0) {
			author_name = [self normalizedHostFromURLString:url_string];
		}

		MBEntry* sidebar_entry = [[MBEntry alloc] init];
		sidebar_entry.title = author_name;
		sidebar_entry.url = url_string;
		sidebar_entry.subscriptionTitle = @"";
		sidebar_entry.summary = summary_value;
		sidebar_entry.text = @"";
		sidebar_entry.source = @"";
		sidebar_entry.avatarURL = author_avatar;
		sidebar_entry.entryID = entry_id_value;
		sidebar_entry.feedID = 0;
		sidebar_entry.feedHost = [self normalizedHostFromURLString:url_string];
		sidebar_entry.date = entry_date;
		sidebar_entry.isRead = YES;
		sidebar_entry.isBookmarked = YES;
		sidebar_entry.isBookmarkEntry = YES;

		[sidebar_items addObject:sidebar_entry];
	}

	return [sidebar_items copy];
}

- (NSString *) stringValueFromObject:(id)object
{
	if ([object isKindOfClass:[NSString class]]) {
		return object;
	}

	return @"";
}

- (NSInteger) integerValueFromObject:(id)object
{
	if ([object isKindOfClass:[NSNumber class]]) {
		return [(NSNumber *) object integerValue];
	}

	if ([object isKindOfClass:[NSString class]]) {
		return [(NSString *) object integerValue];
	}

	return 0;
}

- (BOOL) openSelectedItemInBrowser
{
	MBEntry* selected_item = [self selectedItem];
	if (selected_item == nil) {
		return NO;
	}

	NSString* url_string = [selected_item.url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (url_string.length == 0) {
		return NO;
	}

	NSURL* open_url = [NSURL URLWithString:url_string];
	if (open_url == nil) {
		return NO;
	}

	return [[NSWorkspace sharedWorkspace] openURL:open_url];
}

- (NSMenu*) sidebarContextMenu
{
	if (self.contextMenu != nil) {
		return self.contextMenu;
	}

	NSMenu* menu = [[NSMenu alloc] initWithTitle:@""];
	SEL new_post_selector = NSSelectorFromString(@"newPost:");
	SEL toggle_read_selector = @selector(toggleSelectedItemReadStateAction:);
	SEL toggle_bookmark_selector = NSSelectorFromString(@"toggleSelectedItemBookmarkedState:");
	SEL show_conversation_selector = NSSelectorFromString(@"showConversation:");
	SEL show_highlights_selector = NSSelectorFromString(@"showHighlights:");
	SEL show_all_posts_selector = NSSelectorFromString(@"showAllPosts:");

	NSMenuItem* new_post_item = [[NSMenuItem alloc] initWithTitle:@"New Post..." action:new_post_selector keyEquivalent:@""];
	new_post_item.target = nil;
	[menu addItem:new_post_item];

	NSMenuItem* toggle_read_item = [[NSMenuItem alloc] initWithTitle:@"Mark as Read" action:toggle_read_selector keyEquivalent:@""];
	toggle_read_item.target = self;
	[menu addItem:toggle_read_item];

	NSMenuItem* toggle_bookmark_item = [[NSMenuItem alloc] initWithTitle:@"Bookmark" action:toggle_bookmark_selector keyEquivalent:@""];
	toggle_bookmark_item.target = nil;
	[menu addItem:toggle_bookmark_item];

	[menu addItem:[NSMenuItem separatorItem]];

	NSMenuItem* show_conversation_item = [[NSMenuItem alloc] initWithTitle:@"Show Conversation" action:show_conversation_selector keyEquivalent:@""];
	show_conversation_item.target = nil;
	[menu addItem:show_conversation_item];

	NSMenuItem* show_highlights_item = [[NSMenuItem alloc] initWithTitle:@"Show Highlights" action:show_highlights_selector keyEquivalent:@""];
	show_highlights_item.target = nil;
	[menu addItem:show_highlights_item];

	NSMenuItem* show_all_posts_item = [[NSMenuItem alloc] initWithTitle:@"Show All Posts" action:show_all_posts_selector keyEquivalent:@""];
	show_all_posts_item.target = nil;
	[menu addItem:show_all_posts_item];

	[menu addItem:[NSMenuItem separatorItem]];

	NSMenuItem* open_item = [[NSMenuItem alloc] initWithTitle:[NSString mb_openInBrowserString] action:@selector(openSelectedItemInBrowserAction:) keyEquivalent:@""];
	open_item.target = self;
	[menu addItem:open_item];

	NSMenuItem* copy_item = [[NSMenuItem alloc] initWithTitle:@"Copy Link" action:@selector(copySelectedItemLinkAction:) keyEquivalent:@""];
	copy_item.target = self;
	[menu addItem:copy_item];

	self.contextMenu = menu;
	return self.contextMenu;
}

- (IBAction) openSelectedItemInBrowserAction:(id)sender
{
	#pragma unused(sender)
	[self openSelectedItemInBrowser];
}

- (IBAction) toggleSelectedItemReadStateAction:(id)sender
{
	#pragma unused(sender)

	MBEntry* selected_item = [self selectedItem];
	if (selected_item == nil || selected_item.entryID <= 0) {
		return;
	}

	if (self.client == nil || self.token.length == 0) {
		return;
	}

	BOOL should_mark_as_unread = selected_item.isRead;
	NSInteger entry_id = selected_item.entryID;
	NSInteger selected_row = self.tableView.selectedRow;
	__weak typeof(self) weak_self = self;
	void (^completion_handler)(NSError* _Nullable) = ^(NSError* _Nullable error) {
		if (error != nil) {
			return;
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			MBSidebarController* strong_self = weak_self;
			if (strong_self == nil) {
				return;
			}

			[strong_self updateCachedReadState:!should_mark_as_unread forEntryID:entry_id];
			if (should_mark_as_unread) {
				[strong_self clearSavedSelectedEntryID];
				[strong_self deselectSidebarSelectionPreservingDetail];
			}
			if (strong_self.hideReadPosts) {
				[strong_self applyFiltersAndReload];
			}
			else {
				[strong_self reloadRowForEntryID:entry_id preferredRow:selected_row];
			}
		});
	};

	if (should_mark_as_unread) {
		[self.client markAsUnread:entry_id token:self.token completion:completion_handler];
	}
	else {
		[self.client markAsRead:entry_id token:self.token completion:completion_handler];
	}
}

- (IBAction) toggleSelectedItemBookmarkedStateAction:(id)sender
{
	#pragma unused(sender)

	MBEntry* selected_item = [self selectedItem];
	if (selected_item == nil || selected_item.entryID <= 0) {
		return;
	}

	if (self.client == nil || self.token.length == 0) {
		return;
	}

	BOOL should_unbookmark = selected_item.isBookmarked;
	NSInteger entry_id = selected_item.entryID;
	NSInteger selected_row = self.tableView.selectedRow;
	__weak typeof(self) weak_self = self;
	void (^completion_handler)(NSError* _Nullable) = ^(NSError* _Nullable error) {
		if (error != nil) {
			return;
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			MBSidebarController* strong_self = weak_self;
			if (strong_self == nil) {
				return;
			}

			[strong_self updateCachedBookmarkedState:!should_unbookmark forEntryID:entry_id];
			[strong_self reloadRowForEntryID:entry_id preferredRow:selected_row];
		});
	};

	if (should_unbookmark) {
		[self.client unbookmarkEntry:entry_id token:self.token completion:completion_handler];
	}
	else {
		[self.client bookmarkEntry:entry_id token:self.token completion:completion_handler];
	}
}

- (NSString*) readToggleMenuTitleForSelectedItem:(MBEntry* _Nullable) selected_item
{
	if (selected_item != nil && selected_item.isRead) {
		return @"Mark as Unread";
	}

	return @"Mark as Read";
}

- (NSString*) bookmarkToggleMenuTitleForSelectedItem:(MBEntry* _Nullable) selected_item
{
	if (selected_item != nil && selected_item.isBookmarked) {
		return @"Unbookmark";
	}

	return @"Bookmark";
}

- (IBAction) copySelectedItemLinkAction:(id)sender
{
	#pragma unused(sender)
	MBEntry* selected_item = [self selectedItem];
	if (selected_item == nil) {
		return;
	}

	NSString* url_string = [selected_item.url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (url_string.length == 0) {
		return;
	}

	NSPasteboard* pasteboard = [NSPasteboard generalPasteboard];
	[pasteboard clearContents];
	[pasteboard setString:url_string forType:NSPasteboardTypeString];
}

- (BOOL) validateMenuItem:(NSMenuItem*) menu_item
{
	if (menu_item.action == NSSelectorFromString(@"newPost:")) {
		return ([self selectedItem] != nil);
	}
	if (menu_item.action == @selector(toggleSelectedItemReadStateAction:)) {
		MBEntry* selected_item = [self selectedItem];
		menu_item.title = [self readToggleMenuTitleForSelectedItem:selected_item];
		return (selected_item != nil && selected_item.entryID > 0 && self.client != nil && self.token.length > 0);
	}
	if (menu_item.action == @selector(toggleSelectedItemBookmarkedStateAction:)) {
		MBEntry* selected_item = [self selectedItem];
		menu_item.title = [self bookmarkToggleMenuTitleForSelectedItem:selected_item];
		return (selected_item != nil && selected_item.entryID > 0 && self.client != nil && self.token.length > 0);
	}
	if (menu_item.action == NSSelectorFromString(@"showAllPosts:")) {
		return [self canShowAllPostsForSelectedSite];
	}
	if (menu_item.action == NSSelectorFromString(@"showHighlights:")) {
		return YES;
	}
	if (menu_item.action == @selector(showReadingRecap:)) {
		return [self canShowReadingRecap];
	}

	if (menu_item.action != @selector(openSelectedItemInBrowserAction:) && menu_item.action != @selector(copySelectedItemLinkAction:)) {
		return YES;
	}

	MBEntry* selected_item = [self selectedItem];
	if (selected_item == nil) {
		return NO;
	}

	NSString* url_string = [selected_item.url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	return (url_string.length > 0);
}

- (void) notifySelectionChanged
{
	NSInteger selected_row = self.tableView.selectedRow;
	if (selected_row >= 0 && selected_row < self.items.count) {
		MBEntry *item = self.items[(NSUInteger) selected_row];
		if (![self isShowingSpecialMode] && item.entryID > 0 && !item.isBookmarkEntry) {
			[self cacheSelectedEntry:item];
		}
		[self markSelectedItemAsReadIfNeeded:item atRow:selected_row];
		[self updatePodcastPaneForSelectedItem:item];
		if (self.selectionChangedHandler != nil) {
			self.selectionChangedHandler(item);
		}
		return;
	}

	[self updatePodcastPaneForSelectedItem:nil];
	if (self.selectionChangedHandler != nil) {
		self.selectionChangedHandler(nil);
	}
}

- (void) markSelectedItemAsReadIfNeeded:(MBEntry *)item atRow:(NSInteger)row
{
	if (item == nil || item.isRead || item.entryID <= 0 || item.isBookmarkEntry || self.contentMode == MBSidebarContentModeBookmarks) {
		return;
	}

	if (self.client == nil || self.token.length == 0) {
		return;
	}

	NSInteger entry_id = item.entryID;
	[self.client markAsRead:entry_id token:self.token completion:^(NSError * _Nullable error) {
		if (error != nil) {
			return;
		}

		[self updateCachedReadState:YES forEntryID:entry_id];
		if (self.hideReadPosts) {
			[self applyFiltersAndReload];
		}
		else {
			[self reloadRowForEntryID:entry_id preferredRow:row];
		}
	}];
}

- (void) updateCachedReadState:(BOOL)is_read forEntryID:(NSInteger)entry_id
{
	if (entry_id <= 0) {
		return;
	}

	for (MBEntry *cached_entry in self.allItems) {
		if (cached_entry.entryID == entry_id) {
			cached_entry.isRead = is_read;
		}
	}

	for (MBEntry *cached_entry in self.items) {
		if (cached_entry.entryID == entry_id) {
			cached_entry.isRead = is_read;
		}
	}

	for (MBEntry* cached_entry in self.allPostsItems) {
		if (cached_entry.entryID == entry_id) {
			cached_entry.isRead = is_read;
		}
	}
}

- (void) updateCachedReadState:(BOOL) is_read forEntryIDs:(NSArray*) entry_ids
{
	NSMutableSet* entry_ids_to_update = [NSMutableSet set];
	for (NSNumber* entry_id_value in entry_ids) {
		NSInteger entry_id = [entry_id_value integerValue];
		if (entry_id > 0) {
			[entry_ids_to_update addObject:@(entry_id)];
		}
	}

	if (entry_ids_to_update.count == 0) {
		return;
	}

	for (MBEntry* cached_entry in self.allItems) {
		if ([entry_ids_to_update containsObject:@(cached_entry.entryID)]) {
			cached_entry.isRead = is_read;
		}
	}

	for (MBEntry* cached_entry in self.items) {
		if ([entry_ids_to_update containsObject:@(cached_entry.entryID)]) {
			cached_entry.isRead = is_read;
		}
	}

	for (MBEntry* cached_entry in self.allPostsItems) {
		if ([entry_ids_to_update containsObject:@(cached_entry.entryID)]) {
			cached_entry.isRead = is_read;
		}
	}
}

- (void) updateCachedBookmarkedState:(BOOL)is_bookmarked forEntryID:(NSInteger)entry_id
{
	if (entry_id <= 0) {
		return;
	}

	for (MBEntry *cached_entry in self.allItems) {
		if (cached_entry.entryID == entry_id) {
			cached_entry.isBookmarked = is_bookmarked;
		}
	}

	for (MBEntry *cached_entry in self.items) {
		if (cached_entry.entryID == entry_id) {
			cached_entry.isBookmarked = is_bookmarked;
		}
	}

	for (MBEntry* cached_entry in self.bookmarkItems) {
		if (cached_entry.entryID == entry_id) {
			cached_entry.isBookmarked = is_bookmarked;
		}
	}

	for (MBEntry* cached_entry in self.allPostsItems) {
		if (cached_entry.entryID == entry_id) {
			cached_entry.isBookmarked = is_bookmarked;
		}
	}
}

- (void) reloadRowForEntryID:(NSInteger)entry_id preferredRow:(NSInteger)preferred_row
{
	NSInteger row_to_reload = -1;
	if (preferred_row >= 0 && preferred_row < self.items.count) {
		MBEntry *preferred_entry = self.items[(NSUInteger) preferred_row];
		if (preferred_entry.entryID == entry_id) {
			row_to_reload = preferred_row;
		}
	}

	if (row_to_reload < 0) {
		NSUInteger item_count = self.items.count;
		for (NSUInteger i = 0; i < item_count; i++) {
			MBEntry *entry = self.items[i];
			if (entry.entryID == entry_id) {
				row_to_reload = (NSInteger) i;
				break;
			}
		}
	}

	if (row_to_reload < 0) {
		return;
	}

	NSIndexSet *row_indexes = [NSIndexSet indexSetWithIndex:(NSUInteger) row_to_reload];
	NSIndexSet *column_indexes = [NSIndexSet indexSetWithIndex:0];
	[self.tableView reloadDataForRowIndexes:row_indexes columnIndexes:column_indexes];
}

#pragma mark - Table View

- (NSInteger) numberOfRowsInTableView:(NSTableView *)tableView
{
	return self.items.count;
}

- (NSTableRowView *) tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row
{
	MBSidebarRowView* row_view = [tableView makeViewWithIdentifier:InkwellSidebarRowIdentifier owner:self];
	if (row_view == nil) {
		row_view = [[MBSidebarRowView alloc] initWithFrame:NSZeroRect];
		row_view.identifier = InkwellSidebarRowIdentifier;
		row_view.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
	}

	[self configureRowView:row_view forRow:row tableView:tableView];
	return row_view;
}

- (NSView *) tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	#pragma unused(tableColumn)
	MBSidebarCell* cell_view = [tableView makeViewWithIdentifier:InkwellSidebarCellIdentifier owner:self];

	if (cell_view == nil) {
		cell_view = [[MBSidebarCell alloc] initWithFrame:NSZeroRect];
		cell_view.identifier = InkwellSidebarCellIdentifier;
	}

	MBEntry* item = self.items[(NSUInteger) row];
	MBRoundedImageView* avatar_view = cell_view.avatarView;
	NSTextField* title_field = cell_view.titleTextField;
	NSTextField* subtitle_field = cell_view.subtitleTextField;
	NSTextField* subscription_field = cell_view.subscriptionTextField;
	NSTextField* date_field = cell_view.dateTextField;
	NSTextField* bookmark_field = cell_view.bookmarkTextField;

	NSString* subtitle_value = item.summary ?: @"";
	NSString* date_value = [self displayDateStringForCurrentMode:item.date];

	NSString* raw_title_value = item.title ?: @"";
	BOOL has_post_title = (raw_title_value.length > 0);
	NSString* title_value = raw_title_value;
	if (!has_post_title) {
		title_value = item.subscriptionTitle ?: @"";
	}

	NSString* subscription_value = has_post_title ? (item.subscriptionTitle ?: @"") : @"";
	BOOL should_show_subtitle = (subtitle_value.length > 0);
	BOOL should_show_subscription = (subscription_value.length > 0);

	title_field.stringValue = title_value;
	subtitle_field.stringValue = subtitle_value;
	subtitle_field.hidden = !should_show_subtitle;
	subscription_field.stringValue = subscription_value;
	subscription_field.hidden = !should_show_subscription;
	date_field.stringValue = date_value;
	bookmark_field.hidden = !item.isBookmarked;
	bookmark_field.stringValue = item.isBookmarked ? @"★ Bookmarked" : @"";
	avatar_view.image = [self avatarImageForEntry:item];

	NSLayoutConstraint* subscription_top_with_subtitle_constraint = cell_view.subscriptionTopWithSubtitleConstraint;
	NSLayoutConstraint* subscription_top_without_subtitle_constraint = cell_view.subscriptionTopWithoutSubtitleConstraint;
	NSLayoutConstraint* date_top_with_subscription_constraint = cell_view.dateTopWithSubscriptionConstraint;
	NSLayoutConstraint* date_top_with_subtitle_constraint = cell_view.dateTopWithSubtitleConstraint;
	NSLayoutConstraint* date_top_without_secondary_text_constraint = cell_view.dateTopWithoutSecondaryTextConstraint;
	if (subscription_top_with_subtitle_constraint != nil && subscription_top_without_subtitle_constraint != nil && date_top_with_subscription_constraint != nil && date_top_with_subtitle_constraint != nil && date_top_without_secondary_text_constraint != nil) {
		subscription_top_with_subtitle_constraint.active = (should_show_subscription && should_show_subtitle);
		subscription_top_without_subtitle_constraint.active = (should_show_subscription && !should_show_subtitle);
		date_top_with_subscription_constraint.active = should_show_subscription;
		date_top_with_subtitle_constraint.active = (!should_show_subscription && should_show_subtitle);
		date_top_without_secondary_text_constraint.active = (!should_show_subscription && !should_show_subtitle);
	}

	BOOL is_selected_row = (row == self.selectedRowForStyling);
	if (!is_selected_row) {
		is_selected_row = (tableView.selectedRow == row);
	}
	if (!is_selected_row) {
		is_selected_row = [tableView isRowSelected:row];
	}
	NSColor* title_color = [NSColor labelColor];
	NSColor* subtitle_color = [NSColor secondaryLabelColor];
	NSColor* subscription_color = [NSColor secondaryLabelColor];
	NSColor* date_color = [NSColor tertiaryLabelColor];
	CGFloat avatar_alpha = 1.0;
	
	if (is_selected_row) {
		BOOL has_emphasized_selection = [self hasEmphasizedSelectionForTableView:tableView];
		NSColor* selected_text_color = [NSColor alternateSelectedControlTextColor];
		if (!has_emphasized_selection) {
			selected_text_color = [NSColor colorNamed:InkwellSelectedUnfocusedColorName];
			if (selected_text_color == nil) {
				selected_text_color = [NSColor darkGrayColor];
			}
		}
		title_color = selected_text_color;
		subtitle_color = [selected_text_color colorWithAlphaComponent:0.78];
		subscription_color = [selected_text_color colorWithAlphaComponent:0.78];
		date_color = [selected_text_color colorWithAlphaComponent:0.55];
	}
	else if (item.isRead && self.contentMode != MBSidebarContentModeBookmarks) {
		title_color = [NSColor disabledControlTextColor];
		subtitle_color = [NSColor disabledControlTextColor];
		subscription_color = [NSColor disabledControlTextColor];
		date_color = [NSColor disabledControlTextColor];
		avatar_alpha = 0.35;
	}

	title_field.textColor = title_color;
	subtitle_field.textColor = subtitle_color;
	subscription_field.textColor = subscription_color;
	date_field.textColor = date_color;
	bookmark_field.textColor = date_color;
	avatar_view.alphaValue = avatar_alpha;

	return cell_view;
}

- (CGFloat) tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
	if (row < 0 || row >= self.items.count) {
		return 54.0;
	}

	MBEntry *item = self.items[(NSUInteger) row];
	CGFloat content_width = MAX(120.0, tableView.bounds.size.width - (InkwellSidebarAvatarInset + InkwellSidebarAvatarSize + InkwellSidebarTextInset + InkwellSidebarRightInset));
	NSString *subtitle_value = item.summary ?: @"";
	NSString *date_value = [self displayDateStringForCurrentMode:item.date];
	NSFont *title_font = [NSFont systemFontOfSize:InkwellSidebarTitleFontSize weight:NSFontWeightSemibold];
	NSFont *subtitle_font = [NSFont systemFontOfSize:InkwellSidebarSubtitleFontSize];
	NSFont *date_font = [NSFont systemFontOfSize:InkwellSidebarDateFontSize];

	NSString* title_value = item.title ?: @"";
	BOOL has_post_title = (title_value.length > 0);
	if (!has_post_title) {
		title_value = item.subscriptionTitle ?: @"";
	}
	NSString* subscription_value = has_post_title ? (item.subscriptionTitle ?: @"") : @"";

	CGFloat title_height = [self heightForText:title_value font:title_font width:content_width maxLines:2];
	CGFloat subtitle_height = [self heightForText:subtitle_value font:subtitle_font width:content_width maxLines:2];
	CGFloat subscription_height = [self heightForText:subscription_value font:subtitle_font width:content_width maxLines:1];
	CGFloat date_height = [self heightForText:date_value font:date_font width:content_width maxLines:1];
	CGFloat row_height = 8.0 + title_height;
	if (subtitle_height > 0.0) {
		row_height += InkwellSidebarVerticalSpacing + subtitle_height;
	}
	if (subscription_height > 0.0) {
		row_height += InkwellSidebarVerticalSpacing + subscription_height;
	}
	row_height += InkwellSidebarVerticalSpacing + date_height + 8.0;

	return MAX(50.0, ceil(row_height));
}

- (CGFloat) heightForText:(NSString *)text font:(NSFont *)font width:(CGFloat)width maxLines:(NSInteger)max_lines
{
	if (text.length == 0 || font == nil) {
		return 0.0;
	}

	NSRect text_rect = [text boundingRectWithSize:NSMakeSize(width, CGFLOAT_MAX)
		options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
		attributes:@{ NSFontAttributeName: font }];
	CGFloat measured_height = ceil(NSHeight(text_rect));
	if (max_lines <= 0) {
		return measured_height;
	}

	CGFloat line_height = [self lineHeightForFont:font];
	CGFloat maximum_height = line_height * (CGFloat) max_lines;
	return MIN(measured_height, maximum_height);
}

- (CGFloat) lineHeightForFont:(NSFont *)font
{
	return ceil(font.ascender - font.descender + font.leading);
}

- (NSDate * _Nullable) dateValueFromEntry:(NSDictionary<NSString *, id> *)entry
{
	NSString* published_date_value = [self stringValueFromObject:entry[@"date_published"]];
	if (published_date_value.length > 0) {
		return [self dateFromISO8601String:published_date_value];
	}

	NSString *published_value = [self stringValueFromObject:entry[@"published"]];
	if (published_value.length > 0) {
		return [self dateFromISO8601String:published_value];
	}

	NSString *date_value = [self stringValueFromObject:entry[@"date"]];
	if (date_value.length > 0) {
		return [self dateFromISO8601String:date_value];
	}

	return nil;
}

- (NSDate * _Nullable) dateFromISO8601String:(NSString *)string
{
	static NSISO8601DateFormatter *fractional_date_formatter;
	static NSISO8601DateFormatter *default_date_formatter;
	static dispatch_once_t once_token;
	dispatch_once(&once_token, ^{
		fractional_date_formatter = [[NSISO8601DateFormatter alloc] init];
		fractional_date_formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;

		default_date_formatter = [[NSISO8601DateFormatter alloc] init];
		default_date_formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
	});

	NSDate *date_value = [fractional_date_formatter dateFromString:string];
	if (date_value == nil) {
		return [default_date_formatter dateFromString:string];
	}
	return date_value;
}

- (BOOL) boolValueFromObject:(id)object
{
	if ([object isKindOfClass:[NSNumber class]]) {
		return [(NSNumber *) object boolValue];
	}

	if ([object isKindOfClass:[NSString class]]) {
		NSString *string_value = [(NSString *) object lowercaseString];
		return [string_value isEqualToString:@"1"] || [string_value isEqualToString:@"true"] || [string_value isEqualToString:@"yes"];
	}

	return NO;
}

- (NSString*) bookmarksDisplayDateString:(NSDate* _Nullable) date
{
	if (date == nil) {
		return @"";
	}

	NSCalendar* calendar = [NSCalendar currentCalendar];
	if ([calendar isDateInToday:date]) {
		static NSDateFormatter* today_time_formatter;
		static dispatch_once_t once_token;
		dispatch_once(&once_token, ^{
			today_time_formatter = [[NSDateFormatter alloc] init];
			today_time_formatter.dateStyle = NSDateFormatterNoStyle;
			today_time_formatter.timeStyle = NSDateFormatterShortStyle;
		});

		return [today_time_formatter stringFromDate:date];
	}

	return [self displayDateString:date];
}

- (NSString*) allPostsDisplayDateString:(NSDate* _Nullable) date
{
	if (date == nil) {
		return @"";
	}

	static NSDateFormatter* month_day_formatter;
	static NSDateFormatter* time_formatter;
	static dispatch_once_t once_token;
	dispatch_once(&once_token, ^{
		month_day_formatter = [[NSDateFormatter alloc] init];
		[month_day_formatter setLocalizedDateFormatFromTemplate:@"MMM d"];

		time_formatter = [[NSDateFormatter alloc] init];
		time_formatter.dateStyle = NSDateFormatterNoStyle;
		time_formatter.timeStyle = NSDateFormatterShortStyle;
	});

	NSString* date_part = [month_day_formatter stringFromDate:date];
	NSString* time_part = [time_formatter stringFromDate:date];
	if (date_part.length == 0) {
		return time_part ?: @"";
	}
	if (time_part.length == 0) {
		return date_part;
	}

	return [NSString stringWithFormat:@"%@, %@", date_part, time_part];
}

- (NSString*) displayDateStringForCurrentMode:(NSDate* _Nullable) date
{
	if (self.contentMode == MBSidebarContentModeBookmarks) {
		return [self bookmarksDisplayDateString:date];
	}
	if (self.contentMode == MBSidebarContentModeAllPosts) {
		return [self allPostsDisplayDateString:date];
	}

	return [self displayDateString:date];
}

- (NSString *) displayDateString:(NSDate * _Nullable)date
{
	if (date == nil) {
		return @"";
	}

	static NSDateFormatter* today_time_formatter;
	static NSDateFormatter* month_day_formatter;
	static NSDateFormatter* secondary_time_formatter;
	static dispatch_once_t once_token;
	dispatch_once(&once_token, ^{
		today_time_formatter = [[NSDateFormatter alloc] init];
		today_time_formatter.dateStyle = NSDateFormatterNoStyle;
		today_time_formatter.timeStyle = NSDateFormatterShortStyle;

		month_day_formatter = [[NSDateFormatter alloc] init];
		[month_day_formatter setLocalizedDateFormatFromTemplate:@"MMM d"];

		secondary_time_formatter = [[NSDateFormatter alloc] init];
		secondary_time_formatter.dateStyle = NSDateFormatterNoStyle;
		secondary_time_formatter.timeStyle = NSDateFormatterShortStyle;
	});

	if (self.dateFilter == MBSidebarDateFilterToday) {
		return [today_time_formatter stringFromDate:date];
	}

	NSString* date_part = [month_day_formatter stringFromDate:date];
	NSString* time_part = [secondary_time_formatter stringFromDate:date];
	if (date_part.length == 0) {
		return time_part ?: @"";
	}
	if (time_part.length == 0) {
		return date_part;
	}

	return [NSString stringWithFormat:@"%@, %@", date_part, time_part];
}

- (NSString *) normalizedPreviewString:(NSString *)string
{
	if (string.length == 0) {
		return @"";
	}

	NSArray<NSString *> *parts = [string componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSMutableArray<NSString *> *tokens = [NSMutableArray array];
	for (NSString *part in parts) {
		if (part.length > 0) {
			[tokens addObject:part];
		}
	}

	return [tokens componentsJoinedByString:@" "];
}

- (NSString*) normalizedContentHTMLString:(NSString*) string
{
	NSString* trimmed_string = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if ([trimmed_string isEqualToString:@"<p></p>"]) {
		return @"";
	}

	return trimmed_string;
}

- (void) startObservingWindowKeyState
{
	NSWindow* window = self.view.window;
	if (window == nil) {
		return;
	}

	if (self.observedWindowForSelectionStyling == window) {
		return;
	}

	[self stopObservingWindowKeyState];
	self.observedWindowForSelectionStyling = window;

	NSNotificationCenter* notification_center = [NSNotificationCenter defaultCenter];
	[notification_center addObserver:self selector:@selector(windowKeyStateDidChange:) name:NSWindowDidBecomeKeyNotification object:window];
	[notification_center addObserver:self selector:@selector(windowKeyStateDidChange:) name:NSWindowDidResignKeyNotification object:window];
}

- (void) stopObservingWindowKeyState
{
	NSWindow* observed_window = self.observedWindowForSelectionStyling;
	if (observed_window == nil) {
		return;
	}

	NSNotificationCenter* notification_center = [NSNotificationCenter defaultCenter];
	[notification_center removeObserver:self name:NSWindowDidBecomeKeyNotification object:observed_window];
	[notification_center removeObserver:self name:NSWindowDidResignKeyNotification object:observed_window];
	self.observedWindowForSelectionStyling = nil;
}

- (void) windowKeyStateDidChange:(NSNotification*) notification
{
	#pragma unused(notification)
	NSInteger selected_row = self.tableView.selectedRow;
	[self refreshSelectionStylingForSelectedRow:selected_row];
}

- (BOOL) hasEmphasizedSelectionForTableView:(NSTableView*) table_view
{
	NSWindow* window = table_view.window;
	if (window == nil || !window.isKeyWindow) {
		return NO;
	}

	NSResponder* first_responder = window.firstResponder;
	if (first_responder == table_view) {
		return YES;
	}

	if (![first_responder isKindOfClass:[NSView class]]) {
		return NO;
	}

	NSView* first_responder_view = (NSView*) first_responder;
	if ([first_responder_view isDescendantOf:table_view]) {
		return YES;
	}

	return NO;
}

- (void) tableViewSelectionDidChange:(NSNotification *)notification
{
	#pragma unused(notification)
	NSInteger current_selected_row = self.tableView.selectedRow;
	if (self.isPreservingSelectionDuringReload) {
		self.selectedRowForStyling = current_selected_row;
		return;
	}

	[self refreshSelectionStylingForSelectedRow:current_selected_row];
	if (self.suppressSelectionChangedHandler) {
		self.suppressSelectionChangedHandler = NO;
		return;
	}

	[self saveSelectedEntryIDForCurrentSelection];
	[self notifySelectionChanged];
}

- (void) tableViewSelectionIsChanging:(NSNotification *)notification
{
	#pragma unused(notification)
	NSInteger current_selected_row = self.tableView.selectedRow;
	if (self.isPreservingSelectionDuringReload) {
		self.selectedRowForStyling = current_selected_row;
		return;
	}

	[self refreshSelectionStylingForSelectedRow:current_selected_row];
}

- (void) refreshSelectionStylingForSelectedRow:(NSInteger) selected_row
{
	NSMutableIndexSet *rows_to_reload = [NSMutableIndexSet indexSet];
	if (self.selectedRowForStyling >= 0 && self.selectedRowForStyling < self.items.count) {
		[rows_to_reload addIndex:(NSUInteger) self.selectedRowForStyling];
	}
	if (selected_row >= 0 && selected_row < self.items.count) {
		[rows_to_reload addIndex:(NSUInteger) selected_row];
	}

	self.selectedRowForStyling = selected_row;

	if (rows_to_reload.count > 0) {
		[rows_to_reload enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
			#pragma unused(stop)
			MBSidebarRowView* row_view = (MBSidebarRowView*) [self.tableView rowViewAtRow:(NSInteger) idx makeIfNecessary:NO];
			[self configureRowView:row_view forRow:(NSInteger) idx tableView:self.tableView];
		}];

		NSIndexSet *column_indexes = [NSIndexSet indexSetWithIndex:0];
		[self.tableView reloadDataForRowIndexes:rows_to_reload columnIndexes:column_indexes];
	}
}

@end
