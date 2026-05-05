//
//  MBMainController.m
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import "MBMainController.h"
#import "MBClient.h"
#import "MBConversationController.h"
#import "MBDetailController.h"
#import "MBEntry.h"
#import "MBHighlight.h"
#import "MBHighlightsController.h"
#import "MBNewFeedChoice.h"
#import "MBNewFeedChoiceCellView.h"
#import "MBNewPostController.h"
#import "MBPreferencesController.h"
#import "MBSidebarController.h"
#import "MBSubscription.h"

static NSToolbarItemIdentifier const InkwellToolbarFilterItemIdentifier = @"InkwellToolbarFilter";
static NSToolbarItemIdentifier const InkwellToolbarSearchItemIdentifier = @"InkwellToolbarSearch";
static NSToolbarItemIdentifier const InkwellToolbarHighlightItemIdentifier = @"InkwellToolbarHighlight";
static NSToolbarItemIdentifier const InkwellToolbarRepliesItemIdentifier = @"InkwellToolbarReplies";
static NSToolbarItemIdentifier const InkwellToolbarNewPostItemIdentifier = @"InkwellToolbarNewPost";
static NSToolbarItemIdentifier const InkwellToolbarProgressItemIdentifier = @"InkwellToolbarProgress";
static NSInteger const InkwellFilterTodaySegmentIndex = 0;
static NSInteger const InkwellFilterRecentSegmentIndex = 1;
static NSInteger const InkwellFilterFadingSegmentIndex = 2;
static CGFloat const InkwellSidebarPaneWidth = 310.0;
static CGFloat const InkwellMainWindowDefaultWidth = 1100.0;
static CGFloat const InkwellMainWindowDefaultHeight = 760.0;
static CGFloat const InkwellMainWindowMinWidth = 760.0;
static CGFloat const InkwellMainWindowMinHeight = 520.0;
static NSString* const InkwellMainWindowAutosaveName = @"InkwellWindow";
static NSString* const InkwellMainSplitViewAutosaveName = @"InkwellSplit";
static NSString* const InkwellNewFeedChoiceCellIdentifier = @"InkwellNewFeedChoiceCell";
static CGFloat const InkwellNewFeedSheetWidth = 460.0;
static CGFloat const InkwellNewFeedSheetCollapsedHeight = 152.0;
static CGFloat const InkwellNewFeedSheetExpandedHeight = 350.0;
static CGFloat const InkwellNewFeedChoicesHeight = 186.0;
static CGFloat const InkwellNewFeedChoiceRowHeight = 46.0;
static NSTimeInterval const InkwellAutoRefreshInterval = 5.0 * 60.0;

@interface MBMainController () <NSToolbarDelegate, NSSearchFieldDelegate, NSMenuItemValidation, NSToolbarItemValidation, NSTableViewDataSource, NSTableViewDelegate>

@property (assign) BOOL didBuildInterface;
@property (assign) BOOL didRestoreWindowFrame;
@property (strong) MBClient *client;
@property (strong) NSSegmentedControl *filterSegmentedControl;
@property (strong) NSProgressIndicator *toolbarProgressIndicator;
@property (strong) NSSearchField *toolbarSearchField;
@property (strong) NSSplitView *mainSplitView;
@property (strong) MBSidebarController *sidebarController;
@property (strong) MBDetailController *detailController;
@property (strong) MBHighlightsController *highlightsController;
@property (strong) NSMutableArray* postControllers;
@property (strong) MBConversationController* conversationController;
@property (strong) MBPreferencesController* preferencesController;
@property (copy) NSString *token;
@property (assign) BOOL isNetworkingInProgress;
@property (assign) BOOL isSyncingHighlights;
@property (assign) BOOL isRefreshingMicropubDestinations;
@property (assign) NSInteger conversationReplyCount;
@property (copy) NSDictionary* lastConversationPayload;
@property (copy) NSString* pendingConversationLookupURLString;
@property (strong) NSButton* toolbarRepliesButton;
@property (strong) NSWindow* feedSubscriptionSheetWindow;
@property (strong) NSTextField* feedSubscriptionURLField;
@property (strong) NSButton* feedSubscriptionSubscribeButton;
@property (strong) NSButton* feedSubscriptionCancelButton;
@property (strong) NSProgressIndicator* feedSubscriptionProgressIndicator;
@property (strong) NSScrollView* feedSubscriptionChoicesScrollView;
@property (strong) NSTableView* feedSubscriptionChoicesTableView;
@property (strong) NSLayoutConstraint* feedSubscriptionChoicesHeightConstraint;
@property (copy) NSArray* feedSubscriptionChoices;
@property (copy) NSString* feedSubscriptionRequestedURLString;
@property (assign) BOOL isCreatingFeedSubscription;
@property (strong) NSTimer* autoRefreshTimer;
@property (strong) NSSharingServicePicker* sharingServicePicker;

- (BOOL) focusSidebarPane;
- (BOOL) focusDetailPane;
- (void) restoreWindowFrameIfNeeded;
- (void) setupNewFeedSheetIfNeeded;
- (void) resetNewFeedSheetState;
- (void) updateNewFeedChoicesWithDictionaries:(NSArray*) choices;
- (void) setNewFeedChoicesVisible:(BOOL) is_visible animated:(BOOL) is_animated;
- (void) resizeNewFeedSheetToContentHeight:(CGFloat) content_height animated:(BOOL) is_animated;
- (void) updateNewFeedControls;
- (NSString*) normalizedNewFeedURLString;
- (MBNewFeedChoice* _Nullable) selectedNewFeedChoice;
- (void) closeNewFeedSheetWithReturnCode:(NSModalResponse) return_code;
- (void) presentNewFeedError:(NSError*) error;
- (void) startAutoRefreshTimerIfNeeded;
- (void) stopAutoRefreshTimer;
- (void) autoRefreshTimerDidFire:(NSTimer*) timer;
- (BOOL) isFilterSelectionDisabled;
- (void) updateFilterSegmentedControlEnabledState;
- (BOOL) canCreateNewPost;
- (BOOL) canShareSelectedItem;
- (BOOL) canPrintCurrentContent;
- (BOOL) canHighlightSelectedItem;
- (BOOL) canReplyToConversation;
- (BOOL) canEditSelectedPost;
- (BOOL) canShowCurrentUserPosts;
- (NSArray*) sharingItemsForSelectedItem;
- (NSRect) sharingPickerRectInView:(NSView*) view;
- (MBSubscription * _Nullable) currentUserBlogSubscription;
- (NSDictionary * _Nullable) destinationWithUID:(NSString *)destinationUID destinations:(NSArray *)destinations;
- (MBSubscription * _Nullable) subscriptionMatchingDestinationUID:(NSString *)destinationUID destinationName:(NSString *)destinationName subscriptions:(NSArray *)subscriptions normalizeHosts:(BOOL)normalizeHosts;
- (BOOL) destinationUID:(NSString *)destinationUID destinationName:(NSString *)destinationName matchesSubscription:(MBSubscription *)subscription normalizeHosts:(BOOL)normalizeHosts;
- (NSString *) currentUsernameMenuTitle;
- (NSString *) hostFromURLString:(NSString *)string;
- (NSString *) normalizedHostFromURLString:(NSString *)string;
- (NSString *) normalizedHostString:(NSString *)hostString;
- (BOOL) host:(NSString *)host matchesDestinationHosts:(NSArray *)destinationHosts;
- (NSString*) markdownTextForNewPostWithItem:(MBEntry*) item selectionPayload:(NSDictionary* _Nullable) payload;
- (NSString*) markdownTextForNewPostWithItem:(MBEntry*) item selectionPayload:(NSDictionary* _Nullable) payload includeLinkWithoutSelection:(BOOL) include_link_without_selection;
- (NSString*) blockquoteMarkdownFromText:(NSString*) text_string;
- (void) openNewPostForMarkdownText:(NSString*) markdown_text;
- (void) openNewPostWindowForMarkdownText:(NSString *)markdownText destinations:(NSArray *)destinations;
- (void) openPostEditorForItem:(MBEntry *)item;
- (MBNewPostController *) configuredPostWindowController;
- (NSDictionary * _Nullable) defaultMicropubDestinationFromDestinations:(NSArray *)destinations;
- (void) openNewPostURLForMarkdownText:(NSString*) markdown_text;
- (void) refreshMicropubDestinationsInBackgroundIfNeeded;
- (void) refreshMicropubDestinationsInBackground;
- (void) scheduleMicropubDestinationsRefreshAfterOpeningNewPost;
- (void) postWindowControllerDidClose:(MBNewPostController*)controller;

@end

@implementation MBMainController

- (instancetype) initWithWindow:(nullable NSWindow *)window
{
	return [self initWithWindow:window client:nil token:nil];
}

- (instancetype) initWithWindow:(nullable NSWindow *)window client:(nullable MBClient *)client token:(nullable NSString *)token
{
	self = [super initWithWindow:window];
	if (self) {
		self.client = client;
		self.token = token ?: @"";

		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clientNetworkingDidStart:) name:MBClientNetworkingDidStartNotification object:self.client];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clientNetworkingDidStop:) name:MBClientNetworkingDidStopNotification object:self.client];
	}
	return self;
}

- (void) dealloc
{
	[self stopAutoRefreshTimer];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void) close
{
	[self stopAutoRefreshTimer];
	[self.preferencesController close];
	[self.conversationController close];
	[self.highlightsController close];
	for (MBNewPostController* controller in [self.postControllers copy]) {
		[controller close];
	}
	[super close];
}

- (void) showWindow:(id)sender
{
	[self buildInterfaceIfNeeded];
	[self startAutoRefreshTimerIfNeeded];
	[self restoreWindowFrameIfNeeded];
	[super showWindow:sender];
	[self.window makeKeyAndOrderFront:sender];
}

- (void) buildInterfaceIfNeeded
{
	[self setupWindowIfNeeded];

	if (self.didBuildInterface) {
		return;
	}

	[self buildContentSplitView];
	[self buildToolbar];
	[self startAutoRefreshTimerIfNeeded];

	self.didBuildInterface = YES;
}

- (void) setupWindowIfNeeded
{
	if (self.window == nil) {
		NSRect frame = NSMakeRect(0, 0, InkwellMainWindowDefaultWidth, InkwellMainWindowDefaultHeight);
		NSUInteger style_mask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
		NSWindow* window = [[NSWindow alloc] initWithContentRect:frame styleMask:style_mask backing:NSBackingStoreBuffered defer:NO];
		window.releasedWhenClosed = NO;
		window.minSize = NSMakeSize(InkwellMainWindowMinWidth, InkwellMainWindowMinHeight);
		self.window = window;
	}

	self.window.title = @"Inkwell";
	self.window.styleMask |= NSWindowStyleMaskFullSizeContentView;
	self.window.titlebarAppearsTransparent = YES;
	self.window.titleVisibility = NSWindowTitleHidden;
	self.window.toolbarStyle = NSWindowToolbarStyleUnified;
}

