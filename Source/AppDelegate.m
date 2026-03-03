//
//  AppDelegate.m
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import "AppDelegate.h"
#import <WebKit/WebKit.h>

static NSToolbarItemIdentifier const InkwellToolbarFilterItemIdentifier = @"InkwellToolbarFilter";
static NSToolbarItemIdentifier const InkwellToolbarSearchItemIdentifier = @"InkwellToolbarSearch";
static NSUserInterfaceItemIdentifier const InkwellSidebarCellIdentifier = @"InkwellSidebarCell";
static NSInteger const InkwellSidebarTitleTag = 1001;
static NSInteger const InkwellSidebarSubtitleTag = 1002;

@interface AppDelegate () <NSToolbarDelegate, NSTableViewDataSource, NSTableViewDelegate>

@property (strong) IBOutlet NSWindow *window;
@property (strong) NSSegmentedControl *filterSegmentedControl;
@property (strong) NSSearchField *toolbarSearchField;
@property (strong) NSTableView *sidebarTableView;
@property (strong) WKWebView *detailWebView;
@property (copy) NSArray<NSDictionary<NSString *, NSString *> *> *sidebarItems;
@property (strong) NSSplitView *mainSplitView;

@end

@implementation AppDelegate

- (void) applicationDidFinishLaunching:(NSNotification *)aNotification
{
	[self setupWindowIfNeeded];
	[self buildContentSplitView];
	[self buildToolbar];

	[self.sidebarTableView reloadData];
	if (self.sidebarItems.count > 0) {
		[self.sidebarTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
		[self loadDetailForSidebarItemAtIndex:0];
	}

	[self.window makeKeyAndOrderFront:nil];
}


- (void) applicationWillTerminate:(NSNotification *)aNotification
{
	// Insert code here to tear down your application
}


- (BOOL) applicationSupportsSecureRestorableState:(NSApplication *)app
{
	return YES;
}

- (void) setupWindowIfNeeded
{
	if (self.window == nil) {
		NSRect frame = NSMakeRect(180.0, 180.0, 1040.0, 680.0);
		NSUInteger styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
		self.window = [[NSWindow alloc] initWithContentRect:frame styleMask:styleMask backing:NSBackingStoreBuffered defer:NO];
	}

	NSSize minimumWindowSize = NSMakeSize(900.0, 620.0);
	self.window.minSize = minimumWindowSize;
	NSRect currentFrame = self.window.frame;
	if (currentFrame.size.width < minimumWindowSize.width || currentFrame.size.height < minimumWindowSize.height) {
		currentFrame.size.width = MAX(currentFrame.size.width, minimumWindowSize.width);
		currentFrame.size.height = MAX(currentFrame.size.height, minimumWindowSize.height);
		[self.window setFrame:currentFrame display:NO];
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
	self.sidebarItems = [self placeholderSidebarItems];

	NSSplitViewController *splitViewController = [[NSSplitViewController alloc] init];

	NSViewController *sidebarController = [self makeSidebarViewController];
	NSViewController *detailController = [self makeDetailViewController];

	NSSplitViewItem *sidebarItem = [NSSplitViewItem sidebarWithViewController:sidebarController];
	sidebarItem.minimumThickness = 290.0;
	sidebarItem.maximumThickness = 520.0;
	sidebarItem.canCollapse = NO;
	sidebarItem.holdingPriority = 260.0;
	sidebarItem.allowsFullHeightLayout = YES;

	NSSplitViewItem *detailItem = [NSSplitViewItem splitViewItemWithViewController:detailController];
	detailItem.minimumThickness = 420.0;
	detailItem.canCollapse = NO;
	detailItem.allowsFullHeightLayout = YES;

	[splitViewController addSplitViewItem:sidebarItem];
	[splitViewController addSplitViewItem:detailItem];
	splitViewController.splitView.dividerStyle = NSSplitViewDividerStyleThin;
	[splitViewController.splitView setPosition:290.0 ofDividerAtIndex:0];
	self.mainSplitView = splitViewController.splitView;

	self.window.contentViewController = splitViewController;
}

- (NSViewController *) makeSidebarViewController
{
	NSViewController *controller = [[NSViewController alloc] init];
	NSView *containerView = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 260.0, 600.0)];
	containerView.translatesAutoresizingMaskIntoConstraints = NO;
	controller.view = containerView;

	NSTableView *tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
	tableView.translatesAutoresizingMaskIntoConstraints = NO;
	tableView.delegate = self;
	tableView.dataSource = self;
	tableView.headerView = nil;
	tableView.intercellSpacing = NSMakeSize(0.0, 4.0);
	tableView.style = NSTableViewStyleSourceList;

	NSTableColumn *sourceColumn = [[NSTableColumn alloc] initWithIdentifier:@"SourceColumn"];
	sourceColumn.resizingMask = NSTableColumnAutoresizingMask;
	[tableView addTableColumn:sourceColumn];

	NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	scrollView.translatesAutoresizingMaskIntoConstraints = NO;
	scrollView.drawsBackground = NO;
	scrollView.hasVerticalScroller = YES;
	scrollView.borderType = NSNoBorder;
	scrollView.documentView = tableView;

	[containerView addSubview:scrollView];
	[NSLayoutConstraint activateConstraints:@[
		[scrollView.topAnchor constraintEqualToAnchor:containerView.topAnchor],
		[scrollView.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor],
		[scrollView.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor],
		[scrollView.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor]
	]];

	self.sidebarTableView = tableView;
	return controller;
}

