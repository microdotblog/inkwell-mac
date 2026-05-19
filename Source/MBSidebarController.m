//
//  MBSidebarController.m
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import "MBSidebarController.h"
#import <QuartzCore/CATransform3D.h>
#import <QuartzCore/CAMediaTimingFunction.h>
#import "MBAvatarLoader.h"
#import "MBClient.h"
#import "MBConversationCellView.h"
#import "MBEntry.h"
#import "MBMention.h"
#import "MBPathUtilities.h"
#import "MBPodcastController.h"
#import "MBReplyController.h"
#import "MBRoundedImageView.h"
#import "MBSidebarRecapBoxView.h"
#import "MBSidebarCell.h"
#import "MBSidebarRowView.h"
#import "MBSidebarTableView.h"
#import "MBSubscription.h"
#import "NSStrings+Extras.h"

static NSUserInterfaceItemIdentifier const InkwellSidebarCellIdentifier = @"InkwellSidebarCell";
static NSUserInterfaceItemIdentifier const InkwellSidebarMentionCellIdentifier = @"InkwellSidebarMentionCell";
static NSUserInterfaceItemIdentifier const InkwellSidebarRowIdentifier = @"InkwellSidebarRow";
static CGFloat const InkwellSidebarAvatarSize = 26.0;
static CGFloat const InkwellSidebarRecapBoxHeight = 42.0;
static CGFloat const InkwellSidebarBookmarksBoxHeight = 46.0;
static CGFloat const InkwellSidebarPodcastPaneAnimationOffset = 12.0;
static NSTimeInterval const InkwellSidebarRecapPollInterval = 3.0;
static NSTimeInterval const InkwellSidebarEntriesLookbackInterval = 7.0 * 24.0 * 60.0 * 60.0;
static NSInteger const InkwellSidebarRecapMaxAttempts = 20;
static NSString* const InkwellPlansURLString = @"https://micro.blog/account/plans";
static NSString* const InkwellRecentEntriesCacheFilename = @"RecentEntries.json";
static NSString* const InkwellFadingEntryIDsCacheFilename = @"FadingEntryIDs.json";
static NSString* const InkwellSidebarSelectedEntryCacheFilename = @"SidebarSelectedEntry.json";
static NSString* const InkwellHideReadPostsDefaultsKey = @"HideReadPosts";
static NSString* const InkwellSidebarSortOrderDefaultsKey = @"SidebarSortOrder";
static NSString* const InkwellSelectedUnfocusedColorName = @"color_selected_unfocused_text";
static NSString* const InkwellUnreadBackgroundColorName = @"color_unread_background";
static NSString* const InkwellUnreadBorderColorName = @"color_unread_border";
static NSString* const InkwellPostStatusDraft = @"draft";

@interface MBSidebarCurrentPostsButton : NSButton

@property (strong) NSTrackingArea* trackingArea;
@property (strong) NSImage* chevronImage;
@property (strong) NSImage* placeholderImage;

@end

@implementation MBSidebarCurrentPostsButton

- (void) updateTrackingAreas
{
	[super updateTrackingAreas];

	if (self.trackingArea != nil) {
		[self removeTrackingArea:self.trackingArea];
	}

	NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect;
	self.trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect options:options owner:self userInfo:nil];
	[self addTrackingArea:self.trackingArea];
}

- (void) mouseEntered:(NSEvent *) event
{
	#pragma unused(event)

	self.image = self.chevronImage;
}

- (void) mouseExited:(NSEvent *) event
{
	#pragma unused(event)

	self.image = self.placeholderImage;
}

- (void) mouseDown:(NSEvent *) event
{
	#pragma unused(event)

	if (self.action != nil) {
		[NSApp sendAction:self.action to:self.target from:self];
		return;
	}

	[super mouseDown:event];
}

@end

typedef NS_ENUM(NSInteger, MBSidebarContentMode) {
	MBSidebarContentModeFeeds = 0,
	MBSidebarContentModeBookmarks = 1,
	MBSidebarContentModeMentions = 2,
	MBSidebarContentModeAllPosts = 3
};

@interface MBSidebarController () <NSTableViewDataSource, NSTableViewDelegate, NSMenuItemValidation>

@property (assign) BOOL hasLoadedRemoteItems;
@property (assign) BOOL isFetching;
@property (assign) NSInteger selectedRowForStyling;
@property (strong) NSTableView *tableView;
@property (strong) NSScrollView* tableScrollView;
@property (strong) MBPodcastController* podcastController;
@property (strong) NSView* podcastContainerView;
@property (strong) NSView* podcastContentView;
@property (strong) NSLayoutConstraint* podcastHeightConstraint;
@property (strong, nullable) MBEntry* currentPodcastEntry;
@property (nonatomic, assign) BOOL podcastPaneDisplayed;
@property (assign) BOOL keepsPausedPodcastPaneVisibleUntilSelectionChange;
@property (copy) NSArray<MBEntry *> *allItems;
@property (copy) NSArray<MBEntry *> *bookmarkItems;
@property (copy) NSArray<MBEntry *> *mentionItems;
@property (copy) NSArray* mentions;
@property (copy) NSArray<MBEntry *> *allPostsItems;
@property (copy) NSDictionary<NSString *, NSString *> *iconURLByHost;
@property (strong) MBAvatarLoader* avatarLoader;
@property (strong) NSImage *defaultAvatarImage;
@property (strong) MBReplyController* replyController;
@property (strong) NSBox* recapBoxView;
@property (strong) NSButton* recapButton;
@property (strong) NSTextField* recapCountLabel;
@property (strong) NSTextField* bookmarksTitleLabel;
@property (strong) NSTextField* currentPostsTitleLabel;
@property (strong) MBSidebarCurrentPostsButton* currentPostsHostnameButton;
@property (strong) NSButton* bookmarksClearButton;
@property (strong) NSLayoutConstraint* recapBoxHeightConstraint;
@property (strong) NSLayoutConstraint* recapToTableTopConstraint;
@property (assign) BOOL isRecapFetching;
@property (assign) BOOL isFetchingBookmarks;
@property (assign) BOOL isFetchingMentions;
@property (assign) BOOL isFetchingAllPosts;
@property (assign) NSInteger recapRequestIdentifier;
@property (assign) NSInteger bookmarksRequestIdentifier;
@property (assign) NSInteger mentionsRequestIdentifier;
@property (assign) NSInteger allPostsRequestIdentifier;
@property (weak) NSWindow* observedWindowForSelectionStyling;
@property (strong) NSView* premiumRequiredView;
@property (assign) BOOL hideReadPosts;
@property (assign) BOOL isPreservingSelectionDuringReload;
@property (assign) BOOL suppressSelectionChangedHandler;
@property (assign) MBSidebarContentMode contentMode;
@property (assign) NSInteger allPostsFeedID;
@property (assign) NSInteger rememberedDeselectedRow;
@property (copy) NSString* allPostsSiteName;
@property (copy) NSString* allPostsFeedHost;
@property (assign) BOOL allPostsUsesCurrentDestination;
@property (copy) NSString* allPostsDestinationUID;
@property (copy) NSString* allPostsPostStatus;
@property (copy) NSSet* preservedVisibleEntryIDsForHiddenReadPosts;
@property (strong) NSMutableDictionary* pendingReadStateOverridesByEntryID;
@property (copy) NSArray* fadingEntryIDs;
@property (assign) BOOL hasFadingEntryIDsCache;
@property (strong) MBSidebarCell* sizingCellView;
@property (strong) MBConversationCellView* sizingMentionCellView;

