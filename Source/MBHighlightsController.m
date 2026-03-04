//
//  MBHighlightsController.m
//  Inkwell
//
//  Created by Codex on 3/4/26.
//

#import "MBHighlightsController.h"
#import "MBClient.h"
#import "MBHighlight.h"
#import "MBHighlightCellView.h"

static NSUserInterfaceItemIdentifier const InkwellHighlightsCellIdentifier = @"InkwellHighlightsCell";

@interface MBHighlightsController () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) MBClient* client;
@property (nonatomic, copy) NSString* token;
@property (nonatomic, assign, readwrite) NSInteger entryID;
@property (nonatomic, copy) NSArray* highlights;
@property (nonatomic, strong) NSTableView* tableView;
@property (nonatomic, assign) BOOL didSetupContent;
@property (nonatomic, assign) BOOL isFetching;

@end

@implementation MBHighlightsController

- (instancetype) initWithClient:(MBClient*) client token:(NSString*) token
{
	self = [super initWithWindow:nil];
	if (self) {
		self.client = client;
		self.token = token ?: @"";
		self.highlights = @[];
	}
	return self;
}

- (void) showWindow:(id)sender
{
	[self setupWindowIfNeeded];
	[self setupContentIfNeeded];
	[super showWindow:sender];
	[self.window makeKeyAndOrderFront:sender];
}

- (void) showHighlightsForEntryID:(NSInteger) entry_id
{
	self.entryID = entry_id;
	[self showWindow:nil];
	[self reloadHighlights];
}

- (void) reloadHighlights
{
	if (self.entryID <= 0 || self.client == nil || self.token.length == 0) {
		self.highlights = @[];
		[self.tableView reloadData];
		return;
	}

	if (self.isFetching) {
		return;
	}

	self.isFetching = YES;
	[self.client fetchHighlightsForEntryID:self.entryID token:self.token completion:^(NSArray* _Nullable highlights, NSError* _Nullable error) {
		self.isFetching = NO;
		if (error != nil || ![highlights isKindOfClass:[NSArray class]]) {
			self.highlights = @[];
			[self.tableView reloadData];
			return;
		}

		self.highlights = [highlights copy];
		[self.tableView reloadData];
	}];
}

- (void) setupWindowIfNeeded
{
	if (self.window != nil) {
		return;
	}

	NSRect frame = NSMakeRect(220.0, 220.0, 420.0, 460.0);
	NSUInteger style_mask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow;
	NSPanel* panel = [[NSPanel alloc] initWithContentRect:frame styleMask:style_mask backing:NSBackingStoreBuffered defer:NO];
	panel.floatingPanel = YES;
	panel.hidesOnDeactivate = NO;
	panel.level = NSFloatingWindowLevel;
	panel.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace;
	panel.releasedWhenClosed = NO;
	panel.minSize = NSMakeSize(300.0, 220.0);
	panel.title = @"Highlights";
	self.window = panel;
}

- (void) setupContentIfNeeded
{
	if (self.didSetupContent) {
		return;
	}

	NSView* content_view = self.window.contentView;
	if (content_view == nil) {
		return;
	}

	NSTableView* table_view = [[NSTableView alloc] initWithFrame:NSZeroRect];
	table_view.translatesAutoresizingMaskIntoConstraints = NO;
	table_view.delegate = self;
	table_view.dataSource = self;
	table_view.headerView = nil;
	table_view.rowHeight = 62.0;
	table_view.intercellSpacing = NSMakeSize(0.0, 6.0);
	table_view.usesAutomaticRowHeights = NO;
	table_view.allowsMultipleSelection = NO;
	table_view.allowsEmptySelection = YES;

	NSTableColumn* content_column = [[NSTableColumn alloc] initWithIdentifier:@"HighlightsColumn"];
	content_column.resizingMask = NSTableColumnAutoresizingMask;
	content_column.editable = NO;
	[table_view addTableColumn:content_column];

	NSScrollView* scroll_view = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	scroll_view.translatesAutoresizingMaskIntoConstraints = NO;
	scroll_view.drawsBackground = NO;
	scroll_view.hasVerticalScroller = YES;
	scroll_view.borderType = NSNoBorder;
	scroll_view.documentView = table_view;

	[content_view addSubview:scroll_view];
	[NSLayoutConstraint activateConstraints:@[
		[scroll_view.topAnchor constraintEqualToAnchor:content_view.topAnchor],
		[scroll_view.bottomAnchor constraintEqualToAnchor:content_view.bottomAnchor],
		[scroll_view.leadingAnchor constraintEqualToAnchor:content_view.leadingAnchor],
		[scroll_view.trailingAnchor constraintEqualToAnchor:content_view.trailingAnchor]
	]];

	self.tableView = table_view;
	self.didSetupContent = YES;
}

- (NSInteger) numberOfRowsInTableView:(NSTableView*) tableView
{
	#pragma unused(tableView)
	return self.highlights.count;
}

- (NSView*) tableView:(NSTableView*) tableView viewForTableColumn:(NSTableColumn*) tableColumn row:(NSInteger)row
{
	#pragma unused(tableColumn)
	if (row < 0 || row >= self.highlights.count) {
		return nil;
	}

	MBHighlightCellView* cell_view = [tableView makeViewWithIdentifier:InkwellHighlightsCellIdentifier owner:self];
	if (cell_view == nil) {
		cell_view = [[MBHighlightCellView alloc] initWithFrame:NSZeroRect];
		cell_view.identifier = InkwellHighlightsCellIdentifier;
	}

	MBHighlight* highlight = self.highlights[row];
	[cell_view configureWithHighlight:highlight];
	return cell_view;
}

@end