- (NSViewController *) makeDetailViewController
{
	NSViewController *controller = [[NSViewController alloc] init];
	NSView *rootView = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 780.0, 600.0)];
	rootView.translatesAutoresizingMaskIntoConstraints = NO;

	NSView *containerView = [[NSView alloc] initWithFrame:NSZeroRect];
	containerView.translatesAutoresizingMaskIntoConstraints = NO;
	[rootView addSubview:containerView];

	[NSLayoutConstraint activateConstraints:@[
		[containerView.topAnchor constraintEqualToAnchor:rootView.topAnchor],
		[containerView.bottomAnchor constraintEqualToAnchor:rootView.bottomAnchor],
		[containerView.leadingAnchor constraintEqualToAnchor:rootView.leadingAnchor],
		[containerView.trailingAnchor constraintEqualToAnchor:rootView.trailingAnchor]
	]];

	WKWebView *webView = [[WKWebView alloc] initWithFrame:NSZeroRect];
	webView.translatesAutoresizingMaskIntoConstraints = NO;
	[containerView addSubview:webView];
	[NSLayoutConstraint activateConstraints:@[
		[webView.topAnchor constraintEqualToAnchor:containerView.topAnchor],
		[webView.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor],
		[webView.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor],
		[webView.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor]
	]];
	self.detailWebView = webView;

	controller.view = rootView;
	return controller;
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *) placeholderSidebarItems
{
	return @[
		@{ @"title": @"Morning Capture", @"subtitle": @"Save quick notes, links, and headlines for today's review." },
		@{ @"title": @"Bookmarks", @"subtitle": @"A compact list of highlighted reads from the last couple of days." },
		@{ @"title": @"Longform Queue", @"subtitle": @"Articles you wanted to revisit, with short context snippets and tags." },
		@{ @"title": @"Microblog Drafts", @"subtitle": @"Partial drafts and topic ideas waiting for edits before posting." },
		@{ @"title": @"Research Notes", @"subtitle": @"Reference points, quotes, and summaries collected from your current project." },
		@{ @"title": @"Weekend Ideas", @"subtitle": @"Loose writing prompts and experiments you may expand later this week." },
		@{ @"title": @"Archive", @"subtitle": @"Older entries kept for context, search, and occasional resurfacing." }
	];
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

- (NSToolbarItem *) toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag
{
	if ([itemIdentifier isEqualToString:InkwellToolbarFilterItemIdentifier]) {
		NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
		item.label = @"Filter";

		self.filterSegmentedControl = [NSSegmentedControl segmentedControlWithLabels:@[@"Today", @"Recent", @"Fading"] trackingMode:NSSegmentSwitchTrackingSelectOne target:nil action:nil];
		self.filterSegmentedControl.selectedSegment = 0;
		self.filterSegmentedControl.segmentStyle = NSSegmentStyleAutomatic;
		self.filterSegmentedControl.translatesAutoresizingMaskIntoConstraints = NO;

		item.view = self.filterSegmentedControl;
		return item;
	}

	if ([itemIdentifier isEqualToString:InkwellToolbarSearchItemIdentifier]) {
		NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
		item.label = @"Search";

		self.toolbarSearchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 260.0, 0.0)];
		self.toolbarSearchField.placeholderString = @"Search";
		self.toolbarSearchField.translatesAutoresizingMaskIntoConstraints = NO;
		[self.toolbarSearchField.widthAnchor constraintEqualToConstant:240.0].active = YES;

		item.view = self.toolbarSearchField;
		return item;
	}

	if ([itemIdentifier isEqualToString:NSToolbarSidebarTrackingSeparatorItemIdentifier]) {
		if (self.mainSplitView == nil) {
			return [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
		}

		return [NSTrackingSeparatorToolbarItem trackingSeparatorToolbarItemWithIdentifier:itemIdentifier splitView:self.mainSplitView dividerIndex:0];
	}

	return nil;
}

#pragma mark - Table View

- (NSInteger) numberOfRowsInTableView:(NSTableView *)tableView
{
	return self.sidebarItems.count;
}

