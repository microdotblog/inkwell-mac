//
//  MBSidebarController.m
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import "MBSidebarController.h"
#import "MBClient.h"
#import "MBEntry.h"

static NSUserInterfaceItemIdentifier const InkwellSidebarCellIdentifier = @"InkwellSidebarCell";
static NSInteger const InkwellSidebarTitleTag = 1001;
static NSInteger const InkwellSidebarSubtitleTag = 1002;
static NSInteger const InkwellSidebarDateTag = 1003;

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
	table_view.intercellSpacing = NSMakeSize(0.0, 2.0);
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

		NSArray<MBEntry *> *sidebar_items = [self sidebarItemsForEntries:entries ?: @[]];
		self.hasLoadedRemoteItems = YES;
		self.items = sidebar_items;
		[self reloadTableAndSelectFirstItem];
	}];
}

- (NSArray<MBEntry *> *) sidebarItemsForEntries:(NSArray<NSDictionary<NSString *, id> *> *)entries
{
	NSMutableArray<MBEntry *> *sidebar_items = [NSMutableArray array];

	for (NSDictionary<NSString *, id> *entry in entries) {
		NSString *title_value = [self normalizedPreviewString:[self stringValueFromObject:entry[@"title"]]];
		NSString *summary_value = [self normalizedPreviewString:[self stringValueFromObject:entry[@"summary"]]];
		NSString *author_value = [self normalizedPreviewString:[self stringValueFromObject:entry[@"author"]]];
		NSString *url_value = [self stringValueFromObject:entry[@"url"]];
		NSString *content_html_value = [self stringValueFromObject:entry[@"content_html"]];
		if (content_html_value.length == 0) {
			content_html_value = [self stringValueFromObject:entry[@"content"]];
		}
		NSString *source_value = [self normalizedPreviewString:[self stringValueFromObject:entry[@"source"]]];
		NSDate *entry_date = [self dateValueFromEntry:entry];
		id read_object = entry[@"is_read"] ?: entry[@"read"];
		BOOL is_read_value = [self boolValueFromObject:read_object];

		NSString *resolved_title = title_value;
		if (resolved_title.length == 0) {
			resolved_title = url_value.length > 0 ? url_value : @"Untitled";
		}

		NSString *resolved_source = source_value;
		if (resolved_source.length == 0) {
			resolved_source = author_value;
		}
		if (resolved_source.length == 0) {
			resolved_source = @"";
		}

		MBEntry *sidebar_entry = [[MBEntry alloc] init];
		sidebar_entry.title = resolved_title;
		sidebar_entry.summary = summary_value;
		sidebar_entry.text = content_html_value;
		sidebar_entry.source = resolved_source;
		sidebar_entry.date = entry_date;
		sidebar_entry.isRead = is_read_value;

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

- (void) notifySelectionChanged
{
	if (self.selectionChangedHandler == nil) {
		return;
	}

	NSInteger selected_row = self.tableView.selectedRow;
	if (selected_row >= 0 && selected_row < self.items.count) {
		MBEntry *item = self.items[(NSUInteger) selected_row];
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
		subtitle_field.maximumNumberOfLines = 2;

		NSTextField *date_field = [NSTextField labelWithString:@""];
		date_field.translatesAutoresizingMaskIntoConstraints = NO;
		date_field.tag = InkwellSidebarDateTag;
		date_field.font = [NSFont systemFontOfSize:11.0];
		date_field.textColor = [NSColor tertiaryLabelColor];
		date_field.lineBreakMode = NSLineBreakByTruncatingTail;
		date_field.maximumNumberOfLines = 1;

		[cell_view addSubview:title_field];
		[cell_view addSubview:subtitle_field];
		[cell_view addSubview:date_field];

		NSLayoutConstraint *bottom_constraint = [date_field.bottomAnchor constraintLessThanOrEqualToAnchor:cell_view.bottomAnchor constant:-8.0];
		bottom_constraint.priority = NSLayoutPriorityDefaultHigh;

		[NSLayoutConstraint activateConstraints:@[
			[title_field.topAnchor constraintEqualToAnchor:cell_view.topAnchor constant:8.0],
			[title_field.leadingAnchor constraintEqualToAnchor:cell_view.leadingAnchor constant:10.0],
			[title_field.trailingAnchor constraintEqualToAnchor:cell_view.trailingAnchor constant:-10.0],
			[subtitle_field.topAnchor constraintEqualToAnchor:title_field.bottomAnchor constant:3.0],
			[subtitle_field.leadingAnchor constraintEqualToAnchor:cell_view.leadingAnchor constant:10.0],
			[subtitle_field.trailingAnchor constraintEqualToAnchor:cell_view.trailingAnchor constant:-10.0],
			[date_field.topAnchor constraintEqualToAnchor:subtitle_field.bottomAnchor constant:3.0],
			[date_field.leadingAnchor constraintEqualToAnchor:cell_view.leadingAnchor constant:10.0],
			[date_field.trailingAnchor constraintEqualToAnchor:cell_view.trailingAnchor constant:-10.0],
			bottom_constraint
		]];
	}

	MBEntry *item = self.items[(NSUInteger) row];
	NSTextField *title_field = [cell_view viewWithTag:InkwellSidebarTitleTag];
	NSTextField *subtitle_field = [cell_view viewWithTag:InkwellSidebarSubtitleTag];
	NSTextField *date_field = [cell_view viewWithTag:InkwellSidebarDateTag];
	NSString *subtitle_value = item.summary;
	if (subtitle_value.length == 0) {
		subtitle_value = item.source ?: @"";
	}
	NSString *date_value = [self displayDateString:item.date];

	title_field.stringValue = item.title ?: @"";
	subtitle_field.stringValue = subtitle_value;
	date_field.stringValue = date_value;

	return cell_view;
}

- (CGFloat) tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
	if (row < 0 || row >= self.items.count) {
		return 54.0;
	}

	MBEntry *item = self.items[(NSUInteger) row];
	CGFloat content_width = MAX(120.0, tableView.bounds.size.width - 20.0);
	NSString *subtitle_value = item.summary;
	if (subtitle_value.length == 0) {
		subtitle_value = item.source ?: @"";
	}
	NSString *date_value = [self displayDateString:item.date];
	NSFont *title_font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
	NSFont *subtitle_font = [NSFont systemFontOfSize:12.0];
	NSFont *date_font = [NSFont systemFontOfSize:11.0];

	CGFloat title_height = [self heightForText:item.title ?: @"" font:title_font width:content_width maxLines:2];
	CGFloat subtitle_height = [self heightForText:subtitle_value font:subtitle_font width:content_width maxLines:2];
	CGFloat date_height = [self heightForText:date_value font:date_font width:content_width maxLines:1];
	CGFloat row_height = 6.0 + title_height + 2.0 + subtitle_height + 2.0 + date_height + 6.0;

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
	NSString *published_value = [self stringValueFromObject:entry[@"date_published"]];
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

- (NSString *) displayDateString:(NSDate * _Nullable)date
{
	if (date == nil) {
		return @"";
	}

	static NSDateFormatter *date_formatter;
	static dispatch_once_t once_token;
	dispatch_once(&once_token, ^{
		date_formatter = [[NSDateFormatter alloc] init];
		date_formatter.dateStyle = NSDateFormatterMediumStyle;
		date_formatter.timeStyle = NSDateFormatterShortStyle;
	});

	return [date_formatter stringFromDate:date];
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

- (void) tableViewSelectionDidChange:(NSNotification *)notification
{
	[self notifySelectionChanged];
}

@end