- (void) markSelectedItemAsReadIfNeeded:(MBEntry *)item atRow:(NSInteger)row;
- (void) updateCachedReadState:(BOOL)is_read forEntryID:(NSInteger)entry_id;
- (void) updateCachedReadState:(BOOL) is_read forEntryIDs:(NSArray*) entry_ids;
- (void) updateCachedBookmarkedState:(BOOL)is_bookmarked forEntryID:(NSInteger)entry_id;
- (void) updatePodcastPaneHeightAnimated:(BOOL) animated;
- (void) reloadRowForEntryID:(NSInteger)entry_id preferredRow:(NSInteger)preferred_row;
- (void) reloadTablePreservingSelectionForEntryID:(NSInteger) entry_id notifySelectionIfUnchanged:(BOOL) notify_if_unchanged;
- (void) applyFiltersAndReloadPreservingSelectionEntryID:(NSInteger) preferred_entry_id;
- (NSInteger) preferredSelectionEntryIDForReload;
- (NSInteger) currentSelectedEntryID;
- (BOOL) restoreSelectionForEntryID:(NSInteger)entry_id notifySelectionIfUnchanged:(BOOL) notify_if_unchanged;
- (void) restoreSelectionForEntryIDOnNextRunLoop:(NSInteger) entry_id;
- (NSInteger) rowForEntryID:(NSInteger)entry_id;
- (BOOL) isRowSelectedForStyling:(NSInteger) row tableView:(NSTableView*) table_view;
- (void) configureRowView:(MBSidebarRowView*) row_view forRow:(NSInteger) row tableView:(NSTableView*) table_view;
- (NSInteger) savedSelectedEntryID;
- (void) clearSavedSelectedEntryID;
- (void) saveSelectedEntryIDForCurrentSelection;
- (void) deselectSidebarSelectionPreservingDetail;
- (void) clearRememberedDeselectedRow;
- (void) clearPreservedHiddenReadState;
- (void) scrollTableToTop;
- (void) refreshSelectionStylingForSelectedRow:(NSInteger) selected_row;
- (void) startObservingWindowKeyState;
- (void) stopObservingWindowKeyState;
- (void) windowKeyStateDidChange:(NSNotification*) notification;
- (BOOL) hasEmphasizedSelectionForTableView:(NSTableView*) table_view;
- (BOOL) moveSelectionFromRememberedRow:(NSInteger) direction;
- (BOOL) performPrimaryActionForSelectedItem;
- (BOOL) editSelectedItemIfPossible;
- (BOOL) openSelectedItemInBrowser;
- (NSString*) readToggleMenuTitleForSelectedItem:(MBEntry* _Nullable) selected_item;
- (NSString*) bookmarkToggleMenuTitleForSelectedItem:(MBEntry* _Nullable) selected_item;
- (void) updateRecapUI;
- (void) updatePremiumRequiredView;
- (void) setRecapFetching:(BOOL)is_fetching;
- (void) finishReadingRecapPollingForRequestIdentifier:(NSInteger) request_identifier;
- (void) fetchBookmarksIfNeeded;
- (void) fetchBookmarks;
- (void) fetchMentions;
- (void) fetchAllPostsIfNeeded;
- (void) fetchAllPosts;
- (void) showAllPostsForFeedID:(NSInteger)feedID siteName:(NSString *)siteName feedHost:(NSString *)feedHost usesCurrentDestination:(BOOL)uses_current_destination postStatus:(NSString *)post_status;
- (void) showCurrentPostsForSubscription:(MBSubscription *)subscription;
- (MBSubscription * _Nullable) subscriptionMatchingDestination:(NSDictionary *)destination subscriptions:(NSArray *)subscriptions normalizeHosts:(BOOL)normalize_hosts;
- (BOOL) destinationUID:(NSString *)destinationUID destinationName:(NSString *)destinationName matchesSubscription:(MBSubscription *)subscription normalizeHosts:(BOOL)normalize_hosts;
- (BOOL) host:(NSString *)host matchesDestinationHosts:(NSArray *)destination_hosts;
- (void) ensureSpecialModeSelectionIfNeeded;
- (void) resetBookmarksModeState;
- (void) resetMentionsModeState;
- (void) resetAllPostsModeState;
- (void) cacheRecentEntries;
- (NSURL* _Nullable) recentEntriesCacheURL;
- (NSURL* _Nullable) fadingEntryIDsCacheURL;
- (NSURL* _Nullable) selectedEntryCacheURL;
- (NSArray*) loadCachedFadingEntryIDs;
- (void) cacheFadingEntryIDs:(NSArray*) entry_ids;
- (NSArray*) normalizedFadingEntryIDsFromObjects:(NSArray*) objects;
- (void) updateFadingEntryIDsFromCurrentItemsIsFinished:(BOOL) is_finished preserveCachedValueDuringFetch:(BOOL) preserve_cached_value_during_fetch;
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
- (BOOL) entryShowsReadState:(MBEntry*) entry;
- (NSArray*) sortedItems:(NSArray*) items;
- (NSComparisonResult) compareEntry:(MBEntry*) first_entry toEntry:(MBEntry*) second_entry;
- (NSString*) recapCountStringForPostsCount:(NSInteger)post_count;
- (NSAttributedString*) premiumRequiredMessageAttributedString;
- (BOOL) shouldShowPremiumRequiredView;
- (BOOL) shouldShowSpecialModeBanner;
- (BOOL) isShowingAllPostsMode;
- (BOOL) shouldShowCurrentPostsBanner;
- (MBMention* _Nullable) selectedMention;
- (BOOL) canReplyToMention:(MBMention*) mention;
- (NSString*) prefillTextForUsername:(NSString*) username;
- (void) presentReplyControllerWithPostID:(NSString*) post_id prefillText:(NSString*) prefill_text;
- (NSString*) specialModeBannerTitle;
- (NSString *) currentDestinationDisplayName;
- (NSString *) hostFromURLString:(NSString *) string;
- (NSString *) currentDestinationUID;
- (void) showCurrentDestinationsMenuFromView:(NSView *)view event:(NSEvent *)event;
- (void) updateCurrentPostsHostnameButton;
- (NSString*) siteNameForEntry:(MBEntry*) entry;
- (NSString*) feedHostForEntry:(MBEntry*) entry;
- (BOOL) isPremiumUser;
- (BOOL) savedHideReadPosts;
- (MBSidebarSortOrder) savedSortOrder;
- (void) configureSidebarCellContent:(MBSidebarCell*) cell_view entry:(MBEntry*) item;
- (void) configureSidebarCellContent:(MBSidebarCell*) cell_view entry:(MBEntry*) item includeAvatar:(BOOL) includeAvatar;
- (CGFloat) fittingHeightForSidebarCellWithEntry:(MBEntry*) item width:(CGFloat) width;
- (CGFloat) fittingHeightForMention:(MBMention*) mention width:(CGFloat) width;
- (NSString*) podcastArtworkURLStringForEntry:(MBEntry*) entry;
- (void) setPodcastPaneVisible:(BOOL) is_visible;
- (void) updatePodcastPaneForSelectedItem:(MBEntry* _Nullable) selected_item;
- (NSMenu*) sidebarContextMenu;
- (IBAction) toggleSelectedItemReadStateAction:(id)sender;
- (IBAction) toggleSelectedItemBookmarkedStateAction:(id)sender;
- (IBAction) openSelectedItemInBrowserAction:(id)sender;
- (IBAction) copySelectedItemLinkAction:(id)sender;
- (IBAction) clearSpecialModeAction:(id)sender;
- (IBAction) currentPostsHostnameAction:(id)sender;
- (IBAction) selectCurrentDestinationFromMenuItem:(id)sender;
- (IBAction) openPlansAction:(id)sender;
- (void) pollReadingRecapForEntryIDs:(NSArray*) entry_ids attempt:(NSInteger)attempt requestIdentifier:(NSInteger)request_identifier;
- (void) avatarImageDidLoad:(NSNotification*) notification;
- (void) reloadRowsForAvatarURLString:(NSString*) url_string;
- (void) reloadRowsForIconURLString:(NSString*) url_string;
- (NSArray<MBEntry *> *) sidebarItemsForBookmarks:(NSArray*) items;
- (NSArray*) mentionsFromItems:(NSArray*) items;
- (NSArray<MBEntry *> *) sidebarItemsForMentions:(NSArray*) mentions;
- (NSArray<MBEntry *> *) sidebarItemsForEntries:(NSArray*) entries subscriptionTitle:(NSString*) subscription_title feedHost:(NSString*) feed_host unreadEntryIDs:(NSSet* _Nullable) unread_entry_ids;
- (NSArray<MBEntry *> *) sidebarItemsByMergingFetchedItems:(NSArray<MBEntry *> *) fetched_items withExistingItems:(NSArray<MBEntry *> *) existing_items unreadEntryIDs:(NSSet* _Nullable) unread_entry_ids;
- (BOOL) shouldPreserveExistingSidebarItemDuringRefresh:(MBEntry*) item oldestFetchedDate:(NSDate* _Nullable) oldest_fetched_date;
- (MBEntry* _Nullable) sidebarItemForEntryDictionary:(NSDictionary*) entry subscriptionTitle:(NSString*) subscription_title feedHost:(NSString*) feed_host unreadEntryIDs:(NSSet* _Nullable) unread_entry_ids;
- (NSString*) displayDateStringForCurrentMode:(NSDate* _Nullable) date;
- (NSString*) allPostsDisplayDateString:(NSDate* _Nullable) date;
- (NSString*) bookmarksDisplayDateString:(NSDate* _Nullable) date;
- (NSString*) mentionsDisplayDateString:(NSDate* _Nullable) date;
- (NSDictionary*) dictionaryValueFromObject:(id) object;
- (NSString*) stringValueFromObjectOrNumber:(id) object;
- (NSString*) plainTextFromHTMLString:(NSString*) html_string;
- (NSString*) normalizedTextString:(NSString*) text_string;
- (NSImage*) avatarImageForMention:(MBMention*) mention;

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
		self.rememberedDeselectedRow = -1;
		self.allItems = @[];
		self.bookmarkItems = @[];
		self.allPostsItems = @[];
		self.iconURLByHost = @{};
		self.avatarLoader = [MBAvatarLoader sharedLoader];
		self.items = @[];
		self.contentMode = MBSidebarContentModeFeeds;
		self.mentionItems = @[];
		self.mentions = @[];
		self.allPostsSiteName = @"";
		self.allPostsFeedHost = @"";
		self.allPostsUsesCurrentDestination = NO;
		self.allPostsDestinationUID = @"";
		self.allPostsPostStatus = @"";
		self.pendingReadStateOverridesByEntryID = [NSMutableDictionary dictionary];
		self.fadingEntryIDs = @[];
		NSURL* fading_cache_url = [self fadingEntryIDsCacheURL];
		self.hasFadingEntryIDsCache = (fading_cache_url != nil && [[NSFileManager defaultManager] fileExistsAtPath:fading_cache_url.path]);
		if (self.hasFadingEntryIDsCache) {
			self.fadingEntryIDs = [self loadCachedFadingEntryIDs];
		}
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

	MBSidebarRecapBoxView* recap_box = [[MBSidebarRecapBoxView alloc] initWithFrame:NSZeroRect];
	recap_box.translatesAutoresizingMaskIntoConstraints = NO;
	recap_box.boxType = NSBoxCustom;
	recap_box.borderColor = [NSColor separatorColor];
	recap_box.borderWidth = 1.0;
	recap_box.cornerRadius = 0.0;
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

	NSTextField* current_posts_label = [NSTextField labelWithString:@"Showing posts:"];
	current_posts_label.translatesAutoresizingMaskIntoConstraints = NO;
	current_posts_label.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
	current_posts_label.textColor = [NSColor labelColor];
	current_posts_label.lineBreakMode = NSLineBreakByTruncatingTail;
	current_posts_label.maximumNumberOfLines = 1;
	current_posts_label.usesSingleLineMode = YES;
	[current_posts_label setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
	[current_posts_label setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
	current_posts_label.hidden = YES;

	MBSidebarCurrentPostsButton* current_posts_hostname_button = [MBSidebarCurrentPostsButton buttonWithTitle:@"" target:self action:@selector(currentPostsHostnameAction:)];
	current_posts_hostname_button.translatesAutoresizingMaskIntoConstraints = NO;
	current_posts_hostname_button.bordered = NO;
	current_posts_hostname_button.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
	current_posts_hostname_button.imagePosition = NSImageTrailing;
	current_posts_hostname_button.imageHugsTitle = YES;
	current_posts_hostname_button.lineBreakMode = NSLineBreakByTruncatingTail;
	current_posts_hostname_button.focusRingType = NSFocusRingTypeNone;
	current_posts_hostname_button.hidden = YES;
	NSImage* current_posts_chevron_image = [NSImage imageWithSystemSymbolName:@"chevron.down" accessibilityDescription:@"Show blogs"];
	NSImageSymbolConfiguration* current_posts_chevron_configuration = [NSImageSymbolConfiguration configurationWithPointSize:10.0 weight:NSFontWeightSemibold];
	current_posts_hostname_button.chevronImage = [current_posts_chevron_image imageWithSymbolConfiguration:current_posts_chevron_configuration] ?: current_posts_chevron_image;
	current_posts_hostname_button.placeholderImage = [[NSImage alloc] initWithSize:NSMakeSize(10.0, 10.0)];
	current_posts_hostname_button.image = current_posts_hostname_button.placeholderImage;
	[current_posts_hostname_button setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
	[current_posts_hostname_button setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

	NSButton* clear_button = [NSButton buttonWithTitle:@"Clear" target:self action:@selector(clearSpecialModeAction:)];
	clear_button.translatesAutoresizingMaskIntoConstraints = NO;
	clear_button.bezelStyle = NSBezelStyleRounded;
	clear_button.controlSize = NSControlSizeSmall;
	clear_button.font = [NSFont systemFontOfSize:13.0];
	[clear_button setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
	[clear_button setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
	clear_button.hidden = YES;

	[recap_box addSubview:bookmarks_label];
	[recap_box addSubview:current_posts_label];
	[recap_box addSubview:current_posts_hostname_button];
	[recap_box addSubview:clear_button];

	__weak typeof(self) weak_self = self;
	MBPodcastController* podcast_controller = [[MBPodcastController alloc] init];
	[self addChildViewController:podcast_controller];
	podcast_controller.playbackStateChangedHandler = ^(BOOL is_playing) {
		MBSidebarController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		MBEntry* selected_item = [strong_self selectedItem];
		BOOL has_selected_audio_enclosure = [selected_item hasAudioEnclosure];
		BOOL is_current_podcast_selected = (has_selected_audio_enclosure && strong_self.currentPodcastEntry != nil && strong_self.currentPodcastEntry.entryID == selected_item.entryID);
		strong_self.keepsPausedPodcastPaneVisibleUntilSelectionChange = (!is_playing && strong_self.currentPodcastEntry != nil && !is_current_podcast_selected);
		[strong_self updatePodcastPaneForSelectedItem:selected_item];
	};
	podcast_controller.paneHeightChangedHandler = ^(CGFloat preferred_height) {
		#pragma unused(preferred_height)
		MBSidebarController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		[strong_self updatePodcastPaneHeightAnimated:YES];
	};

	NSView* podcast_view = podcast_controller.view;
	podcast_view.translatesAutoresizingMaskIntoConstraints = NO;

	NSView* podcast_clip_view = [[NSView alloc] initWithFrame:NSZeroRect];
	podcast_clip_view.translatesAutoresizingMaskIntoConstraints = NO;
	podcast_clip_view.hidden = YES;
	podcast_clip_view.alphaValue = 0.0;
	podcast_clip_view.wantsLayer = YES;
	podcast_clip_view.layer.masksToBounds = YES;

	MBSidebarTableView *table_view = [[MBSidebarTableView alloc] initWithFrame:NSZeroRect];
	table_view.translatesAutoresizingMaskIntoConstraints = NO;
	table_view.delegate = self;
	table_view.dataSource = self;
	table_view.target = self;
	table_view.doubleAction = @selector(performDoubleClickedSidebarItemAction:);
	table_view.headerView = nil;
	table_view.allowsEmptySelection = YES;
	table_view.intercellSpacing = NSMakeSize(0.0, 5.0);
	table_view.style = NSTableViewStyleSourceList;
	table_view.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
	table_view.primaryActionHandler = ^BOOL {
		return [weak_self performPrimaryActionForSelectedItem];
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
	table_view.moveSelectionFromRememberedRowHandler = ^BOOL(NSInteger direction) {
		MBSidebarController* strong_self = weak_self;
		if (strong_self == nil) {
			return NO;
		}

		return [strong_self moveSelectionFromRememberedRow:direction];
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
	[container_view addSubview:podcast_clip_view];
	[container_view addSubview:premium_required_view];
	NSLayoutConstraint* recap_height_constraint = [recap_box.heightAnchor constraintEqualToConstant:0.0];
	NSLayoutConstraint* recap_to_table_top_constraint = [scroll_view.topAnchor constraintEqualToAnchor:recap_box.bottomAnchor constant:0.0];
	NSLayoutConstraint* podcast_height_constraint = [podcast_clip_view.heightAnchor constraintEqualToConstant:0.0];
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
			[current_posts_label.leadingAnchor constraintEqualToAnchor:recap_box.leadingAnchor constant:12.0],
			[current_posts_label.centerYAnchor constraintEqualToAnchor:recap_box.centerYAnchor],
			[current_posts_hostname_button.leadingAnchor constraintEqualToAnchor:current_posts_label.trailingAnchor constant:4.0],
			[current_posts_hostname_button.centerYAnchor constraintEqualToAnchor:recap_box.centerYAnchor],
			[current_posts_hostname_button.trailingAnchor constraintLessThanOrEqualToAnchor:clear_button.leadingAnchor constant:-12.0],
			[clear_button.trailingAnchor constraintEqualToAnchor:recap_box.trailingAnchor constant:-12.0],
			[clear_button.centerYAnchor constraintEqualToAnchor:recap_box.centerYAnchor],
		recap_to_table_top_constraint,
		[scroll_view.bottomAnchor constraintEqualToAnchor:podcast_clip_view.topAnchor],
		[scroll_view.leadingAnchor constraintEqualToAnchor:container_view.leadingAnchor],
		[scroll_view.trailingAnchor constraintEqualToAnchor:container_view.trailingAnchor],
		[podcast_clip_view.leadingAnchor constraintEqualToAnchor:container_view.leadingAnchor],
		[podcast_clip_view.trailingAnchor constraintEqualToAnchor:container_view.trailingAnchor],
		[podcast_clip_view.bottomAnchor constraintEqualToAnchor:container_view.bottomAnchor],
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

	[podcast_clip_view addSubview:podcast_view];
	[NSLayoutConstraint activateConstraints:@[
		[podcast_view.leadingAnchor constraintEqualToAnchor:podcast_clip_view.leadingAnchor],
		[podcast_view.trailingAnchor constraintEqualToAnchor:podcast_clip_view.trailingAnchor],
		[podcast_view.topAnchor constraintEqualToAnchor:podcast_clip_view.topAnchor],
	]];

	self.recapBoxView = recap_box;
	self.recapButton = recap_button;
	self.recapCountLabel = recap_label;
	self.bookmarksTitleLabel = bookmarks_label;
	self.currentPostsTitleLabel = current_posts_label;
	self.currentPostsHostnameButton = current_posts_hostname_button;
	self.bookmarksClearButton = clear_button;
	self.recapBoxHeightConstraint = recap_height_constraint;
	self.recapToTableTopConstraint = recap_to_table_top_constraint;
	self.podcastController = podcast_controller;
	self.podcastContainerView = podcast_clip_view;
	self.podcastContentView = podcast_view;
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
					if (!self.hasFadingEntryIDsCache) {
						[self updateFadingEntryIDsFromCurrentItemsIsFinished:NO preserveCachedValueDuringFetch:NO];
					}
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
	[self clearRememberedDeselectedRow];

	if (self.contentMode == MBSidebarContentModeBookmarks) {
		[self fetchBookmarks];
		return;
	}
	if (self.contentMode == MBSidebarContentModeMentions) {
		[self fetchMentions];
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

- (void) showMentions
{
	if (self.client == nil || self.token.length == 0) {
		return;
	}

	[self clearRememberedDeselectedRow];

	BOOL was_showing_special_mode = [self isShowingSpecialMode];
	if (self.contentMode != MBSidebarContentModeMentions) {
		[self clearPreservedHiddenReadState];
		[self resetBookmarksModeState];
		[self resetAllPostsModeState];
		self.contentMode = MBSidebarContentModeMentions;
	}

	[self applyFiltersAndReload];
	[self ensureSpecialModeSelectionIfNeeded];
	[self fetchMentions];
	if (!was_showing_special_mode && self.specialModeChangedHandler != nil) {
		self.specialModeChangedHandler(YES);
	}
}

- (void) showBookmarks
{
	if (self.client == nil || self.token.length == 0) {
		return;
	}

	[self clearRememberedDeselectedRow];

	BOOL was_showing_special_mode = [self isShowingSpecialMode];
	if (self.contentMode != MBSidebarContentModeBookmarks) {
		[self clearPreservedHiddenReadState];
		[self resetMentionsModeState];
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

	[self showAllPostsForFeedID:selected_item.feedID siteName:[self siteNameForEntry:selected_item] feedHost:[self feedHostForEntry:selected_item]];
}

- (void) showAllPostsForFeedID:(NSInteger)feedID siteName:(NSString *)siteName feedHost:(NSString *)feedHost
{
	[self showAllPostsForFeedID:feedID siteName:siteName feedHost:feedHost usesCurrentDestination:NO postStatus:@""];
}

- (void) showCurrentUserPostsForFeedID:(NSInteger)feedID siteName:(NSString *)siteName feedHost:(NSString *)feedHost
{
	[self showAllPostsForFeedID:feedID siteName:siteName feedHost:feedHost usesCurrentDestination:YES postStatus:@""];
}

- (void) showCurrentUserDraftsForFeedID:(NSInteger)feedID siteName:(NSString *)siteName feedHost:(NSString *)feedHost
{
	[self showAllPostsForFeedID:feedID siteName:siteName feedHost:feedHost usesCurrentDestination:YES postStatus:InkwellPostStatusDraft];
}

- (void) showCurrentPostsForSubscription:(MBSubscription *)subscription
{
	if (subscription == nil || subscription.feedID <= 0) {
		return;
	}

	NSString* site_name = [subscription.title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	NSString* feed_host = [self normalizedHostFromURLString:subscription.siteURL ?: @""];
	if (feed_host.length == 0) {
		feed_host = [self normalizedHostFromURLString:subscription.feedURL ?: @""];
	}
	if (site_name.length == 0) {
		site_name = feed_host;
	}

	if ([self.allPostsPostStatus isEqualToString:InkwellPostStatusDraft]) {
		[self showCurrentUserDraftsForFeedID:subscription.feedID siteName:site_name feedHost:feed_host];
	}
	else {
		[self showCurrentUserPostsForFeedID:subscription.feedID siteName:site_name feedHost:feed_host];
	}
}

- (void) showAllPostsForFeedID:(NSInteger)feedID siteName:(NSString *)siteName feedHost:(NSString *)feedHost usesCurrentDestination:(BOOL)uses_current_destination postStatus:(NSString *)post_status
{
	if (self.client == nil || self.token.length == 0 || feedID <= 0) {
		return;
	}

	[self clearRememberedDeselectedRow];

	BOOL was_showing_special_mode = [self isShowingSpecialMode];
	if (self.contentMode != MBSidebarContentModeAllPosts) {
		[self clearPreservedHiddenReadState];
		[self resetBookmarksModeState];
		[self resetMentionsModeState];
		self.contentMode = MBSidebarContentModeAllPosts;
	}

	self.allPostsFeedID = feedID;
	self.allPostsSiteName = siteName ?: @"";
	self.allPostsFeedHost = feedHost ?: @"";
	self.allPostsUsesCurrentDestination = uses_current_destination;
	self.allPostsDestinationUID = uses_current_destination ? [self currentDestinationUID] : @"";
	self.allPostsPostStatus = [post_status stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	self.allPostsItems = uses_current_destination ? @[] : [self cachedItemsForFeedID:feedID];
	[self applyFiltersAndReload];
	[self ensureSpecialModeSelectionIfNeeded];
	[self fetchAllPosts];
	if (!was_showing_special_mode && self.specialModeChangedHandler != nil) {
		self.specialModeChangedHandler(YES);
	}
}

- (void) reloadCurrentPostsFromServer
{
	if (self.contentMode != MBSidebarContentModeAllPosts || !self.allPostsUsesCurrentDestination) {
		return;
	}

	self.isFetchingAllPosts = NO;
	self.allPostsRequestIdentifier += 1;
	[self fetchAllPosts];
}

- (void) clearSpecialMode
{
	if (self.contentMode == MBSidebarContentModeFeeds) {
		return;
	}

	[self clearRememberedDeselectedRow];

	NSInteger preferred_entry_id = [self savedSelectedEntryID];
	[self clearPreservedHiddenReadState];
	[self resetBookmarksModeState];
	[self resetMentionsModeState];
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
	if (self.contentMode == MBSidebarContentModeBookmarks || self.contentMode == MBSidebarContentModeMentions) {
		return NO;
	}

	MBEntry* selected_item = [self selectedItem];
	return (selected_item != nil && selected_item.entryID > 0 && !selected_item.isBookmarkEntry && !selected_item.isDraft && self.client != nil && self.token.length > 0);
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
	if (self.contentMode == MBSidebarContentModeMentions) {
		return NO;
	}

	MBEntry* selected_item = [self selectedItem];
	return (selected_item != nil && selected_item.entryID > 0 && !selected_item.isDraft && self.client != nil && self.token.length > 0);
}

- (BOOL) canReplyToSelectedMention
{
	return [self canReplyToMention:[self selectedMention]];
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
	[self clearRememberedDeselectedRow];
	if (self.hideReadPosts) {
		self.preservedVisibleEntryIDsForHiddenReadPosts = nil;
	}
	else {
		[self clearPreservedHiddenReadState];
	}

	[self applyFiltersAndReload];
}

- (void) replyToSelectedMention
{
	MBMention* mention = [self selectedMention];
	if (![self canReplyToMention:mention]) {
		return;
	}

	if (self.replyController != nil) {
		return;
	}

	NSString* prefill_text = [self prefillTextForUsername:mention.username];
	[self presentReplyControllerWithPostID:mention.postID prefillText:prefill_text];
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
	if (![NSThread isMainThread]) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self setPodcastPaneVisible:is_visible];
		});
		return;
	}

	if (self.podcastContainerView == nil || self.podcastHeightConstraint == nil) {
		return;
	}

	if (self.podcastPaneDisplayed == is_visible && self.podcastContainerView.hidden == !is_visible) {
		return;
	}

	self.podcastPaneDisplayed = is_visible;
	if (is_visible) {
		self.podcastContainerView.hidden = NO;
		if (self.podcastContentView.layer != nil) {
			self.podcastContentView.layer.transform = CATransform3DMakeTranslation(0.0, -InkwellSidebarPodcastPaneAnimationOffset, 0.0);
		}
	}

	[self.view layoutSubtreeIfNeeded];
	[NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
		context.duration = 0.18;
		context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
		context.allowsImplicitAnimation = YES;
		self.podcastHeightConstraint.constant = is_visible ? self.podcastController.preferredPaneHeight : 0.0;
		self.podcastContainerView.alphaValue = is_visible ? 1.0 : 0.0;
		if (self.podcastContentView.layer != nil) {
			self.podcastContentView.layer.transform = is_visible ? CATransform3DIdentity : CATransform3DMakeTranslation(0.0, -InkwellSidebarPodcastPaneAnimationOffset, 0.0);
		}
		[self.view layoutSubtreeIfNeeded];
	} completionHandler:^{
		if (!self.podcastPaneDisplayed) {
			self.podcastContainerView.hidden = YES;
		}
		else {
			if (self.podcastContentView.layer != nil) {
				self.podcastContentView.layer.transform = CATransform3DIdentity;
			}
			[self.podcastContainerView setNeedsLayout:YES];
			[self.podcastContainerView layoutSubtreeIfNeeded];
			[self.podcastContainerView setNeedsDisplay:YES];
		}
	}];
}

- (void) updatePodcastPaneHeightAnimated:(BOOL) animated
{
	if (![NSThread isMainThread]) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self updatePodcastPaneHeightAnimated:animated];
		});
		return;
	}

	if (!self.podcastPaneDisplayed || self.podcastContainerView == nil || self.podcastHeightConstraint == nil) {
		return;
	}

	CGFloat target_height = self.podcastController.preferredPaneHeight;
	if (fabs(self.podcastHeightConstraint.constant - target_height) < DBL_EPSILON) {
		return;
	}

	if (!animated) {
		self.podcastHeightConstraint.constant = target_height;
		[self.view layoutSubtreeIfNeeded];
		return;
	}

	[self.view layoutSubtreeIfNeeded];
	[NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
		context.duration = 0.18;
		context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
		context.allowsImplicitAnimation = YES;
		self.podcastHeightConstraint.constant = target_height;
		[self.view layoutSubtreeIfNeeded];
	} completionHandler:nil];
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

	if (self.keepsPausedPodcastPaneVisibleUntilSelectionChange) {
		if (self.currentPodcastEntry != nil) {
			self.podcastController.entry = self.currentPodcastEntry;
			self.podcastController.artworkURLString = [self podcastArtworkURLStringForEntry:self.currentPodcastEntry];
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
	if (did_restore_selection && current_selected_row < 0) {
		current_selected_row = [self rowForEntryID:entry_id];
	}
	[self refreshSelectionStylingForSelectedRow:current_selected_row];
	if (did_restore_selection) {
		[self restoreSelectionForEntryIDOnNextRunLoop:entry_id];
	}
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
	BOOL preserve_cached_fading_value_during_fetch = self.hasFadingEntryIDsCache;
	NSMutableSet* existing_entry_ids = [NSMutableSet set];
	for (MBEntry* item in self.allItems ?: @[]) {
		if (item.entryID > 0) {
			[existing_entry_ids addObject:@(item.entryID)];
		}
	}
	[self.client fetchFeedEntriesWithToken:self.token existingEntryIDs:existing_entry_ids completion:^(NSArray<MBSubscription *> * _Nullable subscriptions, NSArray<NSDictionary<NSString *,id> *> * _Nullable entries, NSSet * _Nullable unread_entry_ids, BOOL is_finished, NSError * _Nullable error) {
		if (is_finished) {
			self.isFetching = NO;
			[self updateRecapUI];
		}

		if (error != nil) {
			return;
		}

		NSArray<MBEntry *> *fetched_sidebar_items = [self sidebarItemsForEntries:entries ?: @[] subscriptions:subscriptions ?: @[] unreadEntryIDs:unread_entry_ids];
		NSArray<MBEntry *> *sidebar_items = [self sidebarItemsByMergingFetchedItems:fetched_sidebar_items withExistingItems:self.allItems ?: @[] unreadEntryIDs:unread_entry_ids];
		self.hasLoadedRemoteItems = YES;
		self.allItems = sidebar_items;
		[self updateFadingEntryIDsFromCurrentItemsIsFinished:is_finished preserveCachedValueDuringFetch:preserve_cached_fading_value_during_fetch];
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

- (void) fetchMentions
{
	if (self.client == nil || self.token.length == 0 || self.isFetchingMentions) {
		return;
	}

	self.isFetchingMentions = YES;
	self.mentionsRequestIdentifier += 1;
	NSInteger request_identifier = self.mentionsRequestIdentifier;
	__weak typeof(self) weak_self = self;
	[self.client fetchRecentMentionsWithToken:self.token completion:^(NSArray* _Nullable items, NSError* _Nullable error) {
		MBSidebarController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		if (request_identifier != strong_self.mentionsRequestIdentifier) {
			return;
		}

		strong_self.isFetchingMentions = NO;
		if (error != nil || strong_self.contentMode != MBSidebarContentModeMentions) {
			return;
		}

		strong_self.mentions = [strong_self mentionsFromItems:items ?: @[]];
		strong_self.mentionItems = [strong_self sidebarItemsForMentions:strong_self.mentions];
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
	NSString* post_status = [self.allPostsPostStatus copy];
	NSString* destination_uid = [self.allPostsDestinationUID copy];
	__weak typeof(self) weak_self = self;
	if (self.allPostsUsesCurrentDestination) {
		void (^completion)(NSArray* _Nullable entries, NSError* _Nullable error) = ^(NSArray* _Nullable entries, NSError* _Nullable error) {
			MBSidebarController* strong_self = weak_self;
			if (strong_self == nil) {
				return;
			}

			if (request_identifier != strong_self.allPostsRequestIdentifier) {
				return;
			}

			strong_self.isFetchingAllPosts = NO;

			if (error != nil || strong_self.contentMode != MBSidebarContentModeAllPosts || strong_self.allPostsFeedID <= 0) {
				return;
			}

			strong_self.allPostsItems = [strong_self sidebarItemsForEntries:entries ?: @[] subscriptionTitle:site_name feedHost:feed_host unreadEntryIDs:nil];
			[strong_self applyFiltersAndReload];
			[strong_self ensureSpecialModeSelectionIfNeeded];
		};

		if ([post_status isEqualToString:InkwellPostStatusDraft]) {
			[self.client fetchDraftEntriesForDestinationUID:destination_uid token:self.token completion:completion];
		}
		else {
			[self.client fetchPostEntriesForDestinationUID:destination_uid token:self.token completion:completion];
		}
		return;
	}

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
	if (self.contentMode != MBSidebarContentModeAllPosts || self.tableView == nil) {
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

- (void) resetMentionsModeState
{
	self.isFetchingMentions = NO;
	self.mentionsRequestIdentifier += 1;
}

- (void) resetAllPostsModeState
{
	self.isFetchingAllPosts = NO;
	self.allPostsRequestIdentifier += 1;
	self.allPostsItems = @[];
	self.allPostsFeedID = 0;
	self.allPostsSiteName = @"";
	self.allPostsFeedHost = @"";
	self.allPostsUsesCurrentDestination = NO;
	self.allPostsDestinationUID = @"";
	self.allPostsPostStatus = @"";
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

- (NSURL* _Nullable) fadingEntryIDsCacheURL
{
	return [MBPathUtilities appFileURLForSearchPathDirectory:NSCachesDirectory filename:InkwellFadingEntryIDsCacheFilename createDirectoryIfNeeded:YES];
}

- (NSURL* _Nullable) selectedEntryCacheURL
{
	return [MBPathUtilities appFileURLForSearchPathDirectory:NSCachesDirectory filename:InkwellSidebarSelectedEntryCacheFilename createDirectoryIfNeeded:YES];
}

- (NSArray*) loadCachedFadingEntryIDs
{
	NSURL* cache_url = [self fadingEntryIDsCacheURL];
	if (cache_url == nil) {
		return @[];
	}

	NSData* data = [NSData dataWithContentsOfURL:cache_url options:0 error:nil];
	if (data.length == 0) {
		return @[];
	}

	id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
	if (![payload isKindOfClass:[NSArray class]]) {
		return @[];
	}

	return [self normalizedFadingEntryIDsFromObjects:(NSArray*) payload];
}

- (void) cacheFadingEntryIDs:(NSArray*) entry_ids
{
	NSURL* cache_url = [self fadingEntryIDsCacheURL];
	if (cache_url == nil) {
		return;
	}

	NSArray* normalized_entry_ids = [self normalizedFadingEntryIDsFromObjects:(entry_ids ?: @[])];
	NSData* data = [NSJSONSerialization dataWithJSONObject:normalized_entry_ids options:0 error:nil];
	if (data.length == 0) {
		return;
	}

	if ([data writeToURL:cache_url atomically:YES]) {
		self.hasFadingEntryIDsCache = YES;
	}
}

- (NSArray*) normalizedFadingEntryIDsFromObjects:(NSArray*) objects
{
	NSMutableArray* normalized_entry_ids = [NSMutableArray array];
	NSMutableSet* seen_entry_ids = [NSMutableSet set];
	for (id object in objects ?: @[]) {
		NSInteger entry_id = [self integerValueFromObject:object];
		if (entry_id <= 0) {
			continue;
		}

		NSNumber* entry_id_value = @(entry_id);
		if ([seen_entry_ids containsObject:entry_id_value]) {
			continue;
		}

		[seen_entry_ids addObject:entry_id_value];
		[normalized_entry_ids addObject:entry_id_value];
	}

	return [normalized_entry_ids copy];
}

- (void) updateFadingEntryIDsFromCurrentItemsIsFinished:(BOOL) is_finished preserveCachedValueDuringFetch:(BOOL) preserve_cached_value_during_fetch
{
	NSArray* current_entry_ids = [self normalizedFadingEntryIDsFromObjects:[self allFadingEntryIDs]];
	BOOL should_update_visible_entry_ids = (is_finished || !preserve_cached_value_during_fetch);
	if (should_update_visible_entry_ids) {
		self.fadingEntryIDs = current_entry_ids;
	}

	if (should_update_visible_entry_ids && (current_entry_ids.count > 0 || is_finished || self.hasFadingEntryIDsCache)) {
		[self cacheFadingEntryIDs:current_entry_ids];
	}
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

- (NSImage*) avatarImageForMention:(MBMention*) mention
{
	NSString* avatar_url = [mention.avatarURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (avatar_url.length == 0) {
		return [self fallbackAvatarImage];
	}

	NSImage* cached_image = [self.avatarLoader cachedImageForURLString:avatar_url];
	if (cached_image != nil) {
		return cached_image;
	}

	[self.avatarLoader loadImageForURLString:avatar_url];
	return [self fallbackAvatarImage];
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
	if (selected_entry_id <= 0 && preferred_entry_id > 0) {
		selected_entry_id = preferred_entry_id;
	}

	BOOL is_searching = (self.contentMode == MBSidebarContentModeFeeds && self.searchQuery.length > 0);
	NSArray* filtered_items = nil;
	if (self.contentMode == MBSidebarContentModeBookmarks) {
		filtered_items = [self.bookmarkItems copy];
	}
	else if (self.contentMode == MBSidebarContentModeMentions) {
		filtered_items = [self.mentionItems copy];
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
	NSArray* sorted_items = (self.contentMode == MBSidebarContentModeMentions) ? (filtered_items ?: @[]) : [self sortedItems:(filtered_items ?: @[])];
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
	if (self.contentMode == MBSidebarContentModeBookmarks || self.contentMode == MBSidebarContentModeMentions) {
		return 0;
	}

	MBEntry* selected_item = [self selectedItem];
	if (selected_item != nil && selected_item.entryID > 0 && !selected_item.isBookmarkEntry) {
		return selected_item.entryID;
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

- (void) restoreSelectionForEntryIDOnNextRunLoop:(NSInteger) entry_id
{
	if (entry_id <= 0 || self.tableView == nil) {
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		NSInteger row = [self rowForEntryID:entry_id];
		if (row < 0 || row >= self.items.count) {
			return;
		}

		NSIndexSet* index_set = [NSIndexSet indexSetWithIndex:(NSUInteger) row];
		if (![self.tableView isRowSelected:row]) {
			self.isPreservingSelectionDuringReload = YES;
			[self.tableView selectRowIndexes:index_set byExtendingSelection:NO];
			self.isPreservingSelectionDuringReload = NO;
		}

		self.selectedRowForStyling = row;
		[self refreshSelectionStylingForSelectedRow:row];
	});
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
	if (self.contentMode == MBSidebarContentModeBookmarks || self.contentMode == MBSidebarContentModeMentions) {
		row_view.customBackgroundColor = nil;
		row_view.customBorderColor = nil;
		return;
	}

	if ([self entryShowsReadState:item]) {
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

- (void) clearRememberedDeselectedRow
{
	self.rememberedDeselectedRow = -1;
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
	BOOL should_show_current_posts_banner = [self shouldShowCurrentPostsBanner];
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

	NSInteger fading_count = self.fadingEntryIDs.count;
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
		self.bookmarksTitleLabel.hidden = (!should_show_special_mode || should_show_current_posts_banner);
		self.bookmarksTitleLabel.stringValue = (should_show_special_mode && !should_show_current_posts_banner) ? [self specialModeBannerTitle] : @"";
	}
	if (self.currentPostsTitleLabel != nil) {
		self.currentPostsTitleLabel.hidden = !should_show_current_posts_banner;
		self.currentPostsTitleLabel.stringValue = [self.allPostsPostStatus isEqualToString:InkwellPostStatusDraft] ? @"Showing drafts:" : @"Showing posts:";
	}
	if (self.currentPostsHostnameButton != nil) {
		self.currentPostsHostnameButton.hidden = !should_show_current_posts_banner;
		self.currentPostsHostnameButton.image = self.currentPostsHostnameButton.placeholderImage;
		if (should_show_current_posts_banner) {
			[self updateCurrentPostsHostnameButton];
		}
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

	BOOL has_fading_entry_ids = (self.fadingEntryIDs.count > 0);
	if (!has_fading_entry_ids) {
		return NO;
	}

	if (!self.hasLoadedRemoteItems || self.isFetching) {
		return self.hasFadingEntryIDsCache;
	}

	return YES;
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

- (BOOL) shouldShowCurrentPostsBanner
{
	if (self.contentMode != MBSidebarContentModeAllPosts || !self.allPostsUsesCurrentDestination) {
		return NO;
	}

	return ([self currentDestinationDisplayName].length > 0);
}

- (MBMention* _Nullable) selectedMention
{
	if (self.contentMode != MBSidebarContentModeMentions) {
		return nil;
	}

	NSInteger selected_row = self.tableView.selectedRow;
	if (selected_row < 0 || selected_row >= self.mentions.count) {
		return nil;
	}

	id object = self.mentions[(NSUInteger) selected_row];
	if (![object isKindOfClass:[MBMention class]]) {
		return nil;
	}

	return (MBMention*) object;
}

- (BOOL) canReplyToMention:(MBMention*) mention
{
	if (![mention isKindOfClass:[MBMention class]]) {
		return NO;
	}

	NSString* post_id = [mention.postID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	NSString* username = [mention.username stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	return (self.client != nil && self.token.length > 0 && post_id.length > 0 && username.length > 0);
}

- (NSString*) prefillTextForUsername:(NSString*) username
{
	NSString* normalized_username = [username stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (normalized_username.length == 0) {
		return @"";
	}

	return [NSString stringWithFormat:@"@%@ ", normalized_username];
}

- (void) presentReplyControllerWithPostID:(NSString*) post_id prefillText:(NSString*) prefill_text
{
	if (self.view.window == nil || self.replyController != nil) {
		return;
	}

	MBReplyController* reply_controller = [[MBReplyController alloc] initWithClient:self.client token:self.token];
	__weak typeof(self) weak_self = self;
	reply_controller.didCloseHandler = ^{
		MBSidebarController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		strong_self.replyController = nil;
	};
	self.replyController = reply_controller;
	[self.replyController showForWindow:self.view.window postID:post_id prefillText:prefill_text];
}

- (NSString*) specialModeBannerTitle
{
	if (self.contentMode == MBSidebarContentModeBookmarks) {
		return @"Showing recent bookmarks";
	}

	if (self.contentMode == MBSidebarContentModeMentions) {
		return @"Showing mentions";
	}

	NSString* site_name = [self.allPostsSiteName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (site_name.length == 0) {
		site_name = @"this site";
	}

	return [NSString stringWithFormat:@"Showing posts from %@", site_name];
}

- (NSString *) currentDestinationDisplayName
{
	NSString* current_destination = [self currentDestinationUID];
	if (current_destination.length == 0) {
		return @"";
	}

	for (id object in [self.client cachedMicropubDestinations] ?: @[]) {
		if (![object isKindOfClass:[NSDictionary class]]) {
			continue;
		}

		NSDictionary* destination = (NSDictionary*) object;
		NSString* destination_uid = [self stringValueFromObjectOrNumber:destination[@"uid"]];
		destination_uid = [destination_uid stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		if (![destination_uid isEqualToString:current_destination]) {
			continue;
		}

		NSString* destination_name = [self stringValueFromObjectOrNumber:destination[@"name"]];
		destination_name = [destination_name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		if (destination_name.length > 0) {
			return destination_name;
		}
	}

	return [self hostFromURLString:current_destination];
}

- (NSString *) currentDestinationUID
{
	NSString* current_destination = [[NSUserDefaults standardUserDefaults] stringForKey:InkwellCurrentDestinationDefaultsKey] ?: @"";
	return [current_destination stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

- (NSString *) hostFromURLString:(NSString *) string
{
	NSString* trimmed_string = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (trimmed_string.length == 0) {
		return @"";
	}

	NSURLComponents* components = [NSURLComponents componentsWithString:trimmed_string];
	NSString* host_value = components.host ?: @"";
	if (host_value.length == 0) {
		NSString* possible_url_string = [NSString stringWithFormat:@"https://%@", trimmed_string];
		NSURLComponents* host_only_components = [NSURLComponents componentsWithString:possible_url_string];
		host_value = host_only_components.host ?: @"";
	}

	return [[host_value lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

- (void) showCurrentDestinationsMenuFromView:(NSView *)view event:(NSEvent *)event
{
	NSArray* destinations = [self.client cachedMicropubDestinations] ?: @[];
	if (destinations.count == 0) {
		return;
	}

	NSString* current_destination_uid = [self currentDestinationUID];
	NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Blogs"];
	for (id object in destinations) {
		if (![object isKindOfClass:[NSDictionary class]]) {
			continue;
		}

		NSDictionary* destination = (NSDictionary*) object;
		NSString* name = [self stringValueFromObjectOrNumber:destination[@"name"]];
		if (name.length == 0) {
			continue;
		}

		NSMenuItem* menu_item = [[NSMenuItem alloc] initWithTitle:name action:@selector(selectCurrentDestinationFromMenuItem:) keyEquivalent:@""];
		menu_item.target = self;
		menu_item.representedObject = destination;

		NSString* uid = [self stringValueFromObjectOrNumber:destination[@"uid"]];
		if (uid.length > 0 && [uid isEqualToString:current_destination_uid]) {
			menu_item.state = NSControlStateValueOn;
		}

		[menu addItem:menu_item];
	}

	if (menu.numberOfItems == 0) {
		return;
	}

	[NSMenu popUpContextMenu:menu withEvent:event forView:view];
}

- (void) updateCurrentPostsHostnameButton
{
	NSString* hostname = [self currentDestinationDisplayName];
	if (hostname.length == 0 || self.currentPostsHostnameButton == nil) {
		return;
	}

	NSFont* font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
	NSDictionary* attributes = @{
		NSFontAttributeName: font,
		NSForegroundColorAttributeName: [NSColor labelColor]
	};
	self.currentPostsHostnameButton.attributedTitle = [[NSAttributedString alloc] initWithString:hostname attributes:attributes];
}

- (MBSubscription *) subscriptionMatchingDestination:(NSDictionary *)destination subscriptions:(NSArray *)subscriptions normalizeHosts:(BOOL)normalize_hosts
{
	NSString* destination_uid = [self stringValueFromObjectOrNumber:destination[@"uid"]];
	NSString* destination_name = [self stringValueFromObjectOrNumber:destination[@"name"]];
	for (MBSubscription* subscription in subscriptions ?: @[]) {
		if (subscription.feedID <= 0) {
			continue;
		}
		if ([self destinationUID:destination_uid destinationName:destination_name matchesSubscription:subscription normalizeHosts:normalize_hosts]) {
			return subscription;
		}
	}

	return nil;
}

- (BOOL) destinationUID:(NSString *)destinationUID destinationName:(NSString *)destinationName matchesSubscription:(MBSubscription *)subscription normalizeHosts:(BOOL)normalize_hosts
{
	NSArray* destination_hosts = nil;
	if (normalize_hosts) {
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
		NSString* subscription_host = normalize_hosts ? [self normalizedHostFromURLString:url_string] : [self hostFromURLString:url_string];
		if ([self host:subscription_host matchesDestinationHosts:destination_hosts]) {
			return YES;
		}
	}

	return NO;
}

- (BOOL) host:(NSString *)host matchesDestinationHosts:(NSArray *)destination_hosts
{
	if (host.length == 0) {
		return NO;
	}

	for (NSString* destination_host in destination_hosts) {
		if (destination_host.length == 0) {
			continue;
		}
		if ([host isEqualToString:destination_host]) {
			return YES;
		}
	}

	return NO;
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

	NSArray* entry_ids = [self.fadingEntryIDs copy];
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

- (IBAction) currentPostsHostnameAction:(id)sender
{
	if (![sender isKindOfClass:[NSView class]]) {
		return;
	}

	NSEvent* event = [NSApp currentEvent];
	if (event == nil) {
		return;
	}

	[self showCurrentDestinationsMenuFromView:(NSView*) sender event:event];
}

- (IBAction) selectCurrentDestinationFromMenuItem:(id)sender
{
	if (![sender isKindOfClass:[NSMenuItem class]]) {
		return;
	}

	NSMenuItem* menu_item = (NSMenuItem*) sender;
	id represented_object = menu_item.representedObject;
	if (![represented_object isKindOfClass:[NSDictionary class]]) {
		return;
	}

	NSDictionary* destination = (NSDictionary*) represented_object;
	NSString* destination_uid = [self stringValueFromObjectOrNumber:destination[@"uid"]];
	if (destination_uid.length == 0) {
		return;
	}

	[[NSUserDefaults standardUserDefaults] setObject:destination_uid forKey:InkwellCurrentDestinationDefaultsKey];
	[self updateCurrentPostsHostnameButton];

	NSArray* subscriptions = [self.client cachedFeedSubscriptions] ?: @[];
	MBSubscription* subscription = [self subscriptionMatchingDestination:destination subscriptions:subscriptions normalizeHosts:NO];
	if (subscription == nil) {
		subscription = [self subscriptionMatchingDestination:destination subscriptions:subscriptions normalizeHosts:YES];
	}
	if (subscription == nil) {
		return;
	}

	[self showCurrentPostsForSubscription:subscription];
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
//				NSLog(@"Reading Recap HTML: %@", html ?: @"");
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

- (NSArray<MBEntry *> *) sidebarItemsByMergingFetchedItems:(NSArray<MBEntry *> *) fetched_items withExistingItems:(NSArray<MBEntry *> *) existing_items unreadEntryIDs:(NSSet* _Nullable) unread_entry_ids
{
	NSMutableArray<MBEntry *> *merged_items = [NSMutableArray array];
	NSMutableSet* fetched_entry_ids = [NSMutableSet set];
	NSDate* oldest_fetched_date = nil;
	for (MBEntry* item in fetched_items ?: @[]) {
		if (![item isKindOfClass:[MBEntry class]]) {
			continue;
		}

		if (item.entryID > 0) {
			[fetched_entry_ids addObject:@(item.entryID)];
		}
		if (item.date != nil && (oldest_fetched_date == nil || [item.date compare:oldest_fetched_date] == NSOrderedAscending)) {
			oldest_fetched_date = item.date;
		}
		[merged_items addObject:item];
	}

	for (MBEntry* item in existing_items ?: @[]) {
		if (![item isKindOfClass:[MBEntry class]]) {
			continue;
		}

		if (item.entryID > 0 && [fetched_entry_ids containsObject:@(item.entryID)]) {
			continue;
		}

		if (![self shouldPreserveExistingSidebarItemDuringRefresh:item oldestFetchedDate:oldest_fetched_date]) {
			continue;
		}

		if (unread_entry_ids != nil && item.entryID > 0) {
			item.isRead = ![unread_entry_ids containsObject:@(item.entryID)];
		}

		[merged_items addObject:item];
	}

	return [merged_items copy];
}

- (BOOL) shouldPreserveExistingSidebarItemDuringRefresh:(MBEntry*) item oldestFetchedDate:(NSDate* _Nullable) oldest_fetched_date
{
	if (![item isKindOfClass:[MBEntry class]] || item.entryID <= 0 || item.date == nil) {
		return NO;
	}

	if (oldest_fetched_date == nil || [item.date compare:oldest_fetched_date] == NSOrderedDescending) {
		return NO;
	}

	NSDate* cutoff_date = [[NSDate date] dateByAddingTimeInterval:-InkwellSidebarEntriesLookbackInterval];
	return ([item.date compare:cutoff_date] != NSOrderedAscending);
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
	sidebar_entry.isDraft = [self boolValueFromObject:entry[@"is_draft"]];

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

- (NSArray*) mentionsFromItems:(NSArray*) items
{
	NSMutableArray* mentions = [NSMutableArray array];
	for (id object in items ?: @[]) {
		if (![object isKindOfClass:[NSDictionary class]]) {
			continue;
		}

		NSDictionary* item = (NSDictionary*) object;
		NSDictionary* author = [self dictionaryValueFromObject:item[@"author"]];
		NSDictionary* microblog = [self dictionaryValueFromObject:author[@"_microblog"]];
		if (microblog.count == 0) {
			microblog = [self dictionaryValueFromObject:item[@"_microblog"]];
		}

		MBMention* mention = [[MBMention alloc] init];
		mention.avatarURL = [self stringValueFromObject:author[@"avatar"]];
		mention.fullName = [self stringValueFromObject:author[@"name"]];
		mention.username = [self stringValueFromObject:microblog[@"username"]];
		mention.postID = [self stringValueFromObjectOrNumber:item[@"id"]];
		mention.url = [self stringValueFromObject:item[@"url"]];

		NSString* content_html = [self stringValueFromObject:item[@"content_html"]];
		NSString* content_text = [self stringValueFromObject:item[@"content_text"]];
		NSString* text_value = [self plainTextFromHTMLString:content_html];
		if (text_value.length == 0) {
			text_value = [self normalizedTextString:content_text];
		}
		mention.text = text_value;
		mention.contentHTML = content_html;
		mention.date = [self dateValueFromEntry:item];

		[mentions addObject:mention];
	}

	return [mentions copy];
}

- (NSArray<MBEntry *> *) sidebarItemsForMentions:(NSArray*) mentions
{
	NSMutableArray<MBEntry *> *sidebar_items = [NSMutableArray array];
	for (id object in mentions ?: @[]) {
		if (![object isKindOfClass:[MBMention class]]) {
			continue;
		}

		MBMention* mention = (MBMention*) object;
		NSString* title_value = [mention.fullName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		if (title_value.length == 0 && mention.username.length > 0) {
			title_value = [NSString stringWithFormat:@"@%@", mention.username];
		}

		MBEntry* sidebar_entry = [[MBEntry alloc] init];
		sidebar_entry.title = title_value;
		sidebar_entry.url = mention.url ?: @"";
		sidebar_entry.subscriptionTitle = @"";
		sidebar_entry.summary = mention.text ?: @"";
		sidebar_entry.text = (mention.contentHTML.length > 0) ? mention.contentHTML : @"";
		sidebar_entry.source = @"";
		sidebar_entry.author = mention.username ?: @"";
		sidebar_entry.avatarURL = mention.avatarURL ?: @"";
		sidebar_entry.entryID = [mention.postID integerValue];
		sidebar_entry.feedID = 0;
		sidebar_entry.feedHost = [self normalizedHostFromURLString:mention.url ?: @""];
		sidebar_entry.date = mention.date;
		sidebar_entry.isRead = YES;
		sidebar_entry.isBookmarked = NO;
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

- (NSDictionary*) dictionaryValueFromObject:(id) object
{
	if ([object isKindOfClass:[NSDictionary class]]) {
		return (NSDictionary*) object;
	}

	return @{};
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

- (BOOL) performPrimaryActionForSelectedItem
{
	if ([self editSelectedItemIfPossible]) {
		return YES;
	}

	return [self openSelectedItemInBrowser];
}

- (BOOL) editSelectedItemIfPossible
{
	if ([self selectedItem] == nil) {
		return NO;
	}

	SEL edit_post_selector = NSSelectorFromString(@"editPost:");
	id target = [NSApp targetForAction:edit_post_selector to:nil from:self];
	if (target == nil) {
		return NO;
	}

	if ([target respondsToSelector:@selector(validateMenuItem:)]) {
		NSMenuItem* validation_item = [[NSMenuItem alloc] initWithTitle:@"" action:edit_post_selector keyEquivalent:@""];
		validation_item.target = target;
		if (![(id<NSMenuItemValidation>) target validateMenuItem:validation_item]) {
			return NO;
		}
	}

	return [NSApp sendAction:edit_post_selector to:target from:self];
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
	MBEntry* selected_item = [self selectedItem];
	BOOL is_draft = selected_item.isDraft;
	NSMenu* menu = [[NSMenu alloc] initWithTitle:@""];
	SEL new_post_selector = NSSelectorFromString(@"openPostWindow:");
	SEL toggle_read_selector = @selector(toggleSelectedItemReadStateAction:);
	SEL toggle_bookmark_selector = NSSelectorFromString(@"toggleSelectedItemBookmarkedState:");
	SEL edit_post_selector = NSSelectorFromString(@"editPost:");
	SEL show_conversation_selector = NSSelectorFromString(@"showConversation:");
	SEL show_highlights_selector = NSSelectorFromString(@"showHighlights:");
	SEL show_all_posts_selector = NSSelectorFromString(@"showAllPosts:");

	if (!is_draft) {
		NSMenuItem* new_post_item = [[NSMenuItem alloc] initWithTitle:@"New Post..." action:new_post_selector keyEquivalent:@""];
		new_post_item.target = nil;
		[menu addItem:new_post_item];

		NSMenuItem* toggle_read_item = [[NSMenuItem alloc] initWithTitle:@"Mark as Read" action:toggle_read_selector keyEquivalent:@""];
		toggle_read_item.target = self;
		[menu addItem:toggle_read_item];

		NSMenuItem* toggle_bookmark_item = [[NSMenuItem alloc] initWithTitle:@"Bookmark" action:toggle_bookmark_selector keyEquivalent:@""];
		toggle_bookmark_item.target = nil;
		[menu addItem:toggle_bookmark_item];
	}

	NSMenuItem* edit_post_item = [[NSMenuItem alloc] initWithTitle:@"Edit" action:edit_post_selector keyEquivalent:@""];
	edit_post_item.target = nil;
	[menu addItem:edit_post_item];

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

	return menu;
}

- (IBAction) performDoubleClickedSidebarItemAction:(id)sender
{
	#pragma unused(sender)

	NSInteger clicked_row = self.tableView.clickedRow;
	if (clicked_row < 0 || clicked_row >= self.items.count) {
		return;
	}

	NSIndexSet* index_set = [NSIndexSet indexSetWithIndex:(NSUInteger) clicked_row];
	[self.tableView selectRowIndexes:index_set byExtendingSelection:NO];
	[self performPrimaryActionForSelectedItem];
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
	NSNumber* entry_id_value = @(entry_id);
	self.pendingReadStateOverridesByEntryID[entry_id_value] = @(!should_mark_as_unread);
	[self reloadRowForEntryID:entry_id preferredRow:selected_row];
	__weak typeof(self) weak_self = self;
	void (^completion_handler)(NSError* _Nullable) = ^(NSError* _Nullable error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			MBSidebarController* strong_self = weak_self;
			if (strong_self == nil) {
				return;
			}

			[strong_self.pendingReadStateOverridesByEntryID removeObjectForKey:entry_id_value];
			if (error != nil) {
				[strong_self reloadRowForEntryID:entry_id preferredRow:selected_row];
				return;
			}

			[strong_self updateCachedReadState:!should_mark_as_unread forEntryID:entry_id];
			if (should_mark_as_unread) {
				BOOL should_clear_selection = ([strong_self currentSelectedEntryID] == entry_id);
				if (should_clear_selection) {
					[strong_self clearSavedSelectedEntryID];
					[strong_self deselectSidebarSelectionPreservingDetail];
					strong_self.rememberedDeselectedRow = selected_row;
				}
			}
			else {
				[strong_self clearRememberedDeselectedRow];
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
	if (menu_item.action == NSSelectorFromString(@"openPostWindow:")) {
		MBEntry* selected_item = [self selectedItem];
		return (selected_item != nil && !selected_item.isDraft);
	}
	if (menu_item.action == @selector(toggleSelectedItemReadStateAction:)) {
		MBEntry* selected_item = [self selectedItem];
		menu_item.title = [self readToggleMenuTitleForSelectedItem:selected_item];
		return [self canToggleSelectedItemReadState];
	}
	if (menu_item.action == @selector(toggleSelectedItemBookmarkedStateAction:)) {
		MBEntry* selected_item = [self selectedItem];
		menu_item.title = [self bookmarkToggleMenuTitleForSelectedItem:selected_item];
		return [self canToggleSelectedItemBookmarkedState];
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
	self.keepsPausedPodcastPaneVisibleUntilSelectionChange = NO;

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
	if (item == nil || item.isRead || item.entryID <= 0 || item.isBookmarkEntry || self.contentMode == MBSidebarContentModeBookmarks || self.contentMode == MBSidebarContentModeMentions) {
		return;
	}

	if (self.client == nil || self.token.length == 0) {
		return;
	}

	NSInteger entry_id = item.entryID;
	NSNumber* entry_id_value = @(entry_id);
	if (self.pendingReadStateOverridesByEntryID[entry_id_value] != nil) {
		return;
	}

	self.pendingReadStateOverridesByEntryID[entry_id_value] = @YES;
	[self.client markAsRead:entry_id token:self.token completion:^(NSError * _Nullable error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self.pendingReadStateOverridesByEntryID removeObjectForKey:entry_id_value];
			if (error != nil) {
				[self reloadRowForEntryID:entry_id preferredRow:row];
				return;
			}

			[self updateCachedReadState:YES forEntryID:entry_id];
			if (self.hideReadPosts) {
				[self applyFiltersAndReload];
			}
			else {
				[self reloadRowForEntryID:entry_id preferredRow:row];
			}
		});
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

- (BOOL) entryShowsReadState:(MBEntry*) entry
{
	if (![entry isKindOfClass:[MBEntry class]]) {
		return NO;
	}

	NSNumber* pending_read_state = self.pendingReadStateOverridesByEntryID[@(entry.entryID)];
	if (pending_read_state != nil) {
		return [pending_read_state boolValue];
	}

	if (entry.isRead) {
		return YES;
	}

	return NO;
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

	BOOL should_restore_selection = [self.tableView isRowSelected:row_to_reload] || (self.selectedRowForStyling == row_to_reload);
	NSIndexSet *row_indexes = [NSIndexSet indexSetWithIndex:(NSUInteger) row_to_reload];
	NSIndexSet *column_indexes = [NSIndexSet indexSetWithIndex:0];
	[self.tableView reloadDataForRowIndexes:row_indexes columnIndexes:column_indexes];
	if (should_restore_selection && ![self.tableView isRowSelected:row_to_reload]) {
		[self.tableView selectRowIndexes:row_indexes byExtendingSelection:NO];
		self.selectedRowForStyling = row_to_reload;
		[self refreshSelectionStylingForSelectedRow:row_to_reload];
		[self restoreSelectionForEntryIDOnNextRunLoop:entry_id];
	}
}

#pragma mark - Table View

- (NSInteger) numberOfRowsInTableView:(NSTableView *)tableView
{
	if (self.contentMode == MBSidebarContentModeMentions) {
		return self.mentions.count;
	}

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
	CGFloat cell_width = MAX(120.0, tableColumn.width);
	if (self.contentMode == MBSidebarContentModeMentions) {
		MBConversationCellView* cell_view = [tableView makeViewWithIdentifier:InkwellSidebarMentionCellIdentifier owner:self];
		if (cell_view == nil) {
			cell_view = [[MBConversationCellView alloc] initWithFrame:NSZeroRect];
			cell_view.identifier = InkwellSidebarMentionCellIdentifier;
		}

		if (row >= 0 && row < self.mentions.count) {
			MBMention* mention = self.mentions[(NSUInteger) row];
			NSImage* avatar_image = [self avatarImageForMention:mention];
			NSString* date_text = [self mentionsDisplayDateString:mention.date];
			[cell_view configureWithMention:mention dateText:date_text avatarImage:avatar_image];
		}
		[cell_view prepareForLayoutWithWidth:cell_width];

		return cell_view;
	}

	MBSidebarCell* cell_view = [tableView makeViewWithIdentifier:InkwellSidebarCellIdentifier owner:self];

	if (cell_view == nil) {
		cell_view = [[MBSidebarCell alloc] initWithFrame:NSZeroRect];
		cell_view.identifier = InkwellSidebarCellIdentifier;
	}

	MBEntry* item = self.items[(NSUInteger) row];
	[self configureSidebarCellContent:cell_view entry:item];
	[cell_view prepareForLayoutWithWidth:cell_width];

	MBRoundedImageView* avatar_view = cell_view.avatarView;
	NSTextField* title_field = cell_view.titleTextField;
	NSTextField* subtitle_field = cell_view.subtitleTextField;
	NSTextField* subscription_field = cell_view.subscriptionTextField;
	NSTextField* date_field = cell_view.dateTextField;
	NSTextField* bookmark_field = cell_view.bookmarkTextField;

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
	else if ([self entryShowsReadState:item] && self.contentMode != MBSidebarContentModeBookmarks) {
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
	if (row < 0) {
		return 54.0;
	}

	if (self.contentMode == MBSidebarContentModeMentions) {
		if (row >= self.mentions.count) {
			return 54.0;
		}

		MBMention* mention = self.mentions[(NSUInteger) row];
		NSTableColumn* table_column = tableView.tableColumns.firstObject;
		CGFloat table_width = MAX(120.0, table_column.width > 0 ? table_column.width : tableView.bounds.size.width);
		return [self fittingHeightForMention:mention width:table_width];
	}

	if (row >= self.items.count) {
		return 54.0;
	}

	MBEntry* item = self.items[(NSUInteger) row];
	NSTableColumn* table_column = tableView.tableColumns.firstObject;
	CGFloat table_width = MAX(120.0, table_column.width > 0 ? table_column.width : tableView.bounds.size.width);
	return [self fittingHeightForSidebarCellWithEntry:item width:table_width];
}

- (void) configureSidebarCellContent:(MBSidebarCell*) cell_view entry:(MBEntry*) item
{
	[self configureSidebarCellContent:cell_view entry:item includeAvatar:YES];
}

- (void) configureSidebarCellContent:(MBSidebarCell*) cell_view entry:(MBEntry*) item includeAvatar:(BOOL) includeAvatar
{
	if (cell_view == nil || item == nil) {
		return;
	}

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

	cell_view.titleTextField.stringValue = title_value;
	cell_view.subtitleTextField.stringValue = subtitle_value;
	cell_view.subtitleTextField.hidden = !should_show_subtitle;
	cell_view.subscriptionTextField.stringValue = subscription_value;
	cell_view.subscriptionTextField.hidden = !should_show_subscription;
	cell_view.dateTextField.stringValue = date_value;
	cell_view.bookmarkTextField.hidden = !item.isBookmarked;
	cell_view.bookmarkTextField.stringValue = item.isBookmarked ? @"★ Bookmarked" : @"";
	if (includeAvatar) {
		cell_view.avatarView.image = [self avatarImageForEntry:item];
	}
	else {
		cell_view.avatarView.image = nil;
	}

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
}

- (CGFloat) fittingHeightForSidebarCellWithEntry:(MBEntry*) item width:(CGFloat) width
{
	if (item == nil) {
		return 54.0;
	}

	if (self.sizingCellView == nil) {
		self.sizingCellView = [[MBSidebarCell alloc] initWithFrame:NSZeroRect];
		self.sizingCellView.translatesAutoresizingMaskIntoConstraints = NO;
	}

	MBSidebarCell* cell_view = self.sizingCellView;
	[self configureSidebarCellContent:cell_view entry:item includeAvatar:NO];

	NSLayoutConstraint* width_constraint = [cell_view.widthAnchor constraintEqualToConstant:width];
	width_constraint.active = YES;
	[cell_view prepareForLayoutWithWidth:width];
	CGFloat row_height = ceil(cell_view.fittingSize.height);
	width_constraint.active = NO;

	return MAX(50.0, row_height);
}

- (CGFloat) fittingHeightForMention:(MBMention*) mention width:(CGFloat) width
{
	if (mention == nil) {
		return 72.0;
	}

	if (self.sizingMentionCellView == nil) {
		self.sizingMentionCellView = [[MBConversationCellView alloc] initWithFrame:NSZeroRect];
		self.sizingMentionCellView.translatesAutoresizingMaskIntoConstraints = NO;
	}

	MBConversationCellView* cell_view = self.sizingMentionCellView;
	[cell_view configureWithMention:mention dateText:[self mentionsDisplayDateString:mention.date] avatarImage:[self fallbackAvatarImage]];

	NSLayoutConstraint* width_constraint = [cell_view.widthAnchor constraintEqualToConstant:width];
	width_constraint.active = YES;
	[cell_view prepareForLayoutWithWidth:width];
	CGFloat row_height = ceil(cell_view.fittingSize.height);
	width_constraint.active = NO;

	return MAX(72.0, row_height);
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
	if (self.contentMode == MBSidebarContentModeMentions) {
		return [self mentionsDisplayDateString:date];
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

- (NSString*) mentionsDisplayDateString:(NSDate* _Nullable) date
{
	if (date == nil) {
		return @"";
	}

	return [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle] ?: @"";
}

- (NSString*) plainTextFromHTMLString:(NSString*) html_string
{
	NSString* trimmed_html = [html_string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (trimmed_html.length == 0) {
		return @"";
	}

	NSData* html_data = [trimmed_html dataUsingEncoding:NSUTF8StringEncoding];
	if (html_data.length == 0) {
		return @"";
	}

	NSDictionary* options = @{
		NSDocumentTypeDocumentOption: NSHTMLTextDocumentType,
		NSCharacterEncodingDocumentOption: @(NSUTF8StringEncoding)
	};
	NSAttributedString* attributed_string = [[NSAttributedString alloc] initWithData:html_data options:options documentAttributes:nil error:nil];
	NSString* plain_text = attributed_string.string ?: @"";
	return [self normalizedTextString:plain_text];
}

- (NSString*) normalizedTextString:(NSString*) text_string
{
	NSString* normalized_text = [text_string stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] ?: @"";
	normalized_text = [normalized_text stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"] ?: @"";
	while ([normalized_text containsString:@"\n\n\n"]) {
		normalized_text = [normalized_text stringByReplacingOccurrencesOfString:@"\n\n\n" withString:@"\n\n"];
	}

	return [normalized_text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
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

- (BOOL) moveSelectionFromRememberedRow:(NSInteger) direction
{
	if (self.tableView == nil || self.items.count == 0) {
		[self clearRememberedDeselectedRow];
		return NO;
	}

	NSInteger remembered_row = self.rememberedDeselectedRow;
	if (remembered_row < 0 || remembered_row >= self.items.count) {
		[self clearRememberedDeselectedRow];
		return NO;
	}

	NSInteger target_row = remembered_row + direction;
	if (target_row < 0) {
		target_row = 0;
	}
	else if (target_row >= self.items.count) {
		target_row = self.items.count - 1;
	}

	[self clearRememberedDeselectedRow];

	NSIndexSet* index_set = [NSIndexSet indexSetWithIndex:(NSUInteger) target_row];
	[self.tableView selectRowIndexes:index_set byExtendingSelection:NO];
	self.selectedRowForStyling = target_row;
	[self.tableView scrollRowToVisible:target_row];
	return YES;
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

	[self clearRememberedDeselectedRow];
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
