//
//  MBSidebarController.m
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import "MBSidebarController.h"
#import "MBClient.h"
#import "MBEntry.h"
#import "MBRoundedImageView.h"
#import "MBSubscription.h"

static NSUserInterfaceItemIdentifier const InkwellSidebarCellIdentifier = @"InkwellSidebarCell";
static NSUserInterfaceItemIdentifier const InkwellSidebarRowIdentifier = @"InkwellSidebarRow";
static NSInteger const InkwellSidebarAvatarTag = 1000;
static NSInteger const InkwellSidebarTitleTag = 1001;
static NSInteger const InkwellSidebarSubtitleTag = 1002;
static NSInteger const InkwellSidebarDateTag = 1003;
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

@interface MBSidebarRowView : NSTableRowView

@property (strong) NSColor* customBackgroundColor;

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

- (void) drawBackgroundInRect:(NSRect)dirty_rect
{
	[super drawBackgroundInRect:dirty_rect];
	#pragma unused(dirty_rect)
	if (self.customBackgroundColor == nil) {
		return;
	}

	NSRect fill_rect = NSInsetRect(self.bounds, InkwellSidebarRowBackgroundHorizontalInset, InkwellSidebarRowBackgroundVerticalInset);
	NSBezierPath* background_path = [NSBezierPath bezierPathWithRoundedRect:fill_rect xRadius:10.0 yRadius:10.0];
	[self.customBackgroundColor setFill];
	[background_path fill];
}

@end

@interface MBSidebarController () <NSTableViewDataSource, NSTableViewDelegate>

@property (assign) BOOL hasLoadedRemoteItems;
@property (assign) BOOL isFetching;
@property (assign) NSInteger selectedRowForStyling;
@property (strong) NSTableView *tableView;
@property (copy) NSArray<MBEntry *> *allItems;
@property (copy) NSDictionary<NSString *, NSString *> *iconURLByHost;
@property (strong) NSMutableDictionary<NSString *, NSImage *> *iconImageByHost;
@property (strong) NSMutableSet<NSString *> *hostsWithPendingImageRequests;
@property (strong) NSURLSession *imageSession;
@property (strong) NSImage *defaultAvatarImage;

- (void) markSelectedItemAsReadIfNeeded:(MBEntry *)item atRow:(NSInteger)row;
- (void) updateCachedReadState:(BOOL)is_read forEntryID:(NSInteger)entry_id;
- (void) reloadRowForEntryID:(NSInteger)entry_id preferredRow:(NSInteger)preferred_row;

@end

@implementation MBSidebarController

