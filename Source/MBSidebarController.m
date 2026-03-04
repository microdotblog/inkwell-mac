//
//  MBSidebarController.m
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import "MBSidebarController.h"
#import "MBClient.h"

static NSUserInterfaceItemIdentifier const InkwellSidebarCellIdentifier = @"InkwellSidebarCell";
static NSInteger const InkwellSidebarTitleTag = 1001;
static NSInteger const InkwellSidebarSubtitleTag = 1002;

@interface MBSidebarController () <NSTableViewDataSource, NSTableViewDelegate>

@property (assign) BOOL hasLoadedRemoteItems;
@property (assign) BOOL isFetching;
@property (strong) NSTableView *tableView;

@end

@implementation MBSidebarController

- (instancetype) init
{
	self = [super initWithNibName:nil bundle:nil];
	if (self) {
		self.items = @[];
	}
	return self;
}

- (void) loadView
{
	NSView *container_view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 260.0, 600.0)];
	container_view.translatesAutoresizingMaskIntoConstraints = NO;

	NSTableView *table_view = [[NSTableView alloc] initWithFrame:NSZeroRect];
	table_view.translatesAutoresizingMaskIntoConstraints = NO;
	table_view.delegate = self;
	table_view.dataSource = self;
	table_view.headerView = nil;
	table_view.intercellSpacing = NSMakeSize(0.0, 4.0);
	table_view.style = NSTableViewStyleSourceList;

	NSTableColumn *source_column = [[NSTableColumn alloc] initWithIdentifier:@"SourceColumn"];
	source_column.resizingMask = NSTableColumnAutoresizingMask;
	[table_view addTableColumn:source_column];

	NSScrollView *scroll_view = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	scroll_view.translatesAutoresizingMaskIntoConstraints = NO;
	scroll_view.drawsBackground = NO;
	scroll_view.hasVerticalScroller = YES;
	scroll_view.borderType = NSNoBorder;
	scroll_view.documentView = table_view;

	[container_view addSubview:scroll_view];
	[NSLayoutConstraint activateConstraints:@[
		[scroll_view.topAnchor constraintEqualToAnchor:container_view.topAnchor],
		[scroll_view.bottomAnchor constraintEqualToAnchor:container_view.bottomAnchor],
		[scroll_view.leadingAnchor constraintEqualToAnchor:container_view.leadingAnchor],
		[scroll_view.trailingAnchor constraintEqualToAnchor:container_view.trailingAnchor]
	]];

	self.tableView = table_view;
	self.view = container_view;
}

- (void) reloadDataAndSelectFirstItem
{
	[self reloadTableAndSelectFirstItem];
	[self fetchEntriesIfNeeded];
}