- (void) restoreWindowFrameIfNeeded
{
	if (self.didRestoreWindowFrame || self.window == nil) {
		return;
	}

	BOOL did_restore_frame = [self.window setFrameUsingName:InkwellMainWindowAutosaveName];
	[self.window setFrameAutosaveName:InkwellMainWindowAutosaveName];
	if (!did_restore_frame) {
		[self.window center];
	}

	self.didRestoreWindowFrame = YES;
}

- (void) startAutoRefreshTimerIfNeeded
{
	if (self.autoRefreshTimer != nil) {
		return;
	}

	NSTimer* timer = [NSTimer timerWithTimeInterval:InkwellAutoRefreshInterval target:self selector:@selector(autoRefreshTimerDidFire:) userInfo:nil repeats:YES];
	[[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
	self.autoRefreshTimer = timer;
}

- (void) stopAutoRefreshTimer
{
	[self.autoRefreshTimer invalidate];
	self.autoRefreshTimer = nil;
}

- (void) autoRefreshTimerDidFire:(NSTimer*) timer
{
	#pragma unused(timer)
	[self.sidebarController refreshData];
}

- (void) buildToolbar
{
	NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"InkwellMainToolbar"];
	toolbar.delegate = self;
	toolbar.allowsUserCustomization = NO;
	toolbar.autosavesConfiguration = NO;
	toolbar.displayMode = NSToolbarDisplayModeIconOnly;

	self.window.toolbar = toolbar;
	self.window.toolbarStyle = NSWindowToolbarStyleUnified;
	[self refreshRepliesToolbarItemVisibility];
}

- (void) buildContentSplitView
{
	self.sidebarController = [[MBSidebarController alloc] init];
	self.detailController = [[MBDetailController alloc] init];
	self.detailController.client = self.client;
	self.detailController.token = self.token ?: @"";

	__weak typeof(self) weak_self = self;
	self.sidebarController.selectionChangedHandler = ^(MBEntry * _Nullable item) {
		[weak_self.detailController showSidebarItem:item];
		[weak_self.highlightsController updateForSelectedEntry:item];
		[weak_self updateConversationForSelectedItem:item];
		[weak_self.window.toolbar validateVisibleItems];
	};
	self.sidebarController.focusDetailHandler = ^BOOL {
		MBMainController* strong_self = weak_self;
		if (strong_self == nil) {
			return NO;
		}

		return [strong_self focusDetailPane];
	};
	self.sidebarController.syncCompletedHandler = ^{
		MBMainController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		MBEntry* selected_item = [strong_self.sidebarController selectedItem];
		if (selected_item != nil && strong_self.detailController.displayedEntryID <= 0 && !strong_self.detailController.isShowingReadingRecap) {
			[strong_self.detailController showSidebarItem:selected_item];
			[strong_self.highlightsController updateForSelectedEntry:selected_item];
			[strong_self updateConversationForSelectedItem:selected_item];
		}

		[strong_self syncHighlightsFromServer];
		[strong_self refreshMicropubDestinationsInBackgroundIfNeeded];
	};
	self.sidebarController.specialModeChangedHandler = ^(BOOL is_showing_special_mode) {
		#pragma unused(is_showing_special_mode)
		[weak_self updateFilterSegmentedControlEnabledState];
	};
	self.detailController.selectionChangedHandler = ^(BOOL has_selection) {
		#pragma unused(has_selection)
		[weak_self.window.toolbar validateVisibleItems];
	};
	self.detailController.focusSidebarHandler = ^BOOL {
		MBMainController* strong_self = weak_self;
		if (strong_self == nil) {
			return NO;
		}

		return [strong_self focusSidebarPane];
	};
	self.detailController.highlightsProvider = ^NSArray* (NSInteger entry_id) {
		return [weak_self.client cachedHighlightsForEntryID:entry_id];
	};
	self.detailController.highlightDeletedHandler = ^(MBHighlight* highlight) {
		#pragma unused(highlight)
		MBMainController* strong_self = weak_self;
		if (strong_self == nil || strong_self.highlightsController == nil) {
			return;
		}

		[strong_self.highlightsController reloadHighlights];
	};
	self.sidebarController.readingRecapHandler = ^(NSString* html) {
		[weak_self.detailController showReadingRecapHTML:html];
	};
	self.sidebarController.client = self.client;
	self.sidebarController.token = self.token;

	NSSplitViewController *split_view_controller = [[NSSplitViewController alloc] init];

	NSSplitViewItem *sidebar_item = [NSSplitViewItem sidebarWithViewController:self.sidebarController];
	sidebar_item.minimumThickness = InkwellSidebarPaneWidth;
	sidebar_item.maximumThickness = 520.0;
	sidebar_item.canCollapse = NO;
	sidebar_item.holdingPriority = 260.0;
	sidebar_item.allowsFullHeightLayout = YES;

	NSSplitViewItem *detail_item = [NSSplitViewItem splitViewItemWithViewController:self.detailController];
	detail_item.minimumThickness = 420.0;
	detail_item.canCollapse = NO;
	detail_item.allowsFullHeightLayout = YES;

	[split_view_controller addSplitViewItem:sidebar_item];
	[split_view_controller addSplitViewItem:detail_item];
	split_view_controller.splitView.dividerStyle = NSSplitViewDividerStyleThin;
	split_view_controller.splitView.autosaveName = InkwellMainSplitViewAutosaveName;
	[split_view_controller.splitView setPosition:InkwellSidebarPaneWidth ofDividerAtIndex:0];
	self.mainSplitView = split_view_controller.splitView;

	self.window.contentViewController = split_view_controller;
	[self.sidebarController loadCachedRecentEntries];
	[self.sidebarController reloadData];
}

- (BOOL) focusSidebarPane
{
	if (self.sidebarController == nil) {
		return NO;
	}

	return [self.sidebarController focusSidebar];
}

- (BOOL) focusDetailPane
{
	if (self.detailController == nil) {
		return NO;
	}

	return [self.detailController focusDetailPane];
}

- (void) clientNetworkingDidStart:(NSNotification *)notification
{
	#pragma unused(notification)
	self.isNetworkingInProgress = YES;
	[self updateToolbarProgressIndicator];
}

- (void) clientNetworkingDidStop:(NSNotification *)notification
{
	#pragma unused(notification)
	self.isNetworkingInProgress = NO;
	[self updateToolbarProgressIndicator];
}

- (void) updateToolbarProgressIndicator
{
	if (self.toolbarProgressIndicator == nil) {
		return;
	}

	if (self.isNetworkingInProgress) {
		self.toolbarProgressIndicator.hidden = NO;
		[self.toolbarProgressIndicator startAnimation:nil];
	}
	else {
		[self.toolbarProgressIndicator stopAnimation:nil];
		self.toolbarProgressIndicator.hidden = YES;
	}
}

- (MBSidebarDateFilter) sidebarDateFilterForSegmentIndex:(NSInteger)segment_index
{
	switch (segment_index) {
		case InkwellFilterRecentSegmentIndex:
			return MBSidebarDateFilterRecent;

		case InkwellFilterFadingSegmentIndex:
			return MBSidebarDateFilterFading;

		case InkwellFilterTodaySegmentIndex:
		default:
			return MBSidebarDateFilterToday;
	}
}

- (void) selectFilterSegment:(NSInteger)segment_index
{
	if (segment_index < InkwellFilterTodaySegmentIndex || segment_index > InkwellFilterFadingSegmentIndex) {
		return;
	}

	[self.sidebarController clearSpecialMode];
	self.sidebarController.dateFilter = [self sidebarDateFilterForSegmentIndex:segment_index];

	if (self.filterSegmentedControl == nil) {
		return;
	}

	if (segment_index >= self.filterSegmentedControl.segmentCount) {
		return;
	}

	self.filterSegmentedControl.selectedSegment = segment_index;
}

- (void) updateFilterSegmentedControlEnabledState
{
	if (self.filterSegmentedControl == nil) {
		return;
	}

	self.filterSegmentedControl.enabled = ![self isFilterSelectionDisabled];
}

- (BOOL) isFilterSelectionDisabled
{
	return ([self.sidebarController isShowingSpecialMode] || self.sidebarController.searchQuery.length > 0);
}

- (IBAction) filterSegmentChanged:(id)sender
{
	#pragma unused(sender)

	if ([self isFilterSelectionDisabled]) {
		return;
	}

	[self selectFilterSegment:self.filterSegmentedControl.selectedSegment];
}

- (IBAction) selectTodayView:(id)sender
{
	#pragma unused(sender)

	if ([self isFilterSelectionDisabled]) {
		return;
	}

	[self selectFilterSegment:InkwellFilterTodaySegmentIndex];
}

- (IBAction) selectRecentView:(id)sender
{
	#pragma unused(sender)

	if ([self isFilterSelectionDisabled]) {
		return;
	}

	[self selectFilterSegment:InkwellFilterRecentSegmentIndex];
}

- (IBAction) selectFadingView:(id)sender
{
	#pragma unused(sender)

	if ([self isFilterSelectionDisabled]) {
		return;
	}

	[self selectFilterSegment:InkwellFilterFadingSegmentIndex];
}

- (IBAction) sortNewestAtTop:(id)sender
{
	#pragma unused(sender)
	self.sidebarController.sortOrder = MBSidebarSortOrderNewestFirst;
}

- (IBAction) sortOldestAtTop:(id)sender
{
	#pragma unused(sender)
	self.sidebarController.sortOrder = MBSidebarSortOrderOldestFirst;
}

- (IBAction) showReadingRecap:(id)sender
{
	[self.sidebarController showReadingRecap:sender];
}

- (IBAction) showMentions:(id)sender
{
	#pragma unused(sender)

	if (self.toolbarSearchField != nil && self.toolbarSearchField.stringValue.length > 0) {
		self.toolbarSearchField.stringValue = @"";
	}
	self.sidebarController.searchQuery = @"";
	[self.sidebarController showMentions];
	[self updateFilterSegmentedControlEnabledState];
}

- (IBAction) showBookmarks:(id)sender
{
	#pragma unused(sender)

	if (self.toolbarSearchField != nil && self.toolbarSearchField.stringValue.length > 0) {
		self.toolbarSearchField.stringValue = @"";
	}
	self.sidebarController.searchQuery = @"";
	[self.sidebarController showBookmarks];
	[self updateFilterSegmentedControlEnabledState];
}

- (IBAction) showAllPosts:(id)sender
{
	#pragma unused(sender)

	if (self.toolbarSearchField != nil && self.toolbarSearchField.stringValue.length > 0) {
		self.toolbarSearchField.stringValue = @"";
	}
	self.sidebarController.searchQuery = @"";
	[self.sidebarController showAllPostsForSelectedSite];
	[self updateFilterSegmentedControlEnabledState];
}

- (IBAction) showCurrentUserPosts:(id)sender
{
	#pragma unused(sender)

	MBSubscription* subscription = [self currentUserBlogSubscription];
	if (subscription == nil || subscription.feedID <= 0) {
		return;
	}

	if (self.toolbarSearchField != nil && self.toolbarSearchField.stringValue.length > 0) {
		self.toolbarSearchField.stringValue = @"";
	}

	NSString* site_name = [subscription.title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	NSString* feed_host = [self normalizedHostFromURLString:subscription.siteURL ?: @""];
	if (feed_host.length == 0) {
		feed_host = [self normalizedHostFromURLString:subscription.feedURL ?: @""];
	}
	if (site_name.length == 0) {
		site_name = feed_host;
	}

	self.sidebarController.searchQuery = @"";
	[self.sidebarController showAllPostsForFeedID:subscription.feedID siteName:site_name feedHost:feed_host];
	[self updateFilterSegmentedControlEnabledState];
}

- (IBAction) refreshView:(id)sender
{
	#pragma unused(sender)
	[self.sidebarController refreshData];
}

- (IBAction) showHighlights:(id)sender
{
	#pragma unused(sender)

	if (self.highlightsController == nil) {
		self.highlightsController = [[MBHighlightsController alloc] initWithClient:self.client token:self.token];
		__weak typeof(self) weak_self = self;
		self.highlightsController.highlightDeletedHandler = ^(MBHighlight* highlight) {
			MBMainController* strong_self = weak_self;
			if (strong_self == nil || ![highlight isKindOfClass:[MBHighlight class]]) {
				return;
			}

			MBEntry* selected_item = [strong_self.sidebarController selectedItem];
			if (selected_item != nil && selected_item.entryID == highlight.entryID) {
				[strong_self.detailController refreshHighlights];
			}
		};
		self.highlightsController.postWindowHandler = ^(NSString* markdown_text) {
			MBMainController* strong_self = weak_self;
			if (strong_self == nil) {
				return;
			}

			[strong_self openNewPostForMarkdownText:markdown_text];
		};
	}

	MBEntry* selected_item = [self.sidebarController selectedItem];
	[self.highlightsController showHighlightsForEntry:selected_item];
}

- (IBAction) openPostWindow:(id)sender
{
	BOOL include_link_without_selection = NO;
	if ([sender isKindOfClass:[NSMenuItem class]]) {
		NSMenuItem* menu_item = (NSMenuItem*) sender;
		include_link_without_selection = [menu_item.title isEqualToString:@"New Post..."];
	}

	MBEntry* selected_item = [self.sidebarController selectedItem];
	if (selected_item == nil) {
		[self openNewPostForMarkdownText:@""];
		return;
	}

	__weak typeof(self) weak_self = self;
	[self.detailController requestSelectionHighlightPayloadWithCompletion:^(NSDictionary* _Nullable payload) {
		MBMainController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		NSString* markdown_text = [strong_self markdownTextForNewPostWithItem:selected_item selectionPayload:payload includeLinkWithoutSelection:include_link_without_selection];
		[strong_self openNewPostForMarkdownText:markdown_text];
	}];
}

- (IBAction) editPost:(id)sender
{
	#pragma unused(sender)

	if (![self canEditSelectedPost]) {
		return;
	}

	MBEntry* selected_item = [self.sidebarController selectedItem];
	[self openPostEditorForItem:selected_item];
}

- (IBAction) newFeed:(id) sender
{
	#pragma unused(sender)

	if (self.window == nil) {
		return;
	}

	[self setupNewFeedSheetIfNeeded];
	if (self.window.attachedSheet == self.feedSubscriptionSheetWindow) {
		[self.feedSubscriptionURLField selectText:nil];
		return;
	}

	[self resetNewFeedSheetState];

	__weak typeof(self) weak_self = self;
	[self.window beginSheet:self.feedSubscriptionSheetWindow completionHandler:^(NSModalResponse return_code) {
		MBMainController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		BOOL did_add_feed = (return_code == NSModalResponseOK);
		[strong_self.feedSubscriptionSheetWindow orderOut:nil];
		[strong_self resetNewFeedSheetState];
		if (did_add_feed) {
			[strong_self.sidebarController refreshData];
		}
	}];
	[self.feedSubscriptionSheetWindow makeFirstResponder:self.feedSubscriptionURLField];
	[self.feedSubscriptionURLField selectText:nil];
}

- (IBAction) cancelNewFeed:(id) sender
{
	#pragma unused(sender)
	if (self.isCreatingFeedSubscription) {
		return;
	}

	[self closeNewFeedSheetWithReturnCode:NSModalResponseCancel];
}

- (IBAction) subscribeNewFeed:(id) sender
{
	#pragma unused(sender)

	if (self.client == nil || self.token.length == 0 || self.isCreatingFeedSubscription) {
		return;
	}

	NSString* url_string = @"";
	MBNewFeedChoice* selected_choice = [self selectedNewFeedChoice];
	if (selected_choice != nil && self.feedSubscriptionChoices.count > 0) {
		url_string = selected_choice.feedURL ?: @"";
	}
	else {
		url_string = [self normalizedNewFeedURLString];
	}

	NSString* trimmed_url_string = [url_string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (trimmed_url_string.length == 0) {
		NSBeep();
		return;
	}

	self.isCreatingFeedSubscription = YES;
	self.feedSubscriptionRequestedURLString = trimmed_url_string;
	[self updateNewFeedControls];

	__weak typeof(self) weak_self = self;
	[self.client createFeedSubscriptionWithURLString:trimmed_url_string token:self.token completion:^(NSInteger status_code, MBSubscription* _Nullable subscription, NSArray* _Nullable choices, NSError* _Nullable error) {
		#pragma unused(subscription)
		MBMainController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		strong_self.isCreatingFeedSubscription = NO;

		if (error != nil) {
			[strong_self updateNewFeedControls];
			[strong_self presentNewFeedError:error];
			return;
		}

		if (status_code == 300) {
			[strong_self updateNewFeedChoicesWithDictionaries:choices ?: @[]];
			[strong_self updateNewFeedControls];
			return;
		}

		[strong_self.client invalidateFeedIconsCache];
		[strong_self closeNewFeedSheetWithReturnCode:NSModalResponseOK];
	}];
}

- (IBAction) copyLink:(id)sender
{
	#pragma unused(sender)

	MBEntry* selected_item = [self.sidebarController selectedItem];
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

- (IBAction) share:(id) sender
{
	#pragma unused(sender)

	if (![self canShareSelectedItem] || self.window.contentView == nil) {
		return;
	}

	NSArray* sharing_items = [self sharingItemsForSelectedItem];
	if (sharing_items.count == 0) {
		return;
	}

	NSView* content_view = self.window.contentView;
	self.sharingServicePicker = [[NSSharingServicePicker alloc] initWithItems:sharing_items];
	[self.sharingServicePicker showRelativeToRect:[self sharingPickerRectInView:content_view] ofView:content_view preferredEdge:NSMaxYEdge];
}

- (IBAction) printDetail:(id) sender
{
	#pragma unused(sender)

	if (![self canPrintCurrentContent] || self.window == nil) {
		return;
	}

	[self.detailController printCurrentContentForWindow:self.window];
}

- (void) updateConversationForSelectedItem:(MBEntry* _Nullable) selected_item
{
	self.pendingConversationLookupURLString = @"";
	self.conversationReplyCount = 0;
	self.lastConversationPayload = @{};
	[self refreshRepliesToolbarItemVisibility];
	[self.conversationController updateWithConversationPayload:nil];
	[self.conversationController updateForSelectedEntry:selected_item];

	if (selected_item == nil || self.client == nil) {
		return;
	}

	NSString* selected_url_string = [selected_item.url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (selected_url_string.length == 0) {
		return;
	}

	self.pendingConversationLookupURLString = selected_url_string;

	__weak typeof(self) weak_self = self;
	[self.client fetchConversationForURLString:selected_url_string completion:^(NSDictionary* _Nullable conversation_payload, NSError* _Nullable error) {
		#pragma unused(error)
		MBMainController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		NSString* pending_url_string = strong_self.pendingConversationLookupURLString ?: @"";
		if (![pending_url_string isEqualToString:selected_url_string]) {
			return;
		}
		strong_self.pendingConversationLookupURLString = @"";
		[strong_self applyConversationPayload:conversation_payload];
	}];
}

- (void) applyConversationPayload:(NSDictionary* _Nullable) conversation_payload
{
	if (![conversation_payload isKindOfClass:[NSDictionary class]]) {
		self.conversationReplyCount = 0;
		self.lastConversationPayload = @{};
		[self refreshRepliesToolbarItemVisibility];
		[self.conversationController updateWithConversationPayload:nil];
		return;
	}

	self.lastConversationPayload = [conversation_payload copy];
	NSArray* conversation_items = [self conversationItemsFromPayload:self.lastConversationPayload];
	self.conversationReplyCount = conversation_items.count;
	[self refreshRepliesToolbarItemVisibility];
	[self.conversationController updateWithConversationPayload:self.lastConversationPayload];
}

- (NSArray*) conversationItemsFromPayload:(NSDictionary*) conversation_payload
{
	id items_object = conversation_payload[@"items"];
	if (![items_object isKindOfClass:[NSArray class]]) {
		return @[];
	}

	return [items_object copy];
}

- (NSString*) repliesToolbarTitle
{
	if (self.conversationReplyCount == 1) {
		return @"1 reply";
	}

	return [NSString stringWithFormat:@"%ld replies", (long) self.conversationReplyCount];
}

- (NSImage* _Nullable) repliesToolbarSymbolImage
{
	NSImage* symbol_image = [NSImage imageWithSystemSymbolName:@"bubble.left.and.bubble.right" accessibilityDescription:@"Replies"];
	if (symbol_image == nil) {
		return nil;
	}

	NSImageSymbolConfiguration* symbol_config = [NSImageSymbolConfiguration configurationWithPointSize:12.0 weight:NSFontWeightRegular scale:NSImageSymbolScaleSmall];
	NSImage* configured_image = [symbol_image imageWithSymbolConfiguration:symbol_config];
	return configured_image ?: symbol_image;
}

- (void) refreshRepliesToolbarItemVisibility
{
	NSToolbar* toolbar = self.window.toolbar;
	if (toolbar == nil) {
		return;
	}

	BOOL should_show_item = (self.conversationReplyCount > 0);
	NSInteger item_index = [self indexOfToolbarItemWithIdentifier:InkwellToolbarRepliesItemIdentifier inToolbar:toolbar];
	if (!should_show_item) {
		if (item_index != NSNotFound) {
			[toolbar removeItemAtIndex:item_index];
		}
		self.toolbarRepliesButton = nil;
		[toolbar validateVisibleItems];
		return;
	}

	if (item_index == NSNotFound) {
		NSInteger insertion_index = [self insertionIndexForRepliesItemInToolbar:toolbar];
		[toolbar insertItemWithItemIdentifier:InkwellToolbarRepliesItemIdentifier atIndex:insertion_index];
	}

	[self updateRepliesToolbarPresentation];
	[toolbar validateVisibleItems];
}

- (NSInteger) insertionIndexForRepliesItemInToolbar:(NSToolbar*) toolbar
{
	NSInteger search_index = [self indexOfToolbarItemWithIdentifier:InkwellToolbarSearchItemIdentifier inToolbar:toolbar];
	if (search_index != NSNotFound) {
		return search_index;
	}

	NSInteger highlight_index = [self indexOfToolbarItemWithIdentifier:InkwellToolbarHighlightItemIdentifier inToolbar:toolbar];
	if (highlight_index != NSNotFound) {
		return highlight_index;
	}

	return toolbar.items.count;
}

- (NSInteger) indexOfToolbarItemWithIdentifier:(NSToolbarItemIdentifier) item_identifier inToolbar:(NSToolbar*) toolbar
{
	NSInteger current_index = 0;
	for (NSToolbarItem* item in toolbar.items) {
		if ([item.itemIdentifier isEqualToString:item_identifier]) {
			return current_index;
		}
		current_index += 1;
	}

	return NSNotFound;
}

- (NSToolbarItem* _Nullable) toolbarItemWithIdentifier:(NSToolbarItemIdentifier) item_identifier inToolbar:(NSToolbar*) toolbar
{
	for (NSToolbarItem* item in toolbar.items) {
		if ([item.itemIdentifier isEqualToString:item_identifier]) {
			return item;
		}
	}

	return nil;
}

- (void) updateRepliesToolbarPresentation
{
	NSToolbar* toolbar = self.window.toolbar;
	if (toolbar == nil) {
		return;
	}

	NSToolbarItem* replies_item = [self toolbarItemWithIdentifier:InkwellToolbarRepliesItemIdentifier inToolbar:toolbar];
	if (replies_item == nil) {
		return;
	}

	NSString* title_string = [self repliesToolbarTitle];
	replies_item.label = title_string;
	replies_item.paletteLabel = @"Replies";
	replies_item.toolTip = title_string;

	NSButton* replies_button = nil;
	if ([replies_item.view isKindOfClass:[NSButton class]]) {
		replies_button = (NSButton*) replies_item.view;
	}
	if (replies_button == nil) {
		return;
	}

	self.toolbarRepliesButton = replies_button;
	replies_button.title = title_string;
	NSImage* symbol_image = [self repliesToolbarSymbolImage];
	replies_button.image = symbol_image;
	replies_button.imagePosition = (symbol_image != nil) ? NSImageLeading : NSNoImage;
	replies_button.imageScaling = NSImageScaleProportionallyDown;
	[replies_button sizeToFit];

	NSRect button_frame = replies_button.frame;
	button_frame.size.width = MAX(72.0, button_frame.size.width + 8.0);
	button_frame.size.height = MAX(24.0, button_frame.size.height);
	replies_button.frame = button_frame;
}

- (IBAction) showConversation:(id) sender
{
	#pragma unused(sender)

	if (self.conversationController == nil) {
		self.conversationController = [[MBConversationController alloc] initWithClient:self.client token:self.token];
	}

	[self.conversationController updateForSelectedEntry:[self.sidebarController selectedItem]];
	[self.conversationController updateWithConversationPayload:self.lastConversationPayload];
	[self.conversationController showWindow:nil];
}

- (IBAction) reply:(id) sender
{
	if ([self.sidebarController canReplyToSelectedMention]) {
		[self.sidebarController replyToSelectedMention];
		return;
	}

	if (![self canReplyToConversation]) {
		return;
	}

	[self.conversationController reply:sender];
}

- (IBAction) toggleSelectedItemReadState:(id) sender
{
	#pragma unused(sender)
	[self.sidebarController toggleSelectedItemReadState];
}

- (IBAction) markAllItemsAsRead:(id) sender
{
	#pragma unused(sender)
	[self.sidebarController markAllItemsAsRead];
}

- (IBAction) toggleSelectedItemBookmarkedState:(id) sender
{
	#pragma unused(sender)
	[self.sidebarController toggleSelectedItemBookmarkedState];
}

- (IBAction) toggleReadPostsVisibility:(id) sender
{
	#pragma unused(sender)
	[self.sidebarController toggleReadPostsVisibility];
}

- (IBAction) showPreferences:(id) sender
{
	#pragma unused(sender)

	if (self.preferencesController == nil) {
		self.preferencesController = [[MBPreferencesController alloc] initWithClient:self.client token:self.token];

		__weak typeof(self) weak_self = self;
		self.preferencesController.textSettingsChangedHandler = ^{
			MBMainController* strong_self = weak_self;
			if (strong_self == nil) {
				return;
			}

			[strong_self.detailController applyPreferredTextSettings];
		};
		self.preferencesController.signOutHandler = ^{
			MBMainController* strong_self = weak_self;
			if (strong_self == nil) {
				return;
			}

			[strong_self.preferencesController close];
			SEL sign_out_selector = NSSelectorFromString(@"signOut:");
			[NSApp sendAction:sign_out_selector to:nil from:strong_self];
		};
	}

	[self.preferencesController reloadFromDefaults];
	[self.preferencesController showWindow:nil];
}

- (BOOL) validateMenuItem:(NSMenuItem*) menu_item
{
	if (menu_item.action == @selector(selectTodayView:) || menu_item.action == @selector(selectRecentView:) || menu_item.action == @selector(selectFadingView:)) {
		return ![self isFilterSelectionDisabled];
	}
	if (menu_item.action == @selector(openPostWindow:)) {
		return [self canCreateNewPost];
	}
	if (menu_item.action == @selector(share:)) {
		return [self canShareSelectedItem];
	}
	if (menu_item.action == @selector(printDetail:)) {
		return [self canPrintCurrentContent];
	}
	if (menu_item.action == @selector(newFeed:)) {
		return (self.client != nil && self.token.length > 0);
	}
	if (menu_item.action == @selector(showHighlights:)) {
		return YES;
	}
	if (menu_item.action == @selector(reply:)) {
		return ([self.sidebarController canReplyToSelectedMention] || [self canReplyToConversation]);
	}
	if (menu_item.action == @selector(sortNewestAtTop:)) {
		menu_item.state = (self.sidebarController.sortOrder == MBSidebarSortOrderNewestFirst) ? NSControlStateValueOn : NSControlStateValueOff;
		return (self.sidebarController != nil);
	}
	if (menu_item.action == @selector(sortOldestAtTop:)) {
		menu_item.state = (self.sidebarController.sortOrder == MBSidebarSortOrderOldestFirst) ? NSControlStateValueOn : NSControlStateValueOff;
		return (self.sidebarController != nil);
	}
	if (menu_item.action == @selector(toggleSelectedItemReadState:)) {
		menu_item.title = [self.sidebarController readToggleMenuTitle];
		return [self.sidebarController canToggleSelectedItemReadState];
	}
	if (menu_item.action == @selector(markAllItemsAsRead:)) {
		return [self.sidebarController canMarkAllItemsAsRead];
	}
	if (menu_item.action == @selector(toggleSelectedItemBookmarkedState:)) {
		menu_item.title = [self.sidebarController bookmarkToggleMenuTitle];
		return [self.sidebarController canToggleSelectedItemBookmarkedState];
	}
	if (menu_item.action == @selector(editPost:)) {
		BOOL can_edit = [self canEditSelectedPost];
		menu_item.hidden = !can_edit;
		return can_edit;
	}
	if (menu_item.action == @selector(toggleReadPostsVisibility:)) {
		menu_item.title = [self.sidebarController readPostsVisibilityMenuTitle];
		return (self.sidebarController != nil);
	}
	if (menu_item.action == @selector(showReadingRecap:)) {
		return [self.sidebarController canShowReadingRecap];
	}
	if (menu_item.action == @selector(showMentions:)) {
		return (self.client != nil && self.token.length > 0);
	}
	if (menu_item.action == @selector(showBookmarks:)) {
		return (self.client != nil && self.token.length > 0);
	}
	if (menu_item.action == @selector(showAllPosts:)) {
		return [self.sidebarController canShowAllPostsForSelectedSite];
	}
	if (menu_item.action == @selector(showCurrentUserPosts:)) {
		menu_item.title = [self currentUsernameMenuTitle];
		return [self canShowCurrentUserPosts];
	}
	if (menu_item.action == @selector(highlightSelectedItem:)) {
		return [self canHighlightSelectedItem];
	}

	if (menu_item.action == @selector(copyLink:)) {
		MBEntry* selected_item = [self.sidebarController selectedItem];
		if (selected_item == nil) {
			return NO;
		}

		NSString* url_string = [selected_item.url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		return (url_string.length > 0);
	}

	return YES;
}

- (BOOL) canCreateNewPost
{
	return YES;
}

- (BOOL) canShareSelectedItem
{
	MBEntry* selected_item = [self.sidebarController selectedItem];
	if (selected_item == nil) {
		return NO;
	}

	NSString* url_string = [selected_item.url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	return (url_string.length > 0);
}

- (BOOL) canPrintCurrentContent
{
	return ([self.sidebarController selectedItem] != nil && self.detailController != nil);
}

- (BOOL) canShowCurrentUserPosts
{
	return [self.client hasCachedMicropubDestinations];
}

- (BOOL) validateToolbarItem:(NSToolbarItem *)toolbar_item
{
	if (toolbar_item.action == @selector(openPostWindow:)) {
		return [self canCreateNewPost];
	}
	if (toolbar_item.action == @selector(highlightSelectedItem:)) {
		return [self canHighlightSelectedItem];
	}
	if (toolbar_item.action == @selector(showConversation:)) {
		return (self.conversationReplyCount > 0);
	}

	return YES;
}

- (BOOL) canHighlightSelectedItem
{
	MBEntry* selected_item = [self.sidebarController selectedItem];
	if (selected_item == nil || selected_item.entryID <= 0 || selected_item.isBookmarkEntry) {
		return NO;
	}

	return [self.detailController hasSelection];
}

- (BOOL) canReplyToConversation
{
	return (self.conversationController.window.isVisible && [self.conversationController canReplyToConversation]);
}

- (BOOL) canEditSelectedPost
{
	MBEntry* selected_item = [self.sidebarController selectedItem];
	if (selected_item == nil || selected_item.feedID <= 0) {
		return NO;
	}

	NSString* post_url = [selected_item.url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (post_url.length == 0) {
		return NO;
	}

	MBSubscription* current_user_blog_subscription = [self currentUserBlogSubscription];
	if (current_user_blog_subscription == nil || current_user_blog_subscription.feedID <= 0) {
		return NO;
	}

	return (selected_item.feedID == current_user_blog_subscription.feedID);
}

- (MBSubscription *) currentUserBlogSubscription
{
	NSArray* destinations = [self.client cachedMicropubDestinations];
	NSArray* subscriptions = [self.client cachedFeedSubscriptions];
	if (subscriptions.count == 0) {
		return nil;
	}

	NSString* current_destination_uid = [[NSUserDefaults standardUserDefaults] stringForKey:InkwellCurrentDestinationDefaultsKey] ?: @"";
	current_destination_uid = [current_destination_uid stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (current_destination_uid.length > 0) {
		NSDictionary* current_destination = [self destinationWithUID:current_destination_uid destinations:destinations];
		NSString* current_destination_name = [self stringValueFromObjectOrNumber:current_destination[@"name"]];
		MBSubscription* raw_subscription = [self subscriptionMatchingDestinationUID:current_destination_uid destinationName:current_destination_name subscriptions:subscriptions normalizeHosts:NO];
		if (raw_subscription != nil) {
			return raw_subscription;
		}

		MBSubscription* normalized_subscription = [self subscriptionMatchingDestinationUID:current_destination_uid destinationName:current_destination_name subscriptions:subscriptions normalizeHosts:YES];
		if (normalized_subscription != nil) {
			return normalized_subscription;
		}
	}

	if (destinations.count == 0) {
		return nil;
	}

	for (id object in destinations) {
		if (![object isKindOfClass:[NSDictionary class]]) {
			continue;
		}

		NSDictionary* destination = (NSDictionary*) object;
		NSString* destination_uid = [self stringValueFromObjectOrNumber:destination[@"uid"]];
		NSString* destination_name = [self stringValueFromObjectOrNumber:destination[@"name"]];

		MBSubscription* raw_subscription = [self subscriptionMatchingDestinationUID:destination_uid destinationName:destination_name subscriptions:subscriptions normalizeHosts:NO];
		if (raw_subscription != nil) {
			return raw_subscription;
		}

		MBSubscription* normalized_subscription = [self subscriptionMatchingDestinationUID:destination_uid destinationName:destination_name subscriptions:subscriptions normalizeHosts:YES];
		if (normalized_subscription != nil) {
			return normalized_subscription;
		}
	}

	return nil;
}

- (NSDictionary *) destinationWithUID:(NSString *)destinationUID destinations:(NSArray *)destinations
{
	NSString* normalized_uid = [destinationUID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (normalized_uid.length == 0) {
		return nil;
	}

	for (id object in destinations ?: @[]) {
		if (![object isKindOfClass:[NSDictionary class]]) {
			continue;
		}

		NSDictionary* destination = (NSDictionary*) object;
		NSString* destination_uid = [self stringValueFromObjectOrNumber:destination[@"uid"]];
		destination_uid = [destination_uid stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		if ([destination_uid isEqualToString:normalized_uid]) {
			return destination;
		}
	}

	return nil;
}

- (MBSubscription *) subscriptionMatchingDestinationUID:(NSString *)destinationUID destinationName:(NSString *)destinationName subscriptions:(NSArray *)subscriptions normalizeHosts:(BOOL)normalizeHosts
{
	for (MBSubscription* subscription in subscriptions) {
		if (subscription.feedID <= 0) {
			continue;
		}
		if ([self destinationUID:destinationUID destinationName:destinationName matchesSubscription:subscription normalizeHosts:normalizeHosts]) {
			return subscription;
		}
	}

	return nil;
}

- (BOOL) destinationUID:(NSString *)destinationUID destinationName:(NSString *)destinationName matchesSubscription:(MBSubscription *)subscription normalizeHosts:(BOOL)normalizeHosts
{
	NSArray* destination_hosts = nil;
	if (normalizeHosts) {
		destination_hosts = @[
			[self normalizedHostFromURLString:destinationUID ?: @""],
			[self normalizedHostFromURLString:destinationName ?: @""]
		];
	}
	else {
		destination_hosts = @[
			[self hostFromURLString:destinationUID ?: @""],
			[self hostFromURLString:destinationName ?: @""]
		];
	}

	NSArray* url_strings = @[ subscription.siteURL ?: @"", subscription.feedURL ?: @"" ];
	for (NSString* url_string in url_strings) {
		NSString* subscription_host = normalizeHosts ? [self normalizedHostFromURLString:url_string] : [self hostFromURLString:url_string];
		if ([self host:subscription_host matchesDestinationHosts:destination_hosts]) {
			return YES;
		}
	}

	return NO;
}

- (NSString *) currentUsernameMenuTitle
{
	NSString* username = [[NSUserDefaults standardUserDefaults] stringForKey:InkwellUsernameDefaultsKey] ?: @"";
	username = [username stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (username.length == 0) {
		return @"Posts";
	}

	if (![username hasPrefix:@"@"]) {
		username = [@"@" stringByAppendingString:username];
	}

	return [NSString stringWithFormat:@"Posts: %@", username];
}

- (NSString *) hostFromURLString:(NSString *)string
{
	if (string.length == 0) {
		return @"";
	}

	NSURLComponents* components = [NSURLComponents componentsWithString:string];
	NSString* host_value = components.host ?: @"";
	if (host_value.length == 0) {
		NSString* possible_url_string = [NSString stringWithFormat:@"https://%@", string];
		NSURLComponents* host_only_components = [NSURLComponents componentsWithString:possible_url_string];
		host_value = host_only_components.host ?: @"";
	}

	return [[host_value lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

- (NSString *) normalizedHostFromURLString:(NSString *)string
{
	return [self normalizedHostString:[self hostFromURLString:string]];
}

- (NSString *) normalizedHostString:(NSString *)hostString
{
	if (hostString.length == 0) {
		return @"";
	}

	NSString* normalized_host = [[hostString lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([normalized_host hasPrefix:@"www."]) {
		normalized_host = [normalized_host substringFromIndex:4];
	}
	if ([normalized_host hasSuffix:@"."]) {
		normalized_host = [normalized_host substringToIndex:(normalized_host.length - 1)];
	}

	return normalized_host;
}

- (BOOL) host:(NSString *)host matchesDestinationHosts:(NSArray *)destinationHosts
{
	if (host.length == 0) {
		return NO;
	}

	for (NSString* destination_host in destinationHosts) {
		if (destination_host.length == 0) {
			continue;
		}
		if ([host isEqualToString:destination_host]) {
			return YES;
		}
	}

	return NO;
}

- (NSArray*) sharingItemsForSelectedItem
{
	MBEntry* selected_item = [self.sidebarController selectedItem];
	if (selected_item == nil) {
		return @[];
	}

	NSMutableArray* sharing_items = [NSMutableArray array];

	NSString* title_string = [selected_item.title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (title_string.length > 0) {
		[sharing_items addObject:title_string];
	}

	NSString* url_string = [selected_item.url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (url_string.length > 0) {
		NSURL* share_url = [NSURL URLWithString:url_string];
		if (share_url != nil) {
			[sharing_items addObject:share_url];
		}
		else {
			[sharing_items addObject:url_string];
		}
	}

	return sharing_items;
}

- (NSRect) sharingPickerRectInView:(NSView*) view
{
	CGFloat top_inset = 20.0;
	return NSMakeRect(NSMidX(view.bounds), NSMaxY(view.bounds) - top_inset, 1.0, 1.0);
}

- (IBAction) performFindPanelAction:(id)sender
{
	if (![sender respondsToSelector:@selector(tag)]) {
		return;
	}

	NSInteger action_tag = [(id) sender tag];
	if (action_tag != NSFindPanelActionShowFindPanel) {
		return;
	}

	if (self.toolbarSearchField == nil) {
		return;
	}

	[self.toolbarSearchField selectText:nil];
}

- (void) searchFieldTextDidChange:(NSNotification*) notification
{
	NSSearchField* search_field = notification.object;
	if (![search_field isKindOfClass:[NSSearchField class]]) {
		return;
	}

	NSString* search_query = [search_field.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (search_query.length > 0 && [self.sidebarController isShowingSpecialMode]) {
		[self.sidebarController clearSpecialMode];
	}

	self.sidebarController.searchQuery = search_field.stringValue ?: @"";
	[self updateFilterSegmentedControlEnabledState];
}

- (void) newFeedURLFieldTextDidChange:(NSNotification*) notification
{
	NSTextField* text_field = notification.object;
	if (text_field != self.feedSubscriptionURLField) {
		return;
	}

	if (self.feedSubscriptionChoices.count > 0) {
		self.feedSubscriptionRequestedURLString = @"";
		[self updateNewFeedChoicesWithDictionaries:@[]];
	}

	[self updateNewFeedControls];
}

- (BOOL) control:(NSControl*) control textView:(NSTextView*) text_view doCommandBySelector:(SEL) command_selector
{
	#pragma unused(text_view)

	if (command_selector == @selector(insertNewline:) || command_selector == @selector(insertLineBreak:) || command_selector == @selector(insertNewlineIgnoringFieldEditor:)) {
		if (control == self.feedSubscriptionURLField) {
			[self subscribeNewFeed:control];
			return YES;
		}

		[self.sidebarController focusAndSelectFirstItem];
		return YES;
	}

	return NO;
}

- (IBAction) highlightSelectedItem:(id) sender
{
	#pragma unused(sender)

	MBEntry* selected_item = [self.sidebarController selectedItem];
	if (selected_item == nil || selected_item.entryID <= 0 || selected_item.isBookmarkEntry) {
		return;
	}

	NSInteger selected_entry_id = selected_item.entryID;
	__weak typeof(self) weak_self = self;
	[self.detailController requestSelectionHighlightPayloadWithCompletion:^(NSDictionary* _Nullable payload) {
		if (![payload isKindOfClass:[NSDictionary class]]) {
			return;
		}

		NSString* selection_text = [weak_self stringValueFromObjectOrNumber:payload[@"selection_text"]];
		NSInteger selection_start = [weak_self integerValueFromObject:payload[@"start_offset"]];
		NSInteger selection_end = [weak_self integerValueFromObject:payload[@"end_offset"]];
		NSString* trimmed_selection_text = [selection_text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		if (trimmed_selection_text.length == 0 || selection_end <= selection_start) {
			return;
		}

		NSString* post_title = [selected_item.title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		if (post_title.length == 0) {
			post_title = [selected_item.subscriptionTitle stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		}
		NSString* post_url = [selected_item.url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		MBHighlight* local_highlight = [weak_self.client saveLocalHighlightForEntryID:selected_entry_id postTitle:post_title postURL:post_url selectionText:trimmed_selection_text selectionStart:selection_start selectionEnd:selection_end];
		if (local_highlight == nil) {
			return;
		}

		[weak_self.detailController clearSelection];
		[weak_self updateHighlightViewsForEntryID:selected_entry_id];

		if (weak_self.token.length == 0) {
			return;
		}

		NSString* local_id = local_highlight.localID ?: @"";
		NSString* remote_selection_text = selection_text.length > 0 ? selection_text : trimmed_selection_text;
		[weak_self.client createHighlightForEntryID:selected_entry_id selectionText:remote_selection_text selectionStart:selection_start selectionEnd:selection_end token:weak_self.token completion:^(NSString * _Nullable highlight_id, NSError * _Nullable error) {
			#pragma unused(error)
			NSString* trimmed_highlight_id = [highlight_id stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
			if (trimmed_highlight_id.length == 0 || local_id.length == 0) {
				return;
			}

			[weak_self.client assignRemoteHighlightID:trimmed_highlight_id toLocalHighlightID:local_id entryID:selected_entry_id];
			[weak_self updateHighlightViewsForEntryID:selected_entry_id];
		}];
	}];
}

- (void) syncHighlightsFromServer
{
	if (self.isSyncingHighlights || self.client == nil || self.token.length == 0) {
		return;
	}

	self.isSyncingHighlights = YES;
	__weak typeof(self) weak_self = self;
	[self.client fetchAllHighlightsWithToken:self.token completion:^(NSArray * _Nullable highlights, NSError * _Nullable error) {
		weak_self.isSyncingHighlights = NO;
		if (error != nil || ![highlights isKindOfClass:[NSArray class]]) {
			return;
		}

		[weak_self.client mergeRemoteHighlightsIntoCache:highlights];
		MBEntry* selected_item = [weak_self.sidebarController selectedItem];
		NSInteger selected_entry_id = selected_item.entryID;
		[weak_self updateHighlightViewsForEntryID:selected_entry_id];
		if (weak_self.highlightsController != nil) {
			[weak_self.highlightsController reloadHighlights];
		}
	}];
}

- (void) refreshMicropubDestinationsInBackgroundIfNeeded
{
	NSArray* cached_destinations = [self.client cachedMicropubDestinations];
	if (cached_destinations.count > 0) {
		return;
	}

	[self refreshMicropubDestinationsInBackground];
}

- (void) refreshMicropubDestinationsInBackground
{
	if (self.isRefreshingMicropubDestinations || self.client == nil || self.token.length == 0) {
		return;
	}

	self.isRefreshingMicropubDestinations = YES;
	__weak typeof(self) weak_self = self;
	[self.client fetchMicropubDestinationsInBackgroundWithToken:self.token completion:^(NSArray * _Nullable destinations, NSError * _Nullable error) {
		#pragma unused(destinations)
		#pragma unused(error)
		weak_self.isRefreshingMicropubDestinations = NO;
	}];
}

- (void) scheduleMicropubDestinationsRefreshAfterOpeningNewPost
{
	__weak typeof(self) weak_self = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[weak_self refreshMicropubDestinationsInBackground];
	});
}

- (NSString*) markdownTextForNewPostWithItem:(MBEntry*) item selectionPayload:(NSDictionary* _Nullable) payload
{
	return [self markdownTextForNewPostWithItem:item selectionPayload:payload includeLinkWithoutSelection:YES];
}

- (NSString*) markdownTextForNewPostWithItem:(MBEntry*) item selectionPayload:(NSDictionary* _Nullable) payload includeLinkWithoutSelection:(BOOL) include_link_without_selection
{
	if (![item isKindOfClass:[MBEntry class]]) {
		return @"";
	}

	NSString* title_string = [item.title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (title_string.length == 0) {
		title_string = [item.subscriptionTitle stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	}

	NSString* url_string = [item.url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (url_string.length == 0) {
		return @"";
	}

	NSString* selection_text = [self stringValueFromObjectOrNumber:payload[@"selection_text"]];
	NSString* trimmed_selection_text = [selection_text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (trimmed_selection_text.length == 0) {
		if (include_link_without_selection) {
			return [NSString stringWithFormat:@"[%@](%@):\n\n", title_string, url_string];
		}

		return @"";
	}

	NSString* blockquote_text = [self blockquoteMarkdownFromText:trimmed_selection_text];
	if (blockquote_text.length == 0) {
		return [NSString stringWithFormat:@"[%@](%@):\n\n", title_string, url_string];
	}

	return [NSString stringWithFormat:@"[%@](%@):\n\n%@", title_string, url_string, blockquote_text];
}

- (NSString*) blockquoteMarkdownFromText:(NSString*) text_string
{
	NSString* normalized_text = [text_string stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] ?: @"";
	normalized_text = [normalized_text stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"] ?: @"";
	if (normalized_text.length == 0) {
		return @"";
	}

	NSArray* lines = [normalized_text componentsSeparatedByString:@"\n"];
	NSMutableArray* quoted_lines = [NSMutableArray array];
	for (NSString* line in lines) {
		[quoted_lines addObject:[NSString stringWithFormat:@"> %@", line ?: @""]];
	}

	return [quoted_lines componentsJoinedByString:@"\n"] ?: @"";
}

- (void) openNewPostForMarkdownText:(NSString*) markdown_text
{
	if ([[NSUserDefaults standardUserDefaults] boolForKey:InkwellNewPostToMicroAppDefaultsKey]) {
		[self openNewPostURLForMarkdownText:markdown_text];
		return;
	}

	NSArray* cached_destinations = [self.client cachedMicropubDestinations];
	[self openNewPostWindowForMarkdownText:markdown_text destinations:(cached_destinations ?: @[])];
	[self scheduleMicropubDestinationsRefreshAfterOpeningNewPost];
}

- (void) openNewPostWindowForMarkdownText:(NSString *)markdownText destinations:(NSArray *)destinations
{
	NSDictionary* default_destination = [self defaultMicropubDestinationFromDestinations:destinations];
	NSString* destination_name = [self stringValueFromObjectOrNumber:default_destination[@"name"]];
	NSString* destination_uid = [self stringValueFromObjectOrNumber:default_destination[@"uid"]];
	if (destination_uid.length > 0) {
		[[NSUserDefaults standardUserDefaults] setObject:destination_uid forKey:InkwellCurrentDestinationDefaultsKey];
	}

	MBNewPostController* post_controller = [self configuredPostWindowController];
	[post_controller showWithMarkdownText:markdownText destinationName:destination_name destinationUID:destination_uid destinations:destinations token:self.token];
}

- (void) openPostEditorForItem:(MBEntry *)item
{
	NSString* post_url = [item.url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (post_url.length == 0) {
		return;
	}

	NSArray* cached_destinations = [self.client cachedMicropubDestinations] ?: @[];
	NSDictionary* default_destination = [self defaultMicropubDestinationFromDestinations:cached_destinations];
	NSString* destination_name = [self stringValueFromObjectOrNumber:default_destination[@"name"]];
	NSString* destination_uid = [self stringValueFromObjectOrNumber:default_destination[@"uid"]];
	if (destination_uid.length > 0) {
		[[NSUserDefaults standardUserDefaults] setObject:destination_uid forKey:InkwellCurrentDestinationDefaultsKey];
	}

	MBNewPostController* post_controller = [self configuredPostWindowController];
	[post_controller showEditingPostURL:post_url destinationName:destination_name destinationUID:destination_uid destinations:cached_destinations token:self.token];
	[self scheduleMicropubDestinationsRefreshAfterOpeningNewPost];
}

- (MBNewPostController *) configuredPostWindowController
{
	if (self.postControllers == nil) {
		self.postControllers = [NSMutableArray array];
	}

	__weak typeof(self) weak_self = self;
	MBNewPostController* post_controller = [[MBNewPostController alloc] init];
	post_controller.destinationsProvider = ^NSArray* _Nullable {
		return [weak_self.client cachedMicropubDestinations];
	};
	post_controller.didCloseHandler = ^(MBNewPostController* closing_controller) {
		[weak_self postWindowControllerDidClose:closing_controller];
	};
	[self.postControllers addObject:post_controller];

	return post_controller;
}

- (void) postWindowControllerDidClose:(MBNewPostController*)controller
{
	[self.postControllers removeObject:controller];
	if (self.postControllers.count == 0) {
		[MBNewPostController resetPostWindowCascade];
	}
}

- (NSDictionary *) defaultMicropubDestinationFromDestinations:(NSArray *)destinations
{
	NSString* current_destination_uid = [[NSUserDefaults standardUserDefaults] stringForKey:InkwellCurrentDestinationDefaultsKey] ?: @"";
	NSDictionary* first_destination = nil;
	NSDictionary* microblog_default_destination = nil;
	for (id object in destinations ?: @[]) {
		if (![object isKindOfClass:[NSDictionary class]]) {
			continue;
		}

		NSDictionary* destination = (NSDictionary*) object;
		if (first_destination == nil) {
			first_destination = destination;
		}

		NSString* destination_uid = [self stringValueFromObjectOrNumber:destination[@"uid"]];
		if (current_destination_uid.length > 0 && [destination_uid isEqualToString:current_destination_uid]) {
			return destination;
		}

		if (microblog_default_destination == nil && [destination[@"microblog-default"] boolValue]) {
			microblog_default_destination = destination;
		}
	}

	return microblog_default_destination ?: first_destination;
}

- (void) openNewPostURLForMarkdownText:(NSString*) markdown_text
{
	NSString* normalized_text = markdown_text ?: @"";

	NSMutableCharacterSet* allowed_character_set = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
	[allowed_character_set removeCharactersInString:@":#[]@!$&'()*+,;=/?"];
	NSString* encoded_text = [normalized_text stringByAddingPercentEncodingWithAllowedCharacters:allowed_character_set] ?: @"";

	BOOL has_microblog_app = ([[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:@"blog.micro.mac"] != nil);
	NSString* open_url_string = nil;
	if (has_microblog_app) {
		open_url_string = [NSString stringWithFormat:@"microblog://post?text=%@", encoded_text];
	}
	else {
		open_url_string = [NSString stringWithFormat:@"https://micro.blog/post?text=%@", encoded_text];
	}

	NSURL* open_url = [NSURL URLWithString:open_url_string];
	if (open_url == nil) {
		return;
	}

	[[NSWorkspace sharedWorkspace] openURL:open_url];
}

- (void) updateHighlightViewsForEntryID:(NSInteger) entry_id
{
	MBEntry* selected_item = [self.sidebarController selectedItem];
	if (selected_item != nil && selected_item.entryID == entry_id) {
		[self.detailController refreshHighlights];
	}

	if (self.highlightsController != nil && self.highlightsController.entryID == entry_id) {
		[self.highlightsController reloadHighlights];
	}
}

- (NSInteger) integerValueFromObject:(id) object
{
	if ([object isKindOfClass:[NSNumber class]]) {
		return [(NSNumber*) object integerValue];
	}

	if ([object isKindOfClass:[NSString class]]) {
		return [(NSString*) object integerValue];
	}

	return 0;
}

- (NSString*) stringValueFromObjectOrNumber:(id) object
{
	if ([object isKindOfClass:[NSString class]]) {
		return (NSString*) object;
	}

	if ([object isKindOfClass:[NSNumber class]]) {
		return [(NSNumber*) object stringValue] ?: @"";
	}

	return @"";
}

- (void) setupNewFeedSheetIfNeeded
{
	if (self.feedSubscriptionSheetWindow != nil) {
		return;
	}

	NSRect content_rect = NSMakeRect(0.0, 0.0, InkwellNewFeedSheetWidth, InkwellNewFeedSheetCollapsedHeight);
	NSWindow* sheet_window = [[NSWindow alloc] initWithContentRect:content_rect styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
	sheet_window.releasedWhenClosed = NO;
	sheet_window.title = @"New Feed";
	sheet_window.titleVisibility = NSWindowTitleHidden;
	sheet_window.titlebarAppearsTransparent = YES;
	sheet_window.movable = NO;

	NSView* content_view = [[NSView alloc] initWithFrame:content_rect];
	content_view.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField* title_label = [NSTextField labelWithString:@"Subscribe to a new feed:"];
	title_label.translatesAutoresizingMaskIntoConstraints = NO;
	title_label.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];

	NSTextField* url_field = [[NSTextField alloc] initWithFrame:NSZeroRect];
	url_field.translatesAutoresizingMaskIntoConstraints = NO;
	url_field.placeholderString = @"URL";
	url_field.bezelStyle = NSTextFieldRoundedBezel;
	url_field.delegate = (id<NSTextFieldDelegate>) self;
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(newFeedURLFieldTextDidChange:) name:NSControlTextDidChangeNotification object:url_field];

	NSTableView* table_view = [[NSTableView alloc] initWithFrame:NSZeroRect];
	table_view.translatesAutoresizingMaskIntoConstraints = NO;
	table_view.delegate = self;
	table_view.dataSource = self;
	table_view.headerView = nil;
	table_view.rowHeight = InkwellNewFeedChoiceRowHeight;
	table_view.intercellSpacing = NSMakeSize(0.0, 0.0);
	table_view.usesAutomaticRowHeights = NO;
	table_view.allowsEmptySelection = NO;
	table_view.allowsMultipleSelection = NO;
	table_view.style = NSTableViewStylePlain;

	NSTableColumn* table_column = [[NSTableColumn alloc] initWithIdentifier:@"NewFeedChoicesColumn"];
	table_column.resizingMask = NSTableColumnAutoresizingMask;
	table_column.editable = NO;
	[table_view addTableColumn:table_column];

	NSScrollView* scroll_view = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	scroll_view.translatesAutoresizingMaskIntoConstraints = NO;
	scroll_view.drawsBackground = NO;
	scroll_view.hasVerticalScroller = YES;
	scroll_view.autohidesScrollers = YES;
	scroll_view.borderType = NSBezelBorder;
	scroll_view.documentView = table_view;
	scroll_view.hidden = YES;

	NSProgressIndicator* progress_indicator = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
	progress_indicator.translatesAutoresizingMaskIntoConstraints = NO;
	progress_indicator.style = NSProgressIndicatorStyleSpinning;
	progress_indicator.indeterminate = YES;
	progress_indicator.controlSize = NSControlSizeSmall;
	progress_indicator.displayedWhenStopped = NO;
	progress_indicator.hidden = YES;

	NSButton* cancel_button = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelNewFeed:)];
	cancel_button.translatesAutoresizingMaskIntoConstraints = NO;
	cancel_button.bezelStyle = NSBezelStyleRounded;
	cancel_button.keyEquivalent = @"\x1B";
	cancel_button.keyEquivalentModifierMask = 0;

	NSButton* subscribe_button = [NSButton buttonWithTitle:@"Subscribe" target:self action:@selector(subscribeNewFeed:)];
	subscribe_button.translatesAutoresizingMaskIntoConstraints = NO;
	subscribe_button.bezelStyle = NSBezelStyleRounded;
	subscribe_button.keyEquivalent = @"\r";

	[content_view addSubview:title_label];
	[content_view addSubview:url_field];
	[content_view addSubview:scroll_view];
	[content_view addSubview:progress_indicator];
	[content_view addSubview:cancel_button];
	[content_view addSubview:subscribe_button];

	NSLayoutConstraint* choices_height_constraint = [scroll_view.heightAnchor constraintEqualToConstant:0.0];
	[NSLayoutConstraint activateConstraints:@[
		[title_label.topAnchor constraintEqualToAnchor:content_view.topAnchor constant:20.0],
		[title_label.leadingAnchor constraintEqualToAnchor:content_view.leadingAnchor constant:20.0],
		[title_label.trailingAnchor constraintEqualToAnchor:content_view.trailingAnchor constant:-20.0],
		[url_field.topAnchor constraintEqualToAnchor:title_label.bottomAnchor constant:17.0],
		[url_field.leadingAnchor constraintEqualToAnchor:content_view.leadingAnchor constant:20.0],
		[url_field.trailingAnchor constraintEqualToAnchor:content_view.trailingAnchor constant:-20.0],
		[url_field.heightAnchor constraintEqualToConstant:24.0],
		[scroll_view.topAnchor constraintEqualToAnchor:url_field.bottomAnchor constant:12.0],
		[scroll_view.leadingAnchor constraintEqualToAnchor:content_view.leadingAnchor constant:20.0],
		[scroll_view.trailingAnchor constraintEqualToAnchor:content_view.trailingAnchor constant:-20.0],
		choices_height_constraint,
		[scroll_view.bottomAnchor constraintEqualToAnchor:cancel_button.topAnchor constant:-16.0],
		[progress_indicator.leadingAnchor constraintEqualToAnchor:content_view.leadingAnchor constant:20.0],
		[progress_indicator.centerYAnchor constraintEqualToAnchor:cancel_button.centerYAnchor],
		[progress_indicator.widthAnchor constraintEqualToConstant:16.0],
		[progress_indicator.heightAnchor constraintEqualToConstant:16.0],
		[cancel_button.trailingAnchor constraintEqualToAnchor:subscribe_button.leadingAnchor constant:-8.0],
		[cancel_button.bottomAnchor constraintEqualToAnchor:content_view.bottomAnchor constant:-16.0],
		[subscribe_button.trailingAnchor constraintEqualToAnchor:content_view.trailingAnchor constant:-20.0],
		[subscribe_button.bottomAnchor constraintEqualToAnchor:cancel_button.bottomAnchor]
	]];

	sheet_window.contentView = content_view;
	sheet_window.defaultButtonCell = subscribe_button.cell;
	sheet_window.initialFirstResponder = url_field;

	self.feedSubscriptionSheetWindow = sheet_window;
	self.feedSubscriptionURLField = url_field;
	self.feedSubscriptionChoicesTableView = table_view;
	self.feedSubscriptionChoicesScrollView = scroll_view;
	self.feedSubscriptionProgressIndicator = progress_indicator;
	self.feedSubscriptionCancelButton = cancel_button;
	self.feedSubscriptionSubscribeButton = subscribe_button;
	self.feedSubscriptionChoicesHeightConstraint = choices_height_constraint;
	self.feedSubscriptionChoices = @[];
	self.feedSubscriptionRequestedURLString = @"";
	[self updateNewFeedControls];
}

- (void) resetNewFeedSheetState
{
	self.feedSubscriptionRequestedURLString = @"";
	self.feedSubscriptionChoices = @[];
	self.isCreatingFeedSubscription = NO;
	self.feedSubscriptionURLField.stringValue = @"";
	[self.feedSubscriptionChoicesTableView deselectAll:nil];
	[self.feedSubscriptionChoicesTableView reloadData];
	[self setNewFeedChoicesVisible:NO animated:NO];
	[self updateNewFeedControls];
}

- (void) updateNewFeedChoicesWithDictionaries:(NSArray*) choices
{
	NSMutableArray* parsed_choices = [NSMutableArray array];
	for (id object in choices ?: @[]) {
		if (![object isKindOfClass:[NSDictionary class]]) {
			continue;
		}

		NSDictionary* dictionary = (NSDictionary*) object;
		NSString* feed_url = [self stringValueFromObjectOrNumber:dictionary[@"feed_url"]];
		NSString* title_value = [self stringValueFromObjectOrNumber:dictionary[@"title"]];
		if (feed_url.length == 0) {
			continue;
		}

		MBNewFeedChoice* choice = [[MBNewFeedChoice alloc] init];
		choice.title = title_value ?: @"";
		choice.feedURL = feed_url;
		choice.isJSONFeed = [dictionary[@"is_json_feed"] boolValue];
		[parsed_choices addObject:choice];
	}

	self.feedSubscriptionChoices = [parsed_choices copy];
	[self.feedSubscriptionChoicesTableView reloadData];

	BOOL should_show_choices = (self.feedSubscriptionChoices.count > 0);
	[self setNewFeedChoicesVisible:should_show_choices animated:YES];
	if (should_show_choices) {
		NSIndexSet* first_index = [NSIndexSet indexSetWithIndex:0];
		[self.feedSubscriptionChoicesTableView selectRowIndexes:first_index byExtendingSelection:NO];
		[self.feedSubscriptionChoicesTableView scrollRowToVisible:0];
		[self.feedSubscriptionSheetWindow makeFirstResponder:self.feedSubscriptionChoicesTableView];
	}
}

- (void) setNewFeedChoicesVisible:(BOOL) is_visible animated:(BOOL) is_animated
{
	self.feedSubscriptionChoicesScrollView.hidden = !is_visible;
	self.feedSubscriptionChoicesHeightConstraint.constant = is_visible ? InkwellNewFeedChoicesHeight : 0.0;
	[self resizeNewFeedSheetToContentHeight:(is_visible ? InkwellNewFeedSheetExpandedHeight : InkwellNewFeedSheetCollapsedHeight) animated:is_animated];
	[self.feedSubscriptionSheetWindow.contentView layoutSubtreeIfNeeded];
}

- (void) resizeNewFeedSheetToContentHeight:(CGFloat) content_height animated:(BOOL) is_animated
{
	if (self.feedSubscriptionSheetWindow == nil) {
		return;
	}

	NSRect current_frame = self.feedSubscriptionSheetWindow.frame;
	NSRect current_content_rect = [self.feedSubscriptionSheetWindow contentRectForFrameRect:current_frame];
	if (fabs(current_content_rect.size.height - content_height) < 0.5) {
		return;
	}

	NSRect target_content_rect = current_content_rect;
	target_content_rect.size.height = content_height;
	NSRect target_frame = [self.feedSubscriptionSheetWindow frameRectForContentRect:target_content_rect];
	target_frame.origin.x = current_frame.origin.x;
	target_frame.origin.y = current_frame.origin.y - (target_frame.size.height - current_frame.size.height);
	if (is_animated) {
		[NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
			context.duration = 0.18;
			[[self.feedSubscriptionSheetWindow animator] setFrame:target_frame display:YES];
		} completionHandler:nil];
	}
	else {
		[self.feedSubscriptionSheetWindow setFrame:target_frame display:YES];
	}
}

- (void) updateNewFeedControls
{
	BOOL is_busy = self.isCreatingFeedSubscription;
	self.feedSubscriptionURLField.enabled = !is_busy;
	self.feedSubscriptionChoicesTableView.enabled = !is_busy;
	self.feedSubscriptionCancelButton.enabled = !is_busy;

	if (is_busy) {
		self.feedSubscriptionProgressIndicator.hidden = NO;
		[self.feedSubscriptionProgressIndicator startAnimation:nil];
	}
	else {
		[self.feedSubscriptionProgressIndicator stopAnimation:nil];
		self.feedSubscriptionProgressIndicator.hidden = YES;
	}

	BOOL has_url_value = ([self normalizedNewFeedURLString].length > 0);
	BOOL has_choice = ([self selectedNewFeedChoice] != nil);
	self.feedSubscriptionSubscribeButton.enabled = (!is_busy && (has_choice || has_url_value));
}

- (NSString*) normalizedNewFeedURLString
{
	return [self.feedSubscriptionURLField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

- (MBNewFeedChoice* _Nullable) selectedNewFeedChoice
{
	NSInteger selected_row = self.feedSubscriptionChoicesTableView.selectedRow;
	if (selected_row < 0 || selected_row >= self.feedSubscriptionChoices.count) {
		return nil;
	}

	id object = self.feedSubscriptionChoices[(NSUInteger) selected_row];
	if (![object isKindOfClass:[MBNewFeedChoice class]]) {
		return nil;
	}

	return (MBNewFeedChoice*) object;
}

- (void) closeNewFeedSheetWithReturnCode:(NSModalResponse) return_code
{
	if (self.window.attachedSheet != self.feedSubscriptionSheetWindow) {
		return;
	}

	[self.window endSheet:self.feedSubscriptionSheetWindow returnCode:return_code];
}

- (void) presentNewFeedError:(NSError*) error
{
	if (error == nil || self.feedSubscriptionSheetWindow == nil) {
		return;
	}

	NSAlert* alert = [[NSAlert alloc] init];
	alert.alertStyle = NSAlertStyleWarning;
	alert.messageText = @"Subscribe Failed";
	alert.informativeText = error.localizedDescription ?: @"The feed could not be subscribed.";
	[alert beginSheetModalForWindow:self.feedSubscriptionSheetWindow completionHandler:nil];
}

- (NSInteger) numberOfRowsInTableView:(NSTableView*) tableView
{
	if (tableView != self.feedSubscriptionChoicesTableView) {
		return 0;
	}

	return self.feedSubscriptionChoices.count;
}

- (NSView* _Nullable) tableView:(NSTableView*) tableView viewForTableColumn:(NSTableColumn*) tableColumn row:(NSInteger) row
{
	#pragma unused(tableColumn)
	if (tableView != self.feedSubscriptionChoicesTableView) {
		return nil;
	}

	if (row < 0 || row >= self.feedSubscriptionChoices.count) {
		return nil;
	}

	MBNewFeedChoiceCellView* cell_view = [tableView makeViewWithIdentifier:InkwellNewFeedChoiceCellIdentifier owner:self];
	if (cell_view == nil) {
		cell_view = [[MBNewFeedChoiceCellView alloc] initWithFrame:NSZeroRect];
		cell_view.identifier = InkwellNewFeedChoiceCellIdentifier;
	}

	MBNewFeedChoice* choice = self.feedSubscriptionChoices[(NSUInteger) row];
	[cell_view configureWithChoice:choice];
	return cell_view;
}

- (void) tableViewSelectionDidChange:(NSNotification*) notification
{
	NSTableView* table_view = notification.object;
	if (table_view != self.feedSubscriptionChoicesTableView) {
		return;
	}

	if (self.feedSubscriptionChoices.count > 0 && table_view.selectedRow < 0) {
		NSIndexSet* first_index = [NSIndexSet indexSetWithIndex:0];
		[table_view selectRowIndexes:first_index byExtendingSelection:NO];
	}

	[self updateNewFeedControls];
}

#pragma mark - Toolbar

- (NSArray<NSToolbarItemIdentifier> *) toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
	return @[
		InkwellToolbarFilterItemIdentifier,
		NSToolbarSidebarTrackingSeparatorItemIdentifier,
		InkwellToolbarProgressItemIdentifier,
		NSToolbarFlexibleSpaceItemIdentifier,
		InkwellToolbarRepliesItemIdentifier,
		InkwellToolbarHighlightItemIdentifier,
		InkwellToolbarNewPostItemIdentifier,
		InkwellToolbarSearchItemIdentifier
	];
}

- (NSArray<NSToolbarItemIdentifier> *) toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
	return @[
		InkwellToolbarFilterItemIdentifier,
		NSToolbarSidebarTrackingSeparatorItemIdentifier,
		InkwellToolbarProgressItemIdentifier,
		NSToolbarFlexibleSpaceItemIdentifier,
		InkwellToolbarSearchItemIdentifier,
		InkwellToolbarHighlightItemIdentifier,
		InkwellToolbarNewPostItemIdentifier
	];
}

- (NSToolbarItem *) toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)item_identifier willBeInsertedIntoToolbar:(BOOL)flag
{
	if ([item_identifier isEqualToString:InkwellToolbarFilterItemIdentifier]) {
		NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:item_identifier];
		item.label = @"Filter";

		self.filterSegmentedControl = [NSSegmentedControl segmentedControlWithLabels:@[@"Today", @"Recent", @"Fading"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(filterSegmentChanged:)];
		self.filterSegmentedControl.selectedSegment = InkwellFilterTodaySegmentIndex;
		self.filterSegmentedControl.segmentStyle = NSSegmentStyleAutomatic;
		self.filterSegmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
		[self updateFilterSegmentedControlEnabledState];

		item.view = self.filterSegmentedControl;
		return item;
	}

	if ([item_identifier isEqualToString:InkwellToolbarProgressItemIdentifier]) {
		NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:item_identifier];
		item.label = @"Loading";
		[item setBordered:NO];

		NSProgressIndicator *progress_indicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0.0, 0.0, 16.0, 16.0)];
		progress_indicator.style = NSProgressIndicatorStyleSpinning;
		progress_indicator.indeterminate = YES;
		progress_indicator.controlSize = NSControlSizeSmall;
		progress_indicator.displayedWhenStopped = NO;
		progress_indicator.hidden = YES;

		item.view = progress_indicator;
		self.toolbarProgressIndicator = progress_indicator;
		[self updateToolbarProgressIndicator];
		return item;
	}

	if ([item_identifier isEqualToString:InkwellToolbarSearchItemIdentifier]) {
		NSSearchToolbarItem *item = [[NSSearchToolbarItem alloc] initWithItemIdentifier:item_identifier];
		item.label = @"Search";
		item.paletteLabel = @"Search";
		item.preferredWidthForSearchField = 200.0;

		NSSearchField* previous_search_field = self.toolbarSearchField;
		if (previous_search_field != nil) {
			[[NSNotificationCenter defaultCenter] removeObserver:self name:NSControlTextDidChangeNotification object:previous_search_field];
		}

		self.toolbarSearchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 0.0)];
		self.toolbarSearchField.placeholderString = @"Search";
		self.toolbarSearchField.delegate = self;
		[self.toolbarSearchField.widthAnchor constraintEqualToConstant:200.0].active = YES;
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(searchFieldTextDidChange:) name:NSControlTextDidChangeNotification object:self.toolbarSearchField];

		item.searchField = self.toolbarSearchField;
		return item;
	}

	if ([item_identifier isEqualToString:InkwellToolbarHighlightItemIdentifier]) {
		NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:item_identifier];
		item.label = @"Highlight";
		item.paletteLabel = @"Highlight";
		item.toolTip = @"Highlight";
		item.image = [NSImage imageNamed:@"icon_highlighter"];
		item.target = self;
		item.action = @selector(highlightSelectedItem:);
		return item;
	}

	if ([item_identifier isEqualToString:InkwellToolbarNewPostItemIdentifier]) {
		NSToolbarItem* item = [[NSToolbarItem alloc] initWithItemIdentifier:item_identifier];
		item.label = @"New Post";
		item.paletteLabel = @"New Post";
		item.toolTip = @"New Post";
		item.image = [NSImage imageWithSystemSymbolName:@"square.and.pencil" accessibilityDescription:@"New Post"];
		item.target = self;
		item.action = @selector(openPostWindow:);
		return item;
	}

	if ([item_identifier isEqualToString:InkwellToolbarRepliesItemIdentifier]) {
		NSToolbarItem* item = [[NSToolbarItem alloc] initWithItemIdentifier:item_identifier];
		NSString* title_string = [self repliesToolbarTitle];
		item.label = title_string;
		item.paletteLabel = @"Replies";
		item.toolTip = title_string;

		NSButton* replies_button = [NSButton buttonWithTitle:title_string target:self action:@selector(showConversation:)];
		replies_button.bezelStyle = NSBezelStyleRounded;
		NSImage* symbol_image = [self repliesToolbarSymbolImage];
		replies_button.image = symbol_image;
		replies_button.imagePosition = (symbol_image != nil) ? NSImageLeading : NSNoImage;
		replies_button.imageScaling = NSImageScaleProportionallyDown;
		[replies_button sizeToFit];

		NSRect button_frame = replies_button.frame;
		button_frame.size.width = MAX(72.0, button_frame.size.width + 8.0);
		button_frame.size.height = MAX(24.0, button_frame.size.height);
		replies_button.frame = button_frame;

		item.view = replies_button;
		self.toolbarRepliesButton = replies_button;
		return item;
	}

	if ([item_identifier isEqualToString:NSToolbarSidebarTrackingSeparatorItemIdentifier]) {
		if (self.mainSplitView == nil) {
			return [[NSToolbarItem alloc] initWithItemIdentifier:item_identifier];
		}

		return [NSTrackingSeparatorToolbarItem trackingSeparatorToolbarItemWithIdentifier:item_identifier splitView:self.mainSplitView dividerIndex:0];
	}

	return nil;
}

@end
