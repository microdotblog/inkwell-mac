//
//  MBMainController.m
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import "MBMainController.h"
#import "MBClient.h"
#import "MBDetailController.h"
#import "MBSidebarController.h"

static NSToolbarItemIdentifier const InkwellToolbarFilterItemIdentifier = @"InkwellToolbarFilter";
static NSToolbarItemIdentifier const InkwellToolbarSearchItemIdentifier = @"InkwellToolbarSearch";

@interface MBMainController () <NSToolbarDelegate>

@property (assign) BOOL didBuildInterface;
@property (strong) MBClient *client;
@property (strong) NSSegmentedControl *filterSegmentedControl;
@property (strong) NSSearchField *toolbarSearchField;
@property (strong) NSSplitView *mainSplitView;
@property (strong) MBSidebarController *sidebarController;
@property (strong) MBDetailController *detailController;
@property (copy) NSString *token;

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
	}
	return self;
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
	[self.sidebarController reloadDataAndSelectFirstItem];
}

#pragma mark - Toolbar

- (NSArray<NSToolbarItemIdentifier> *) toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
	return @[
		InkwellToolbarFilterItemIdentifier,
		NSToolbarSidebarTrackingSeparatorItemIdentifier,
		NSToolbarFlexibleSpaceItemIdentifier,
		InkwellToolbarSearchItemIdentifier
	];
}

- (NSArray<NSToolbarItemIdentifier> *) toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
	return @[
		InkwellToolbarFilterItemIdentifier,
		NSToolbarSidebarTrackingSeparatorItemIdentifier,
		NSToolbarFlexibleSpaceItemIdentifier,
		InkwellToolbarSearchItemIdentifier
	];
}

- (NSToolbarItem *) toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)item_identifier willBeInsertedIntoToolbar:(BOOL)flag
{
	if ([item_identifier isEqualToString:InkwellToolbarFilterItemIdentifier]) {
		NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:item_identifier];
		item.label = @"Filter";

		self.filterSegmentedControl = [NSSegmentedControl segmentedControlWithLabels:@[@"Today", @"Recent", @"Fading"] trackingMode:NSSegmentSwitchTrackingSelectOne target:nil action:nil];
		self.filterSegmentedControl.selectedSegment = 0;
		self.filterSegmentedControl.segmentStyle = NSSegmentStyleAutomatic;
		self.filterSegmentedControl.translatesAutoresizingMaskIntoConstraints = NO;

		item.view = self.filterSegmentedControl;
		return item;
	}

	if ([item_identifier isEqualToString:InkwellToolbarSearchItemIdentifier]) {
		NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:item_identifier];
		item.label = @"Search";

		self.toolbarSearchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 260.0, 0.0)];
		self.toolbarSearchField.placeholderString = @"Search";
		self.toolbarSearchField.translatesAutoresizingMaskIntoConstraints = NO;
		[self.toolbarSearchField.widthAnchor constraintEqualToConstant:240.0].active = YES;

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
