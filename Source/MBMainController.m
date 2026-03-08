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
#import "MBPreferencesController.h"
#import "MBSidebarController.h"

static NSToolbarItemIdentifier const InkwellToolbarFilterItemIdentifier = @"InkwellToolbarFilter";
static NSToolbarItemIdentifier const InkwellToolbarSearchItemIdentifier = @"InkwellToolbarSearch";
static NSToolbarItemIdentifier const InkwellToolbarHighlightItemIdentifier = @"InkwellToolbarHighlight";
static NSToolbarItemIdentifier const InkwellToolbarRepliesItemIdentifier = @"InkwellToolbarReplies";
static NSToolbarItemIdentifier const InkwellToolbarProgressItemIdentifier = @"InkwellToolbarProgress";
static NSInteger const InkwellFilterTodaySegmentIndex = 0;
static NSInteger const InkwellFilterRecentSegmentIndex = 1;
static NSInteger const InkwellFilterFadingSegmentIndex = 2;
static CGFloat const InkwellSidebarPaneWidth = 310.0;

@interface MBMainController () <NSToolbarDelegate, NSSearchFieldDelegate, NSMenuItemValidation, NSToolbarItemValidation>

@property (assign) BOOL didBuildInterface;
@property (strong) MBClient *client;
@property (strong) NSSegmentedControl *filterSegmentedControl;
@property (strong) NSProgressIndicator *toolbarProgressIndicator;
@property (strong) NSSearchField *toolbarSearchField;
@property (strong) NSSplitView *mainSplitView;
@property (strong) MBSidebarController *sidebarController;
@property (strong) MBDetailController *detailController;
@property (strong) MBHighlightsController *highlightsController;
@property (strong) MBConversationController* conversationController;
@property (strong) MBPreferencesController* preferencesController;
@property (copy) NSString *token;
@property (assign) BOOL isNetworkingInProgress;
@property (assign) BOOL isSyncingHighlights;
@property (assign) NSInteger conversationReplyCount;
@property (copy) NSDictionary* lastConversationPayload;
@property (copy) NSString* pendingConversationLookupURLString;
@property (strong) NSButton* toolbarRepliesButton;

- (BOOL) focusSidebarPane;
- (BOOL) focusDetailPane;

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
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void) close
{
	[self.preferencesController close];
	[self.conversationController close];
	[self.highlightsController close];
	[super close];
}

- (void) showWindow:(id)sender
{
	[self buildInterfaceIfNeeded];
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

	self.didBuildInterface = YES;
}

