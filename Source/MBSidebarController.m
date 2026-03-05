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
static NSInteger const InkwellSidebarSubscriptionTag = 1003;
static NSInteger const InkwellSidebarDateTag = 1004;
static NSString* const InkwellSidebarDateTopWithSubscriptionConstraintIdentifier = @"InkwellSidebarDateTopWithSubscription";
static NSString* const InkwellSidebarDateTopWithoutSubscriptionConstraintIdentifier = @"InkwellSidebarDateTopWithoutSubscription";
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
static CGFloat const InkwellSidebarRecapBoxHeight = 42.0;
static NSTimeInterval const InkwellSidebarRecapPollInterval = 3.0;
static NSInteger const InkwellSidebarRecapMaxAttempts = 20;

@interface MBSidebarTableView : NSTableView

@property (copy, nullable) BOOL (^openSelectedItemHandler)(void);

@end

@implementation MBSidebarTableView

- (void) keyDown:(NSEvent*) event
{
	NSString* characters = event.charactersIgnoringModifiers ?: @"";
	if (characters.length > 0) {
		unichar key_code = [characters characterAtIndex:0];
		BOOL is_return_key = (key_code == NSCarriageReturnCharacter || key_code == NSNewlineCharacter || key_code == NSEnterCharacter);
		if (is_return_key && self.openSelectedItemHandler != nil && self.openSelectedItemHandler()) {
			return;
		}
	}

	[super keyDown:event];
}

@end

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
@property (strong) NSBox* recapBoxView;
@property (strong) NSButton* recapButton;
@property (strong) NSTextField* recapCountLabel;
@property (strong) NSLayoutConstraint* recapBoxHeightConstraint;
@property (strong) NSLayoutConstraint* recapToTableTopConstraint;
@property (assign) BOOL isRecapFetching;
@property (assign) NSInteger recapRequestIdentifier;

