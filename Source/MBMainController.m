//
//  MBMainController.m
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import "MBMainController.h"
#import "MBClient.h"
#import "MBDetailController.h"
#import "MBEntry.h"
#import "MBHighlightsController.h"
#import "MBSidebarController.h"

static NSToolbarItemIdentifier const InkwellToolbarFilterItemIdentifier = @"InkwellToolbarFilter";
static NSToolbarItemIdentifier const InkwellToolbarSearchItemIdentifier = @"InkwellToolbarSearch";
static NSToolbarItemIdentifier const InkwellToolbarProgressItemIdentifier = @"InkwellToolbarProgress";
static NSInteger const InkwellFilterTodaySegmentIndex = 0;
static NSInteger const InkwellFilterRecentSegmentIndex = 1;
static NSInteger const InkwellFilterFadingSegmentIndex = 2;

@interface MBMainController () <NSToolbarDelegate, NSSearchFieldDelegate>

@property (assign) BOOL didBuildInterface;
@property (strong) MBClient *client;
@property (strong) NSSegmentedControl *filterSegmentedControl;
@property (strong) NSProgressIndicator *toolbarProgressIndicator;
@property (strong) NSSearchField *toolbarSearchField;
@property (strong) NSSplitView *mainSplitView;
@property (strong) MBSidebarController *sidebarController;
@property (strong) MBDetailController *detailController;
@property (strong) MBHighlightsController *highlightsController;
@property (copy) NSString *token;
@property (assign) BOOL isNetworkingInProgress;

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
	if (self.window == nil) {
		NSRect frame = NSMakeRect(180.0, 180.0, 1040.0, 680.0);
		NSUInteger style_mask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
		self.window = [[NSWindow alloc] initWithContentRect:frame styleMask:style_mask backing:NSBackingStoreBuffered defer:NO];
	}

	NSSize minimum_window_size = NSMakeSize(900.0, 620.0);
	self.window.minSize = minimum_window_size;
	NSRect current_frame = self.window.frame;
	if (current_frame.size.width < minimum_window_size.width || current_frame.size.height < minimum_window_size.height) {
		current_frame.size.width = MAX(current_frame.size.width, minimum_window_size.width);
		current_frame.size.height = MAX(current_frame.size.height, minimum_window_size.height);
		[self.window setFrame:current_frame display:NO];
	}

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
}

- (void) buildContentSplitView
{
	self.sidebarController = [[MBSidebarController alloc] init];
	self.detailController = [[MBDetailController alloc] init];

	__weak typeof(self) weak_self = self;
	self.sidebarController.selectionChangedHandler = ^(MBEntry * _Nullable item) {
		[weak_self.detailController showSidebarItem:item];
		[weak_self.highlightsController updateForSelectedEntry:item];
	};
	self.sidebarController.client = self.client;
	self.sidebarController.token = self.token;

	NSSplitViewController *split_view_controller = [[NSSplitViewController alloc] init];

	NSSplitViewItem *sidebar_item = [NSSplitViewItem sidebarWithViewController:self.sidebarController];
	sidebar_item.minimumThickness = 290.0;
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
	[split_view_controller.splitView setPosition:290.0 ofDividerAtIndex:0];
	self.mainSplitView = split_view_controller.splitView;

	self.window.contentViewController = split_view_controller;
	[self.sidebarController reloadData];
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

#pragma mark - Toolbar

- (NSArray<NSToolbarItemIdentifier> *) toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
	return @[
		InkwellToolbarFilterItemIdentifier,
		NSToolbarSidebarTrackingSeparatorItemIdentifier,
		InkwellToolbarProgressItemIdentifier,
		NSToolbarFlexibleSpaceItemIdentifier,
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
		InkwellToolbarSearchItemIdentifier
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
		NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:item_identifier];
		item.label = @"Search";

		NSSearchField* previous_search_field = self.toolbarSearchField;
		if (previous_search_field != nil) {
			[[NSNotificationCenter defaultCenter] removeObserver:self name:NSControlTextDidChangeNotification object:previous_search_field];
		}

		self.toolbarSearchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 260.0, 0.0)];
		self.toolbarSearchField.placeholderString = @"Search";
		self.toolbarSearchField.translatesAutoresizingMaskIntoConstraints = NO;
		self.toolbarSearchField.delegate = self;
		[self.toolbarSearchField.widthAnchor constraintEqualToConstant:240.0].active = YES;
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(searchFieldTextDidChange:) name:NSControlTextDidChangeNotification object:self.toolbarSearchField];

		item.view = self.toolbarSearchField;
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