- (instancetype) init
{
	self = [super initWithNibName:nil bundle:nil];
	if (self) {
		self.dateFilter = MBSidebarDateFilterToday;
		self.searchQuery = @"";
		self.selectedRowForStyling = -1;
		self.allItems = @[];
		self.iconURLByHost = @{};
		self.iconImageByHost = [NSMutableDictionary dictionary];
		self.hostsWithPendingImageRequests = [NSMutableSet set];
		self.imageSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
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
	table_view.allowsEmptySelection = YES;
	table_view.intercellSpacing = NSMakeSize(0.0, 5.0);
	table_view.style = NSTableViewStyleSourceList;
	table_view.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;

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

- (void) reloadData
{
	[self applyFiltersAndReload];
	[self fetchEntriesIfNeeded];
}

- (void) refreshData
{
	self.hasLoadedRemoteItems = NO;
	[self fetchEntriesIfNeeded];
}

- (void) focusAndSelectFirstItem
{
	if (self.tableView == nil) {
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

	[self.view.window makeFirstResponder:self.tableView];
}

- (void) reloadTable
{
	[self.tableView reloadData];
	NSInteger selected_row = self.tableView.selectedRow;
	if (selected_row >= 0 && selected_row < self.items.count) {
		self.selectedRowForStyling = selected_row;
	}
	else {
		self.selectedRowForStyling = -1;
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
	[self.client fetchFeedEntriesWithToken:self.token completion:^(NSArray<MBSubscription *> * _Nullable subscriptions, NSArray<NSDictionary<NSString *,id> *> * _Nullable entries, NSSet * _Nullable unread_entry_ids, NSError * _Nullable error) {
		self.isFetching = NO;
		if (error != nil) {
			return;
		}

		NSArray<MBEntry *> *sidebar_items = [self sidebarItemsForEntries:entries ?: @[] subscriptions:subscriptions ?: @[] unreadEntryIDs:unread_entry_ids];
		self.hasLoadedRemoteItems = YES;
		self.allItems = sidebar_items;
		[self applyFiltersAndReload];
		[self fetchFeedIcons];
	}];
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
		[self.iconImageByHost removeAllObjects];
		[self.hostsWithPendingImageRequests removeAllObjects];
		[self.tableView reloadData];
	}];
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
	NSString *feed_host = [self normalizedHostString:entry.feedHost ?: @""];
	if (feed_host.length == 0) {
		return [self fallbackAvatarImage];
	}

	NSImage *cached_image = self.iconImageByHost[feed_host];
	if (cached_image != nil) {
		return cached_image;
	}

	NSString *icon_url_string = self.iconURLByHost[feed_host];
	if (icon_url_string.length > 0) {
		[self requestAvatarImageForHost:feed_host urlString:icon_url_string];
	}

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

- (void) requestAvatarImageForHost:(NSString *)host_value urlString:(NSString *)url_string
{
	if (host_value.length == 0 || url_string.length == 0) {
		return;
	}

	if (self.iconImageByHost[host_value] != nil || [self.hostsWithPendingImageRequests containsObject:host_value]) {
		return;
	}

	NSURL *image_url = [NSURL URLWithString:url_string];
	if (image_url == nil) {
		return;
	}

	[self.hostsWithPendingImageRequests addObject:host_value];

	NSURLSessionDataTask *task = [self.imageSession dataTaskWithURL:image_url completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
		#pragma unused(response)
		NSImage *image_value = nil;
		if (error == nil && data.length > 0) {
			image_value = [[NSImage alloc] initWithData:data];
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			[self.hostsWithPendingImageRequests removeObject:host_value];

			if (image_value == nil) {
				return;
			}

			self.iconImageByHost[host_value] = image_value;
			[self reloadRowsForHost:host_value];
		});
	}];
	[task resume];
}

- (void) reloadRowsForHost:(NSString *)host_value
{
	if (host_value.length == 0 || self.items.count == 0) {
		return;
	}

	NSMutableIndexSet *row_indexes = [NSMutableIndexSet indexSet];
	NSUInteger item_count = self.items.count;
	for (NSUInteger i = 0; i < item_count; i++) {
		MBEntry *entry = self.items[i];
		NSString *entry_host = [self normalizedHostString:entry.feedHost ?: @""];
		if ([entry_host isEqualToString:host_value]) {
			[row_indexes addIndex:i];
		}
	}

	if (row_indexes.count == 0) {
		return;
	}

	NSIndexSet *column_indexes = [NSIndexSet indexSetWithIndex:0];
	[self.tableView reloadDataForRowIndexes:row_indexes columnIndexes:column_indexes];
}

- (void) setDateFilter:(MBSidebarDateFilter)date_filter
{
	if (_dateFilter == date_filter) {
		return;
	}

	_dateFilter = date_filter;
	[self applyFiltersAndReload];
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

	_searchQuery = [normalized_query copy];
	[self applyFiltersAndReload];
}

- (void) applyFiltersAndReload
{
	if (self.searchQuery.length > 0) {
		self.items = [self filteredItemsForSearchQuery:self.searchQuery];
	}
	else {
		self.items = [self filteredItemsForDateFilter:self.dateFilter];
	}

	[self reloadTable];
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
		NSString *title_value = [self normalizedPreviewString:[self stringValueFromObject:entry[@"title"]]];
		NSString *summary_value = [self normalizedPreviewString:[self stringValueFromObject:entry[@"summary"]]];
		NSString *author_value = [self normalizedPreviewString:[self stringValueFromObject:entry[@"author"]]];
		NSString *content_html_value = [self stringValueFromObject:entry[@"content_html"]];
		if (content_html_value.length == 0) {
			content_html_value = [self stringValueFromObject:entry[@"content"]];
		}
		NSString *source_value = [self normalizedPreviewString:[self stringValueFromObject:entry[@"source"]]];
		NSDate *entry_date = [self dateValueFromEntry:entry];
		NSInteger entry_id_value = [self integerValueFromObject:entry[@"id"]];
		id read_object = entry[@"is_read"] ?: entry[@"read"];
		BOOL is_read_value = [self boolValueFromObject:read_object];
		if (unread_entry_ids != nil && entry_id_value > 0) {
			is_read_value = ![unread_entry_ids containsObject:@(entry_id_value)];
		}
		NSInteger feed_id_value = [self integerValueFromObject:entry[@"feed_id"]];
		NSString *subscription_title = subscription_titles_by_feed_id[@(feed_id_value)] ?: @"";
		NSString *feed_host = feed_hosts_by_feed_id[@(feed_id_value)] ?: @"";

		NSString *resolved_source = source_value;
		if (resolved_source.length == 0) {
			resolved_source = author_value;
		}
		if (resolved_source.length == 0) {
			resolved_source = @"";
		}

		MBEntry *sidebar_entry = [[MBEntry alloc] init];
		sidebar_entry.title = title_value;
		sidebar_entry.subscriptionTitle = subscription_title;
		sidebar_entry.summary = summary_value;
		sidebar_entry.text = content_html_value;
		sidebar_entry.source = resolved_source;
		sidebar_entry.entryID = entry_id_value;
		sidebar_entry.feedID = feed_id_value;
		sidebar_entry.feedHost = feed_host;
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

- (void) notifySelectionChanged
{
	NSInteger selected_row = self.tableView.selectedRow;
	if (selected_row >= 0 && selected_row < self.items.count) {
		MBEntry *item = self.items[(NSUInteger) selected_row];
		[self markSelectedItemAsReadIfNeeded:item atRow:selected_row];
		if (self.selectionChangedHandler != nil) {
			self.selectionChangedHandler(item);
		}
		return;
	}

	if (self.selectionChangedHandler != nil) {
		self.selectionChangedHandler(nil);
	}
}

- (void) markSelectedItemAsReadIfNeeded:(MBEntry *)item atRow:(NSInteger)row
{
	if (item == nil || item.isRead || item.entryID <= 0) {
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
		[self reloadRowForEntryID:entry_id preferredRow:row];
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

	BOOL is_selected_row = (row == self.selectedRowForStyling);
	if (!is_selected_row) {
		is_selected_row = (tableView.selectedRow == row);
	}
	if (!is_selected_row) {
		is_selected_row = [tableView isRowSelected:row];
	}

	if (is_selected_row || row < 0 || row >= self.items.count) {
		row_view.customBackgroundColor = nil;
		return row_view;
	}

	MBEntry* item = self.items[(NSUInteger) row];
	if (item.isRead) {
		row_view.customBackgroundColor = nil;
	}
	else {
		row_view.customBackgroundColor = [NSColor colorWithRed:0.93 green:0.96 blue:1.0 alpha:0.85];
	}

	return row_view;
}

- (NSView *) tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	#pragma unused(tableColumn)
	NSTableCellView *cell_view = [tableView makeViewWithIdentifier:InkwellSidebarCellIdentifier owner:self];

	if (cell_view == nil) {
		cell_view = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
		cell_view.identifier = InkwellSidebarCellIdentifier;

		MBRoundedImageView *avatar_view = [[MBRoundedImageView alloc] initWithFrame:NSZeroRect];
		avatar_view.translatesAutoresizingMaskIntoConstraints = NO;
		avatar_view.tag = InkwellSidebarAvatarTag;

		NSTextField *title_field = [NSTextField labelWithString:@""];
		title_field.translatesAutoresizingMaskIntoConstraints = NO;
		title_field.tag = InkwellSidebarTitleTag;
		title_field.font = [NSFont systemFontOfSize:InkwellSidebarTitleFontSize weight:NSFontWeightSemibold];
		title_field.lineBreakMode = NSLineBreakByWordWrapping;
		title_field.maximumNumberOfLines = 2;

		NSTextField *subtitle_field = [NSTextField labelWithString:@""];
		subtitle_field.translatesAutoresizingMaskIntoConstraints = NO;
		subtitle_field.tag = InkwellSidebarSubtitleTag;
		subtitle_field.font = [NSFont systemFontOfSize:InkwellSidebarSubtitleFontSize];
		subtitle_field.textColor = [NSColor secondaryLabelColor];
		subtitle_field.lineBreakMode = NSLineBreakByWordWrapping;
		subtitle_field.maximumNumberOfLines = 2;

		NSTextField *date_field = [NSTextField labelWithString:@""];
		date_field.translatesAutoresizingMaskIntoConstraints = NO;
		date_field.tag = InkwellSidebarDateTag;
		date_field.font = [NSFont systemFontOfSize:InkwellSidebarDateFontSize];
		date_field.textColor = [NSColor tertiaryLabelColor];
		date_field.lineBreakMode = NSLineBreakByTruncatingTail;
		date_field.maximumNumberOfLines = 1;

		[cell_view addSubview:avatar_view];
		[cell_view addSubview:title_field];
		[cell_view addSubview:subtitle_field];
		[cell_view addSubview:date_field];

		NSLayoutConstraint *bottom_constraint = [date_field.bottomAnchor constraintLessThanOrEqualToAnchor:cell_view.bottomAnchor constant:-8.0];
		bottom_constraint.priority = NSLayoutPriorityDefaultHigh;

		[NSLayoutConstraint activateConstraints:@[
			[avatar_view.leadingAnchor constraintEqualToAnchor:cell_view.leadingAnchor constant:InkwellSidebarAvatarInset],
			[avatar_view.topAnchor constraintEqualToAnchor:cell_view.topAnchor constant:8.0],
			[avatar_view.widthAnchor constraintEqualToConstant:InkwellSidebarAvatarSize],
			[avatar_view.heightAnchor constraintEqualToConstant:InkwellSidebarAvatarSize],
			[title_field.topAnchor constraintEqualToAnchor:cell_view.topAnchor constant:8.0],
			[title_field.leadingAnchor constraintEqualToAnchor:avatar_view.trailingAnchor constant:InkwellSidebarTextInset],
			[title_field.trailingAnchor constraintEqualToAnchor:cell_view.trailingAnchor constant:-InkwellSidebarRightInset],
			[subtitle_field.topAnchor constraintEqualToAnchor:title_field.bottomAnchor constant:InkwellSidebarVerticalSpacing],
			[subtitle_field.leadingAnchor constraintEqualToAnchor:title_field.leadingAnchor],
			[subtitle_field.trailingAnchor constraintEqualToAnchor:title_field.trailingAnchor],
			[date_field.topAnchor constraintEqualToAnchor:subtitle_field.bottomAnchor constant:InkwellSidebarVerticalSpacing],
			[date_field.leadingAnchor constraintEqualToAnchor:title_field.leadingAnchor],
			[date_field.trailingAnchor constraintEqualToAnchor:title_field.trailingAnchor],
			bottom_constraint
		]];
	}

	MBEntry *item = self.items[(NSUInteger) row];
	MBRoundedImageView *avatar_view = [cell_view viewWithTag:InkwellSidebarAvatarTag];
	NSTextField *title_field = [cell_view viewWithTag:InkwellSidebarTitleTag];
	NSTextField *subtitle_field = [cell_view viewWithTag:InkwellSidebarSubtitleTag];
	NSTextField *date_field = [cell_view viewWithTag:InkwellSidebarDateTag];
	NSString *subtitle_value = item.summary;
	if (subtitle_value.length == 0) {
		subtitle_value = item.source ?: @"";
	}
	NSString *date_value = [self displayDateString:item.date];

	NSString *title_value = item.title ?: @"";
	if (title_value.length == 0) {
		title_value = item.subscriptionTitle ?: @"";
	}

	title_field.stringValue = title_value;
	subtitle_field.stringValue = subtitle_value;
	date_field.stringValue = date_value;
	avatar_view.image = [self avatarImageForEntry:item];

	BOOL is_selected_row = (row == self.selectedRowForStyling);
	if (!is_selected_row) {
		is_selected_row = (tableView.selectedRow == row);
	}
	if (!is_selected_row) {
		is_selected_row = [tableView isRowSelected:row];
	}
	if (is_selected_row) {
		NSColor* selected_text_color = [NSColor alternateSelectedControlTextColor];
		title_field.textColor = selected_text_color;
		subtitle_field.textColor = [selected_text_color colorWithAlphaComponent:0.78];
		date_field.textColor = [selected_text_color colorWithAlphaComponent:0.55];
		avatar_view.alphaValue = 1.0;
		return cell_view;
	}

	if (item.isRead) {
		title_field.textColor = [NSColor disabledControlTextColor];
		subtitle_field.textColor = [NSColor disabledControlTextColor];
		date_field.textColor = [NSColor disabledControlTextColor];
		avatar_view.alphaValue = 0.35;
	}
	else {
		title_field.textColor = [NSColor labelColor];
		subtitle_field.textColor = [NSColor secondaryLabelColor];
		date_field.textColor = [NSColor tertiaryLabelColor];
		avatar_view.alphaValue = 1.0;
	}

	return cell_view;
}

- (CGFloat) tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
	if (row < 0 || row >= self.items.count) {
		return 54.0;
	}

	MBEntry *item = self.items[(NSUInteger) row];
	CGFloat content_width = MAX(120.0, tableView.bounds.size.width - (InkwellSidebarAvatarInset + InkwellSidebarAvatarSize + InkwellSidebarTextInset + InkwellSidebarRightInset));
	NSString *subtitle_value = item.summary;
	if (subtitle_value.length == 0) {
		subtitle_value = item.source ?: @"";
	}
	NSString *date_value = [self displayDateString:item.date];
	NSFont *title_font = [NSFont systemFontOfSize:InkwellSidebarTitleFontSize weight:NSFontWeightSemibold];
	NSFont *subtitle_font = [NSFont systemFontOfSize:InkwellSidebarSubtitleFontSize];
	NSFont *date_font = [NSFont systemFontOfSize:InkwellSidebarDateFontSize];

	NSString *title_value = item.title ?: @"";
	if (title_value.length == 0) {
		title_value = item.subscriptionTitle ?: @"";
	}

	CGFloat title_height = [self heightForText:title_value font:title_font width:content_width maxLines:2];
	CGFloat subtitle_height = [self heightForText:subtitle_value font:subtitle_font width:content_width maxLines:2];
	CGFloat date_height = [self heightForText:date_value font:date_font width:content_width maxLines:1];
	CGFloat row_height = 8.0 + title_height + InkwellSidebarVerticalSpacing + subtitle_height + InkwellSidebarVerticalSpacing + date_height + 8.0;

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

- (void) tableViewSelectionDidChange:(NSNotification *)notification
{
	#pragma unused(notification)
	NSInteger current_selected_row = self.tableView.selectedRow;
	NSMutableIndexSet *rows_to_reload = [NSMutableIndexSet indexSet];
	if (self.selectedRowForStyling >= 0 && self.selectedRowForStyling < self.items.count) {
		[rows_to_reload addIndex:(NSUInteger) self.selectedRowForStyling];
	}
	if (current_selected_row >= 0 && current_selected_row < self.items.count) {
		[rows_to_reload addIndex:(NSUInteger) current_selected_row];
	}

	self.selectedRowForStyling = current_selected_row;

	if (rows_to_reload.count > 0) {
		NSIndexSet *column_indexes = [NSIndexSet indexSetWithIndex:0];
		[self.tableView reloadDataForRowIndexes:rows_to_reload columnIndexes:column_indexes];
	}

	[self notifySelectionChanged];
}

@end