- (void) reloadTableAndSelectFirstItem
{
	[self.tableView reloadData];

	if (self.items.count > 0) {
		NSIndexSet *index_set = [NSIndexSet indexSetWithIndex:0];
		[self.tableView selectRowIndexes:index_set byExtendingSelection:NO];
		[self notifySelectionChanged];
		return;
	}

	[self notifySelectionChanged];
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
	[self.client fetchFeedEntriesWithToken:self.token completion:^(NSArray<NSDictionary<NSString *,id> *> * _Nullable entries, NSError * _Nullable error) {
		self.isFetching = NO;
		if (error != nil) {
			return;
		}

		NSArray<NSDictionary<NSString *, NSString *> *> *sidebar_items = [self sidebarItemsForEntries:entries ?: @[]];
		self.hasLoadedRemoteItems = YES;
		self.items = sidebar_items;
		[self reloadTableAndSelectFirstItem];
	}];
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *) sidebarItemsForEntries:(NSArray<NSDictionary<NSString *, id> *> *)entries
{
	NSMutableArray<NSDictionary<NSString *, NSString *> *> *sidebar_items = [NSMutableArray array];

	for (NSDictionary<NSString *, id> *entry in entries) {
		NSString *title_value = [self stringValueFromObject:entry[@"title"]];
		NSString *summary_value = [self stringValueFromObject:entry[@"summary"]];
		NSString *author_value = [self stringValueFromObject:entry[@"author"]];
		NSString *url_value = [self stringValueFromObject:entry[@"url"]];

		NSString *resolved_title = title_value;
		if (resolved_title.length == 0) {
			resolved_title = url_value.length > 0 ? url_value : @"Untitled";
		}

		NSString *resolved_subtitle = summary_value;
		if (resolved_subtitle.length == 0) {
			resolved_subtitle = author_value;
		}
		if (resolved_subtitle.length == 0) {
			resolved_subtitle = @"";
		}

		[sidebar_items addObject:@{
			@"title": resolved_title,
			@"subtitle": resolved_subtitle
		}];
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

- (void) notifySelectionChanged
{
	if (self.selectionChangedHandler == nil) {
		return;
	}

	NSInteger selected_row = self.tableView.selectedRow;
	if (selected_row >= 0 && selected_row < self.items.count) {
		NSDictionary<NSString *, NSString *> *item = self.items[(NSUInteger) selected_row];
		self.selectionChangedHandler(item);
		return;
	}

	self.selectionChangedHandler(nil);
}

#pragma mark - Table View

- (NSInteger) numberOfRowsInTableView:(NSTableView *)tableView
{
	return self.items.count;
}

- (NSView *) tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSTableCellView *cell_view = [tableView makeViewWithIdentifier:InkwellSidebarCellIdentifier owner:self];

	if (cell_view == nil) {
		cell_view = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
		cell_view.identifier = InkwellSidebarCellIdentifier;

		NSTextField *title_field = [NSTextField labelWithString:@""];
		title_field.translatesAutoresizingMaskIntoConstraints = NO;
		title_field.tag = InkwellSidebarTitleTag;
		title_field.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
		title_field.lineBreakMode = NSLineBreakByWordWrapping;
		title_field.maximumNumberOfLines = 2;

		NSTextField *subtitle_field = [NSTextField labelWithString:@""];
		subtitle_field.translatesAutoresizingMaskIntoConstraints = NO;
		subtitle_field.tag = InkwellSidebarSubtitleTag;
		subtitle_field.font = [NSFont systemFontOfSize:12.0];
		subtitle_field.textColor = [NSColor secondaryLabelColor];
		subtitle_field.lineBreakMode = NSLineBreakByWordWrapping;
		subtitle_field.maximumNumberOfLines = 3;

		[cell_view addSubview:title_field];
		[cell_view addSubview:subtitle_field];

		NSLayoutConstraint *bottom_constraint = [subtitle_field.bottomAnchor constraintLessThanOrEqualToAnchor:cell_view.bottomAnchor constant:-8.0];
		bottom_constraint.priority = NSLayoutPriorityDefaultHigh;

		[NSLayoutConstraint activateConstraints:@[
			[title_field.topAnchor constraintEqualToAnchor:cell_view.topAnchor constant:8.0],
			[title_field.leadingAnchor constraintEqualToAnchor:cell_view.leadingAnchor constant:10.0],
			[title_field.trailingAnchor constraintEqualToAnchor:cell_view.trailingAnchor constant:-10.0],
			[subtitle_field.topAnchor constraintEqualToAnchor:title_field.bottomAnchor constant:3.0],
			[subtitle_field.leadingAnchor constraintEqualToAnchor:cell_view.leadingAnchor constant:10.0],
			[subtitle_field.trailingAnchor constraintEqualToAnchor:cell_view.trailingAnchor constant:-10.0],
			bottom_constraint
		]];
	}

	NSDictionary<NSString *, NSString *> *item = self.items[(NSUInteger) row];
	NSTextField *title_field = [cell_view viewWithTag:InkwellSidebarTitleTag];
	NSTextField *subtitle_field = [cell_view viewWithTag:InkwellSidebarSubtitleTag];

	title_field.stringValue = item[@"title"] ?: @"";
	subtitle_field.stringValue = item[@"subtitle"] ?: @"";

	return cell_view;
}

- (CGFloat) tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
	if (row < 0 || row >= self.items.count) {
		return 54.0;
	}

	NSDictionary<NSString *, NSString *> *item = self.items[(NSUInteger) row];
	CGFloat content_width = MAX(120.0, tableView.bounds.size.width - 20.0);

	CGFloat title_height = [self heightForText:item[@"title"] font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold] width:content_width];
	CGFloat subtitle_height = [self heightForText:item[@"subtitle"] font:[NSFont systemFontOfSize:12.0] width:content_width];
	CGFloat row_height = 8.0 + title_height + 3.0 + subtitle_height + 8.0;

	return MAX(50.0, ceil(row_height));
}

- (CGFloat) heightForText:(NSString *)text font:(NSFont *)font width:(CGFloat)width
{
	if (text.length == 0 || font == nil) {
		return 0.0;
	}

	NSRect text_rect = [text boundingRectWithSize:NSMakeSize(width, CGFLOAT_MAX)
		options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
		attributes:@{ NSFontAttributeName: font }];
	return ceil(NSHeight(text_rect));
}

- (void) tableViewSelectionDidChange:(NSNotification *)notification
{
	[self notifySelectionChanged];
}

@end