- (void) setupWindowIfNeeded
{
	self.window.title = @"Inkwell";
	self.window.styleMask |= NSWindowStyleMaskFullSizeContentView;
	self.window.titlebarAppearsTransparent = YES;
	self.window.titleVisibility = NSWindowTitleHidden;
	self.window.toolbarStyle = NSWindowToolbarStyleUnified;
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

	__weak typeof(self) weak_self = self;
	self.sidebarController.selectionChangedHandler = ^(MBEntry * _Nullable item) {
		[weak_self.detailController showSidebarItem:item];
		[weak_self.highlightsController updateForSelectedEntry:item];
		[weak_self updateConversationForSelectedItem:item];
	};
	self.sidebarController.focusDetailHandler = ^BOOL {
		MBMainController* strong_self = weak_self;
		if (strong_self == nil) {
			return NO;
		}

		return [strong_self focusDetailPane];
	};
	self.sidebarController.syncCompletedHandler = ^{
		[weak_self syncHighlightsFromServer];
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
	[split_view_controller.splitView setPosition:InkwellSidebarPaneWidth ofDividerAtIndex:0];
	self.mainSplitView = split_view_controller.splitView;

	self.window.contentViewController = split_view_controller;
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

	self.sidebarController.dateFilter = [self sidebarDateFilterForSegmentIndex:segment_index];

	if (self.filterSegmentedControl == nil) {
		return;
	}

	if (segment_index >= self.filterSegmentedControl.segmentCount) {
		return;
	}

	self.filterSegmentedControl.selectedSegment = segment_index;
}

- (IBAction) filterSegmentChanged:(id)sender
{
	#pragma unused(sender)
	[self selectFilterSegment:self.filterSegmentedControl.selectedSegment];
}

- (IBAction) selectTodayView:(id)sender
{
	#pragma unused(sender)
	[self selectFilterSegment:InkwellFilterTodaySegmentIndex];
}

- (IBAction) selectRecentView:(id)sender
{
	#pragma unused(sender)
	[self selectFilterSegment:InkwellFilterRecentSegmentIndex];
}

- (IBAction) selectFadingView:(id)sender
{
	#pragma unused(sender)
	[self selectFilterSegment:InkwellFilterFadingSegmentIndex];
}

- (IBAction) refreshView:(id)sender
{
	#pragma unused(sender)
	[self.sidebarController refreshData];
}

- (IBAction) showHighlights:(id)sender
{
	#pragma unused(sender)

	MBEntry* selected_item = [self.sidebarController selectedItem];
	if (selected_item == nil || selected_item.entryID <= 0) {
		return;
	}

	if (self.highlightsController == nil) {
		self.highlightsController = [[MBHighlightsController alloc] initWithClient:self.client token:self.token];
	}

	[self.highlightsController showHighlightsForEntry:selected_item];
}

- (IBAction) newPost:(id)sender
{
	#pragma unused(sender)

	MBEntry* selected_item = [self.sidebarController selectedItem];
	if (selected_item == nil) {
		return;
	}

	NSString* title_string = [selected_item.title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (title_string.length == 0) {
		title_string = [selected_item.subscriptionTitle stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	}

	NSString* url_string = [selected_item.url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (url_string.length == 0) {
		return;
	}

	NSString* markdown_text = [NSString stringWithFormat:@"[%@](%@):\n\n", title_string, url_string];
	NSMutableCharacterSet* allowed_character_set = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
	[allowed_character_set removeCharactersInString:@":#[]@!$&'()*+,;=/?"];
	NSString* encoded_text = [markdown_text stringByAddingPercentEncodingWithAllowedCharacters:allowed_character_set] ?: @"";
	if (encoded_text.length == 0) {
		return;
	}

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

- (IBAction) showPreferences:(id) sender
{
	#pragma unused(sender)

	if (self.preferencesController == nil) {
		self.preferencesController = [[MBPreferencesController alloc] init];

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
	if (menu_item.action == @selector(newPost:)) {
		return ([self.sidebarController selectedItem] != nil);
	}
	if (menu_item.action == @selector(showHighlights:)) {
		MBEntry* selected_item = [self.sidebarController selectedItem];
		return (selected_item != nil && selected_item.entryID > 0);
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

- (BOOL) validateToolbarItem:(NSToolbarItem *)toolbar_item
{
	if (toolbar_item.action == @selector(highlightSelectedItem:)) {
		return [self.detailController hasSelection];
	}
	if (toolbar_item.action == @selector(showConversation:)) {
		return (self.conversationReplyCount > 0);
	}

	return YES;
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

	self.sidebarController.searchQuery = search_field.stringValue ?: @"";
}

- (BOOL) control:(NSControl*) control textView:(NSTextView*) text_view doCommandBySelector:(SEL) command_selector
{
	#pragma unused(control)
	#pragma unused(text_view)

	if (command_selector == @selector(insertNewline:) || command_selector == @selector(insertLineBreak:) || command_selector == @selector(insertNewlineIgnoringFieldEditor:)) {
		[self.sidebarController focusAndSelectFirstItem];
		return YES;
	}

	return NO;
}

- (IBAction) highlightSelectedItem:(id) sender
{
	#pragma unused(sender)

	MBEntry* selected_item = [self.sidebarController selectedItem];
	if (selected_item == nil || selected_item.entryID <= 0) {
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

		MBHighlight* local_highlight = [weak_self.client saveLocalHighlightForEntryID:selected_entry_id selectionText:trimmed_selection_text selectionStart:selection_start selectionEnd:selection_end];
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
		InkwellToolbarHighlightItemIdentifier
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
		item.image = [NSImage imageWithSystemSymbolName:@"highlighter" accessibilityDescription:@"Highlight"];
		item.target = self;
		item.action = @selector(highlightSelectedItem:);
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