- (void) markSelectedItemAsReadIfNeeded:(MBEntry *)item atRow:(NSInteger)row;
- (void) updateCachedReadState:(BOOL)is_read forEntryID:(NSInteger)entry_id;
- (void) reloadRowForEntryID:(NSInteger)entry_id preferredRow:(NSInteger)preferred_row;
- (void) refreshSelectionStylingForSelectedRow:(NSInteger) selected_row;
- (BOOL) openSelectedItemInBrowser;
- (void) updateRecapUI;
- (void) setRecapFetching:(BOOL)is_fetching;
- (NSArray*) fadingItems;
- (NSArray*) fadingEntryIDs;
- (NSString*) recapCountStringForPostsCount:(NSInteger)post_count;
- (NSLayoutConstraint* _Nullable) constraintWithIdentifier:(NSString*) identifier inView:(NSView*) view;
- (IBAction) readingRecapButtonPressed:(id)sender;
- (void) pollReadingRecapForEntryIDs:(NSArray*) entry_ids attempt:(NSInteger)attempt requestIdentifier:(NSInteger)request_identifier;

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

	NSBox* recap_box = [[NSBox alloc] initWithFrame:NSZeroRect];
	recap_box.translatesAutoresizingMaskIntoConstraints = NO;
	recap_box.boxType = NSBoxCustom;
	recap_box.borderColor = [NSColor separatorColor];
	recap_box.borderWidth = 1.0;
	recap_box.cornerRadius = 0.0;
	recap_box.fillColor = [[NSColor controlBackgroundColor] colorWithAlphaComponent:0.5];
	recap_box.hidden = YES;

	NSButton* recap_button = [NSButton buttonWithTitle:@"Reading Recap" target:self action:@selector(readingRecapButtonPressed:)];
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

	MBSidebarTableView *table_view = [[MBSidebarTableView alloc] initWithFrame:NSZeroRect];
	table_view.translatesAutoresizingMaskIntoConstraints = NO;
	table_view.delegate = self;
	table_view.dataSource = self;
	table_view.headerView = nil;
	table_view.allowsEmptySelection = YES;
	table_view.intercellSpacing = NSMakeSize(0.0, 5.0);
	table_view.style = NSTableViewStyleSourceList;
	table_view.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
	__weak typeof(self) weak_self = self;
	table_view.openSelectedItemHandler = ^BOOL {
		return [weak_self openSelectedItemInBrowser];
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

	[container_view addSubview:recap_box];
	[container_view addSubview:scroll_view];
	NSLayoutConstraint* recap_height_constraint = [recap_box.heightAnchor constraintEqualToConstant:0.0];
	NSLayoutConstraint* recap_to_table_top_constraint = [scroll_view.topAnchor constraintEqualToAnchor:recap_box.bottomAnchor constant:0.0];
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
		recap_to_table_top_constraint,
		[scroll_view.bottomAnchor constraintEqualToAnchor:container_view.bottomAnchor],
		[scroll_view.leadingAnchor constraintEqualToAnchor:container_view.leadingAnchor],
		[scroll_view.trailingAnchor constraintEqualToAnchor:container_view.trailingAnchor]
	]];

	self.recapBoxView = recap_box;
	self.recapButton = recap_button;
	self.recapCountLabel = recap_label;
	self.recapBoxHeightConstraint = recap_height_constraint;
	self.recapToTableTopConstraint = recap_to_table_top_constraint;
	self.tableView = table_view;
	self.view = container_view;
	[self updateRecapUI];
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
	__block BOOL did_fetch_icons = NO;
	[self.client fetchFeedEntriesWithToken:self.token completion:^(NSArray<MBSubscription *> * _Nullable subscriptions, NSArray<NSDictionary<NSString *,id> *> * _Nullable entries, NSSet * _Nullable unread_entry_ids, BOOL is_finished, NSError * _Nullable error) {
		if (is_finished) {
			self.isFetching = NO;
		}

		if (error != nil) {
			return;
		}

		NSArray<MBEntry *> *sidebar_items = [self sidebarItemsForEntries:entries ?: @[] subscriptions:subscriptions ?: @[] unreadEntryIDs:unread_entry_ids];
		self.hasLoadedRemoteItems = YES;
		self.allItems = sidebar_items;
		[self applyFiltersAndReload];

		if (!did_fetch_icons) {
			did_fetch_icons = YES;
			[self fetchFeedIcons];
		}
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

- (NSLayoutConstraint* _Nullable) constraintWithIdentifier:(NSString*) identifier inView:(NSView*) view
{
	if (identifier.length == 0 || view == nil) {
		return nil;
	}

	for (NSLayoutConstraint* constraint in view.constraints) {
		if ([constraint.identifier isEqualToString:identifier]) {
			return constraint;
		}
	}

	return nil;
}

- (void) setDateFilter:(MBSidebarDateFilter)date_filter
{
	if (_dateFilter == date_filter) {
		return;
	}

	_dateFilter = date_filter;
	if (_dateFilter != MBSidebarDateFilterFading && self.isRecapFetching) {
		self.recapRequestIdentifier += 1;
		[self setRecapFetching:NO];
	}
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
	[self updateRecapUI];
}

- (void) updateRecapUI
{
	BOOL is_fading_filter = (self.dateFilter == MBSidebarDateFilterFading);
	if (self.recapBoxView != nil) {
		self.recapBoxView.hidden = !is_fading_filter;
	}
	if (self.recapBoxHeightConstraint != nil) {
		self.recapBoxHeightConstraint.constant = is_fading_filter ? InkwellSidebarRecapBoxHeight : 0.0;
	}
	if (self.recapToTableTopConstraint != nil) {
		self.recapToTableTopConstraint.constant = is_fading_filter ? 8.0 : 0.0;
	}

	NSInteger fading_count = [self fadingItems].count;
	if (self.recapCountLabel != nil) {
		self.recapCountLabel.stringValue = [self recapCountStringForPostsCount:fading_count];
	}
	if (self.recapButton != nil) {
		self.recapButton.enabled = is_fading_filter && !self.isRecapFetching && (fading_count > 0);
	}
}

- (void) setRecapFetching:(BOOL)is_fetching
{
	_isRecapFetching = is_fetching;
	[self updateRecapUI];
}

- (NSArray*) fadingItems
{
	return [self filteredItemsForDateFilter:MBSidebarDateFilterFading];
}

- (NSArray*) fadingEntryIDs
{
	NSArray* fading_items = [self fadingItems];
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

- (NSString*) recapCountStringForPostsCount:(NSInteger)post_count
{
	if (post_count == 1) {
		return @"1 older post, grouped";
	}

	return [NSString stringWithFormat:@"%ld older posts, grouped", (long) post_count];
}

- (IBAction) readingRecapButtonPressed:(id)sender
{
	#pragma unused(sender)
	if (self.client == nil || self.token.length == 0) {
		return;
	}

	NSArray* entry_ids = [self fadingEntryIDs];
	if (entry_ids.count == 0) {
		return;
	}

	self.recapRequestIdentifier += 1;
	NSInteger request_identifier = self.recapRequestIdentifier;
	[self setRecapFetching:YES];
	[self pollReadingRecapForEntryIDs:entry_ids attempt:1 requestIdentifier:request_identifier];
}

- (void) pollReadingRecapForEntryIDs:(NSArray*) entry_ids attempt:(NSInteger)attempt requestIdentifier:(NSInteger)request_identifier
{
	if (request_identifier != self.recapRequestIdentifier) {
		return;
	}

	if (attempt > InkwellSidebarRecapMaxAttempts) {
		[self setRecapFetching:NO];
		return;
	}

	[self.client fetchReadingRecapForEntryIDs:entry_ids token:self.token completion:^(NSInteger status_code, NSString* _Nullable html, NSError* _Nullable error) {
		if (request_identifier != self.recapRequestIdentifier) {
			return;
		}

		if (error != nil) {
			[self setRecapFetching:NO];
			return;
		}

		if (status_code == 200) {
			[self setRecapFetching:NO];
			if (self.readingRecapHandler != nil) {
				self.readingRecapHandler(html ?: @"");
			}
			return;
		}

		if (status_code != 202) {
			[self setRecapFetching:NO];
			return;
		}

		if (attempt >= InkwellSidebarRecapMaxAttempts) {
			[self setRecapFetching:NO];
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
		sidebar_entry.url = [self stringValueFromObject:entry[@"url"]];
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
	NSTableCellView* cell_view = [tableView makeViewWithIdentifier:InkwellSidebarCellIdentifier owner:self];

	if (cell_view == nil) {
		cell_view = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
		cell_view.identifier = InkwellSidebarCellIdentifier;

		MBRoundedImageView* avatar_view = [[MBRoundedImageView alloc] initWithFrame:NSZeroRect];
		avatar_view.translatesAutoresizingMaskIntoConstraints = NO;
		avatar_view.tag = InkwellSidebarAvatarTag;

		NSTextField* title_field = [NSTextField labelWithString:@""];
		title_field.translatesAutoresizingMaskIntoConstraints = NO;
		title_field.tag = InkwellSidebarTitleTag;
		title_field.font = [NSFont systemFontOfSize:InkwellSidebarTitleFontSize weight:NSFontWeightSemibold];
		title_field.lineBreakMode = NSLineBreakByWordWrapping;
		title_field.maximumNumberOfLines = 2;

		NSTextField* subtitle_field = [NSTextField labelWithString:@""];
		subtitle_field.translatesAutoresizingMaskIntoConstraints = NO;
		subtitle_field.tag = InkwellSidebarSubtitleTag;
		subtitle_field.font = [NSFont systemFontOfSize:InkwellSidebarSubtitleFontSize];
		subtitle_field.textColor = [NSColor secondaryLabelColor];
		subtitle_field.lineBreakMode = NSLineBreakByWordWrapping;
		subtitle_field.maximumNumberOfLines = 2;

		NSTextField* subscription_field = [NSTextField labelWithString:@""];
		subscription_field.translatesAutoresizingMaskIntoConstraints = NO;
		subscription_field.tag = InkwellSidebarSubscriptionTag;
		subscription_field.font = [NSFont systemFontOfSize:InkwellSidebarSubtitleFontSize];
		subscription_field.textColor = [NSColor secondaryLabelColor];
		subscription_field.lineBreakMode = NSLineBreakByTruncatingTail;
		subscription_field.maximumNumberOfLines = 1;
		subscription_field.hidden = YES;

		NSTextField* date_field = [NSTextField labelWithString:@""];
		date_field.translatesAutoresizingMaskIntoConstraints = NO;
		date_field.tag = InkwellSidebarDateTag;
		date_field.font = [NSFont systemFontOfSize:InkwellSidebarDateFontSize];
		date_field.textColor = [NSColor tertiaryLabelColor];
		date_field.lineBreakMode = NSLineBreakByTruncatingTail;
		date_field.maximumNumberOfLines = 1;

		[cell_view addSubview:avatar_view];
		[cell_view addSubview:title_field];
		[cell_view addSubview:subtitle_field];
		[cell_view addSubview:subscription_field];
		[cell_view addSubview:date_field];

		NSLayoutConstraint* bottom_constraint = [date_field.bottomAnchor constraintLessThanOrEqualToAnchor:cell_view.bottomAnchor constant:-8.0];
		bottom_constraint.priority = NSLayoutPriorityDefaultHigh;

		NSLayoutConstraint* date_top_with_subscription_constraint = [date_field.topAnchor constraintEqualToAnchor:subscription_field.bottomAnchor constant:InkwellSidebarVerticalSpacing];
		date_top_with_subscription_constraint.identifier = InkwellSidebarDateTopWithSubscriptionConstraintIdentifier;
		date_top_with_subscription_constraint.active = NO;

		NSLayoutConstraint* date_top_without_subscription_constraint = [date_field.topAnchor constraintEqualToAnchor:subtitle_field.bottomAnchor constant:InkwellSidebarVerticalSpacing];
		date_top_without_subscription_constraint.identifier = InkwellSidebarDateTopWithoutSubscriptionConstraintIdentifier;
		date_top_without_subscription_constraint.active = YES;

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
			[subscription_field.topAnchor constraintEqualToAnchor:subtitle_field.bottomAnchor constant:InkwellSidebarVerticalSpacing],
			[subscription_field.leadingAnchor constraintEqualToAnchor:title_field.leadingAnchor],
			[subscription_field.trailingAnchor constraintEqualToAnchor:title_field.trailingAnchor],
			date_top_with_subscription_constraint,
			date_top_without_subscription_constraint,
			[date_field.leadingAnchor constraintEqualToAnchor:title_field.leadingAnchor],
			[date_field.trailingAnchor constraintEqualToAnchor:title_field.trailingAnchor],
			bottom_constraint
		]];
	}

	MBEntry* item = self.items[(NSUInteger) row];
	MBRoundedImageView* avatar_view = [cell_view viewWithTag:InkwellSidebarAvatarTag];
	NSTextField* title_field = [cell_view viewWithTag:InkwellSidebarTitleTag];
	NSTextField* subtitle_field = [cell_view viewWithTag:InkwellSidebarSubtitleTag];
	NSTextField* subscription_field = [cell_view viewWithTag:InkwellSidebarSubscriptionTag];
	NSTextField* date_field = [cell_view viewWithTag:InkwellSidebarDateTag];

	NSString* subtitle_value = item.summary;
	if (subtitle_value.length == 0) {
		subtitle_value = item.source ?: @"";
	}
	NSString* date_value = [self displayDateString:item.date];

	NSString* raw_title_value = item.title ?: @"";
	BOOL has_post_title = (raw_title_value.length > 0);
	NSString* title_value = raw_title_value;
	if (!has_post_title) {
		title_value = item.subscriptionTitle ?: @"";
	}

	NSString* subscription_value = has_post_title ? (item.subscriptionTitle ?: @"") : @"";
	BOOL should_show_subscription = (subscription_value.length > 0);

	title_field.stringValue = title_value;
	subtitle_field.stringValue = subtitle_value;
	subscription_field.stringValue = subscription_value;
	subscription_field.hidden = !should_show_subscription;
	date_field.stringValue = date_value;
	avatar_view.image = [self avatarImageForEntry:item];

	NSLayoutConstraint* date_top_with_subscription_constraint = [self constraintWithIdentifier:InkwellSidebarDateTopWithSubscriptionConstraintIdentifier inView:cell_view];
	NSLayoutConstraint* date_top_without_subscription_constraint = [self constraintWithIdentifier:InkwellSidebarDateTopWithoutSubscriptionConstraintIdentifier inView:cell_view];
	if (date_top_with_subscription_constraint != nil && date_top_without_subscription_constraint != nil) {
		date_top_with_subscription_constraint.active = should_show_subscription;
		date_top_without_subscription_constraint.active = !should_show_subscription;
	}

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
		subscription_field.textColor = [selected_text_color colorWithAlphaComponent:0.78];
		date_field.textColor = [selected_text_color colorWithAlphaComponent:0.55];
		avatar_view.alphaValue = 1.0;
		return cell_view;
	}

	if (item.isRead) {
		title_field.textColor = [NSColor disabledControlTextColor];
		subtitle_field.textColor = [NSColor disabledControlTextColor];
		subscription_field.textColor = [NSColor disabledControlTextColor];
		date_field.textColor = [NSColor disabledControlTextColor];
		avatar_view.alphaValue = 0.35;
	}
	else {
		title_field.textColor = [NSColor labelColor];
		subtitle_field.textColor = [NSColor secondaryLabelColor];
		subscription_field.textColor = [NSColor secondaryLabelColor];
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

	NSString* title_value = item.title ?: @"";
	BOOL has_post_title = (title_value.length > 0);
	if (!has_post_title) {
		title_value = item.subscriptionTitle ?: @"";
	}
	NSString* subscription_value = has_post_title ? (item.subscriptionTitle ?: @"") : @"";

	CGFloat title_height = [self heightForText:title_value font:title_font width:content_width maxLines:2];
	CGFloat subtitle_height = [self heightForText:subtitle_value font:subtitle_font width:content_width maxLines:2];
	CGFloat subscription_height = [self heightForText:subscription_value font:subtitle_font width:content_width maxLines:1];
	CGFloat date_height = [self heightForText:date_value font:date_font width:content_width maxLines:1];
	CGFloat row_height = 8.0 + title_height + InkwellSidebarVerticalSpacing + subtitle_height + InkwellSidebarVerticalSpacing;
	if (subscription_height > 0.0) {
		row_height += subscription_height + InkwellSidebarVerticalSpacing;
	}
	row_height += date_height + 8.0;

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
	[self refreshSelectionStylingForSelectedRow:current_selected_row];
	[self notifySelectionChanged];
}

- (void) tableViewSelectionIsChanging:(NSNotification *)notification
{
	#pragma unused(notification)
	NSInteger current_selected_row = self.tableView.selectedRow;
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
		NSIndexSet *column_indexes = [NSIndexSet indexSetWithIndex:0];
		[self.tableView reloadDataForRowIndexes:rows_to_reload columnIndexes:column_indexes];
	}
}

@end