- (NSView *) tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSTableCellView *cellView = [tableView makeViewWithIdentifier:InkwellSidebarCellIdentifier owner:self];

	if (cellView == nil) {
		cellView = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
		cellView.identifier = InkwellSidebarCellIdentifier;

		NSTextField *titleField = [NSTextField labelWithString:@""];
		titleField.translatesAutoresizingMaskIntoConstraints = NO;
		titleField.tag = InkwellSidebarTitleTag;
		titleField.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
		titleField.lineBreakMode = NSLineBreakByWordWrapping;
		titleField.maximumNumberOfLines = 2;

		NSTextField *subtitleField = [NSTextField labelWithString:@""];
		subtitleField.translatesAutoresizingMaskIntoConstraints = NO;
		subtitleField.tag = InkwellSidebarSubtitleTag;
		subtitleField.font = [NSFont systemFontOfSize:12.0];
		subtitleField.textColor = [NSColor secondaryLabelColor];
		subtitleField.lineBreakMode = NSLineBreakByWordWrapping;
		subtitleField.maximumNumberOfLines = 3;

		[cellView addSubview:titleField];
		[cellView addSubview:subtitleField];

		NSLayoutConstraint *bottomConstraint = [subtitleField.bottomAnchor constraintLessThanOrEqualToAnchor:cellView.bottomAnchor constant:-8.0];
		bottomConstraint.priority = NSLayoutPriorityDefaultHigh;

		[NSLayoutConstraint activateConstraints:@[
			[titleField.topAnchor constraintEqualToAnchor:cellView.topAnchor constant:8.0],
			[titleField.leadingAnchor constraintEqualToAnchor:cellView.leadingAnchor constant:10.0],
			[titleField.trailingAnchor constraintEqualToAnchor:cellView.trailingAnchor constant:-10.0],
			[subtitleField.topAnchor constraintEqualToAnchor:titleField.bottomAnchor constant:3.0],
			[subtitleField.leadingAnchor constraintEqualToAnchor:cellView.leadingAnchor constant:10.0],
			[subtitleField.trailingAnchor constraintEqualToAnchor:cellView.trailingAnchor constant:-10.0],
			bottomConstraint
		]];
	}

	NSDictionary<NSString *, NSString *> *item = self.sidebarItems[(NSUInteger)row];
	NSTextField *titleField = [cellView viewWithTag:InkwellSidebarTitleTag];
	NSTextField *subtitleField = [cellView viewWithTag:InkwellSidebarSubtitleTag];

	titleField.stringValue = item[@"title"] ?: @"";
	subtitleField.stringValue = item[@"subtitle"] ?: @"";

	return cellView;
}

- (CGFloat) tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
	if (row < 0 || row >= self.sidebarItems.count) {
		return 54.0;
	}

	NSDictionary<NSString *, NSString *> *item = self.sidebarItems[(NSUInteger)row];
	CGFloat contentWidth = MAX(120.0, tableView.bounds.size.width - 20.0);

	CGFloat titleHeight = [self heightForText:item[@"title"] font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold] width:contentWidth];
	CGFloat subtitleHeight = [self heightForText:item[@"subtitle"] font:[NSFont systemFontOfSize:12.0] width:contentWidth];
	CGFloat rowHeight = 8.0 + titleHeight + 3.0 + subtitleHeight + 8.0;

	return MAX(50.0, ceil(rowHeight));
}

- (CGFloat) heightForText:(NSString *)text font:(NSFont *)font width:(CGFloat)width
{
	if (text.length == 0 || font == nil) {
		return 0.0;
	}

	NSRect textRect = [text boundingRectWithSize:NSMakeSize(width, CGFLOAT_MAX)
		options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
		attributes:@{ NSFontAttributeName: font }];
	return ceil(NSHeight(textRect));
}

- (void) tableViewSelectionDidChange:(NSNotification *)notification
{
	NSInteger selectedRow = self.sidebarTableView.selectedRow;
	[self loadDetailForSidebarItemAtIndex:selectedRow];
}

- (void) loadDetailForSidebarItemAtIndex:(NSInteger)index
{
	NSString *title = @"Select a source item";
	NSString *subtitle = @"Pick an item from the sidebar.";

	if (index >= 0 && index < self.sidebarItems.count) {
		NSDictionary<NSString *, NSString *> *item = self.sidebarItems[(NSUInteger) index];
		NSString *itemTitle = item[@"title"];
		NSString *itemSubtitle = item[@"subtitle"];
		if (itemTitle.length > 0) {
			title = itemTitle;
		}
		if (itemSubtitle.length > 0) {
			subtitle = itemSubtitle;
		}
	}

	if (self.detailWebView == nil) {
		return;
	}

	NSString *safeTitle = [self escapedHTMLString:title];
	NSString *safeSubtitle = [self escapedHTMLString:subtitle];
	NSString *html = [NSString stringWithFormat:
		@"<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;margin:0;padding:40px;color:#1d1d1f;}h1{font-size:30px;line-height:1.2;margin:0 0 12px;}p{font-size:16px;line-height:1.5;color:#1d1d1f;max-width:760px;}</style></head><body><h1>%@</h1><p>%@</p></body></html>",
		safeTitle,
		safeSubtitle];

	[self.detailWebView loadHTMLString:html baseURL:nil];
}

- (NSString *) escapedHTMLString:(NSString *)string
{
	if (string.length == 0) {
		return @"";
	}

	NSMutableString *escaped = [string mutableCopy];
	[escaped replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, escaped.length)];
	[escaped replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, escaped.length)];
	[escaped replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, escaped.length)];
	[escaped replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, escaped.length)];
	[escaped replaceOccurrencesOfString:@"'" withString:@"&#39;" options:0 range:NSMakeRange(0, escaped.length)];
	return escaped;
}


@end
