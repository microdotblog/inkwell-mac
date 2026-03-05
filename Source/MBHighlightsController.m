//
//  MBHighlightsController.m
//  Inkwell
//
//  Created by Codex on 3/4/26.
//

#import "MBHighlightsController.h"
#import "MBClient.h"
#import "MBEntry.h"
#import "MBHighlight.h"
#import "MBHighlightCellView.h"

static NSUserInterfaceItemIdentifier const InkwellHighlightsCellIdentifier = @"InkwellHighlightsCell";
static CGFloat const InkwellHighlightsTopBarHeight = 44.0;
static CGFloat const InkwellHighlightsAvatarSize = 20.0;

@interface MBHighlightsController () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) MBClient* client;
@property (nonatomic, copy) NSString* token;
@property (nonatomic, assign, readwrite) NSInteger entryID;
@property (nonatomic, copy) NSArray* highlights;
@property (nonatomic, strong) NSTableView* tableView;
@property (nonatomic, strong) NSImageView* avatarImageView;
@property (nonatomic, strong) NSTextField* titleTextField;
@property (nonatomic, strong) NSProgressIndicator* progressIndicator;
@property (nonatomic, copy) NSString* headerTitle;
@property (nonatomic, strong) NSImage* headerAvatarImage;
@property (nonatomic, copy) NSString* headerFeedHost;
@property (nonatomic, copy) NSDictionary<NSString*, NSString*>* iconURLByHost;
@property (nonatomic, strong) NSMutableDictionary<NSString*, NSImage*>* iconImageByHost;
@property (nonatomic, strong) NSMutableSet<NSString*>* hostsWithPendingImageRequests;
@property (nonatomic, strong) NSURLSession* imageSession;
@property (nonatomic, assign) BOOL hasLoadedFeedIcons;
@property (nonatomic, assign) BOOL isFetchingFeedIcons;
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
		self.headerTitle = @"Highlights";
		self.headerAvatarImage = [self defaultAvatarImage];
		self.headerFeedHost = @"";
		self.iconURLByHost = @{};
		self.iconImageByHost = [NSMutableDictionary dictionary];
		self.hostsWithPendingImageRequests = [NSMutableSet set];
		self.imageSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
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

- (void) showHighlightsForEntry:(MBEntry*) entry
{
	if (entry == nil || entry.entryID <= 0) {
		return;
	}

	[self updateForSelectedEntry:entry];
	[self showWindow:nil];
	[self reloadHighlights];
}

- (void) showHighlightsForEntryID:(NSInteger) entry_id
{
	if (entry_id <= 0) {
		return;
	}

	self.entryID = entry_id;
	self.headerTitle = [NSString stringWithFormat:@"Post %ld", (long) entry_id];
	self.headerFeedHost = @"";
	self.headerAvatarImage = [self defaultAvatarImage];
	[self showWindow:nil];
	[self applyHeaderIfNeeded];
	[self reloadHighlights];
}

- (void) updateForSelectedEntry:(MBEntry* _Nullable) entry
{
	if (entry == nil || entry.entryID <= 0) {
		self.entryID = 0;
		self.headerTitle = @"Highlights";
		self.headerFeedHost = @"";
		self.headerAvatarImage = [self defaultAvatarImage];
		[self setFetchingState:NO];
		self.highlights = @[];
		[self applyHeaderIfNeeded];
		[self.tableView reloadData];
		return;
	}

	self.entryID = entry.entryID;
	[self updateHeaderForEntry:entry];

	if (self.window.isVisible) {
		[self reloadHighlights];
	}
}

- (void) reloadHighlights
{
	if (self.entryID <= 0 || self.client == nil || self.token.length == 0) {
		[self setFetchingState:NO];
		self.highlights = @[];
		[self.tableView reloadData];
		return;
	}

	if (self.isFetching) {
		return;
	}

	[self setFetchingState:YES];
	[self.client fetchHighlightsForEntryID:self.entryID token:self.token completion:^(NSArray* _Nullable highlights, NSError* _Nullable error) {
		[self setFetchingState:NO];
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
	panel.hidesOnDeactivate = YES;
	panel.level = NSFloatingWindowLevel;
	panel.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace;
	panel.releasedWhenClosed = NO;
	panel.minSize = NSMakeSize(300.0, 220.0);
	panel.title = @"Highlights";
	[panel setFrameAutosaveName:@"HighlightsWindow"];
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

	NSView* top_container_view = [[NSView alloc] initWithFrame:NSZeroRect];
	top_container_view.translatesAutoresizingMaskIntoConstraints = NO;
	top_container_view.wantsLayer = YES;
	top_container_view.layer.backgroundColor = NSColor.secondarySystemFillColor.CGColor;

	NSImageView* avatar_image_view = [[NSImageView alloc] initWithFrame:NSZeroRect];
	avatar_image_view.translatesAutoresizingMaskIntoConstraints = NO;
	avatar_image_view.imageScaling = NSImageScaleAxesIndependently;
	avatar_image_view.wantsLayer = YES;
	avatar_image_view.layer.cornerRadius = (InkwellHighlightsAvatarSize / 2.0);
	avatar_image_view.layer.masksToBounds = YES;

	NSTextField* title_text_field = [NSTextField labelWithString:@""];
	title_text_field.translatesAutoresizingMaskIntoConstraints = NO;
	title_text_field.lineBreakMode = NSLineBreakByTruncatingTail;
	title_text_field.maximumNumberOfLines = 1;
	title_text_field.usesSingleLineMode = YES;
	title_text_field.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
	[title_text_field setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
	[title_text_field setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

	NSProgressIndicator* progress_indicator = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
	progress_indicator.translatesAutoresizingMaskIntoConstraints = NO;
	progress_indicator.style = NSProgressIndicatorStyleSpinning;
	progress_indicator.controlSize = NSControlSizeSmall;
	progress_indicator.indeterminate = YES;
	progress_indicator.displayedWhenStopped = NO;
	progress_indicator.hidden = YES;
	[progress_indicator setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

	[top_container_view addSubview:avatar_image_view];
	[top_container_view addSubview:title_text_field];
	[top_container_view addSubview:progress_indicator];

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

	[content_view addSubview:top_container_view];
	[content_view addSubview:scroll_view];
	[NSLayoutConstraint activateConstraints:@[
		[top_container_view.topAnchor constraintEqualToAnchor:content_view.topAnchor],
		[top_container_view.leadingAnchor constraintEqualToAnchor:content_view.leadingAnchor],
		[top_container_view.trailingAnchor constraintEqualToAnchor:content_view.trailingAnchor],
		[top_container_view.heightAnchor constraintEqualToConstant:InkwellHighlightsTopBarHeight],
		[avatar_image_view.leadingAnchor constraintEqualToAnchor:top_container_view.leadingAnchor constant:10.0],
		[avatar_image_view.centerYAnchor constraintEqualToAnchor:top_container_view.centerYAnchor],
		[avatar_image_view.widthAnchor constraintEqualToConstant:InkwellHighlightsAvatarSize],
		[avatar_image_view.heightAnchor constraintEqualToConstant:InkwellHighlightsAvatarSize],
		[progress_indicator.trailingAnchor constraintEqualToAnchor:top_container_view.trailingAnchor constant:-10.0],
		[progress_indicator.centerYAnchor constraintEqualToAnchor:top_container_view.centerYAnchor],
		[title_text_field.leadingAnchor constraintEqualToAnchor:avatar_image_view.trailingAnchor constant:8.0],
		[title_text_field.trailingAnchor constraintLessThanOrEqualToAnchor:progress_indicator.leadingAnchor constant:-10.0],
		[title_text_field.centerYAnchor constraintEqualToAnchor:top_container_view.centerYAnchor],
		[scroll_view.topAnchor constraintEqualToAnchor:top_container_view.bottomAnchor],
		[scroll_view.bottomAnchor constraintEqualToAnchor:content_view.bottomAnchor],
		[scroll_view.leadingAnchor constraintEqualToAnchor:content_view.leadingAnchor],
		[scroll_view.trailingAnchor constraintEqualToAnchor:content_view.trailingAnchor]
	]];

	self.tableView = table_view;
	self.avatarImageView = avatar_image_view;
	self.titleTextField = title_text_field;
	self.progressIndicator = progress_indicator;
	self.didSetupContent = YES;
	[self applyHeaderIfNeeded];
	[self updateProgressIndicator];
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

- (void) updateHeaderForEntry:(MBEntry*) entry
{
	NSString* title_string = [entry.title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (title_string.length == 0) {
		title_string = [entry.subscriptionTitle stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	}
	if (title_string.length == 0) {
		title_string = [NSString stringWithFormat:@"Post %ld", (long) entry.entryID];
	}

	self.headerTitle = title_string;
	self.headerFeedHost = [self normalizedHostString:entry.feedHost ?: @""];
	self.headerAvatarImage = [self avatarImageForHost:self.headerFeedHost];
	[self applyHeaderIfNeeded];
	[self fetchFeedIconsIfNeeded];
}

- (void) applyHeaderIfNeeded
{
	if (self.titleTextField != nil) {
		self.titleTextField.stringValue = self.headerTitle ?: @"Highlights";
	}

	if (self.avatarImageView != nil) {
		self.avatarImageView.image = self.headerAvatarImage ?: [self defaultAvatarImage];
	}
}

- (void) fetchFeedIconsIfNeeded
{
	if (self.client == nil || self.token.length == 0) {
		return;
	}

	if (self.hasLoadedFeedIcons || self.isFetchingFeedIcons) {
		return;
	}

	self.isFetchingFeedIcons = YES;
	[self.client fetchFeedIconsWithToken:self.token completion:^(NSDictionary<NSString *,NSString *> * _Nullable icons_by_host, NSError * _Nullable error) {
		self.isFetchingFeedIcons = NO;
		if (error != nil) {
			return;
		}

		self.iconURLByHost = [self normalizedIconURLByHostFromMap:icons_by_host ?: @{}];
		self.hasLoadedFeedIcons = YES;
		[self updateHeaderAvatarImage];
	}];
}

- (void) updateHeaderAvatarImage
{
	self.headerAvatarImage = [self avatarImageForHost:self.headerFeedHost];
	[self applyHeaderIfNeeded];
}

- (NSDictionary<NSString*, NSString*>*) normalizedIconURLByHostFromMap:(NSDictionary<NSString*, NSString*>*) icons_by_host
{
	if (icons_by_host.count == 0) {
		return @{};
	}

	NSMutableDictionary<NSString*, NSString*>* normalized_icons_by_host = [NSMutableDictionary dictionary];
	for (NSString* host_value in icons_by_host) {
		NSString* normalized_host = [self normalizedHostString:host_value];
		if (normalized_host.length == 0) {
			continue;
		}

		NSString* url_value = icons_by_host[host_value];
		if (url_value.length == 0) {
			continue;
		}

		normalized_icons_by_host[normalized_host] = url_value;
	}

	return [normalized_icons_by_host copy];
}

- (NSString*) normalizedHostString:(NSString*) host_string
{
	if (host_string.length == 0) {
		return @"";
	}

	NSString* normalized_host = [[host_string lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([normalized_host hasPrefix:@"www."]) {
		normalized_host = [normalized_host substringFromIndex:4];
	}
	if ([normalized_host hasSuffix:@"."]) {
		normalized_host = [normalized_host substringToIndex:(normalized_host.length - 1)];
	}

	return normalized_host;
}

- (NSImage*) avatarImageForHost:(NSString*) host_value
{
	if (host_value.length == 0) {
		return [self defaultAvatarImage];
	}

	NSImage* cached_image = self.iconImageByHost[host_value];
	if (cached_image != nil) {
		return cached_image;
	}

	NSString* icon_url_string = self.iconURLByHost[host_value];
	if (icon_url_string.length > 0) {
		[self requestAvatarImageForHost:host_value urlString:icon_url_string];
	}

	return [self defaultAvatarImage];
}

- (void) requestAvatarImageForHost:(NSString*) host_value urlString:(NSString*) url_string
{
	if (host_value.length == 0 || url_string.length == 0) {
		return;
	}

	if (self.iconImageByHost[host_value] != nil || [self.hostsWithPendingImageRequests containsObject:host_value]) {
		return;
	}

	NSURL* image_url = [NSURL URLWithString:url_string];
	if (image_url == nil) {
		return;
	}

	[self.hostsWithPendingImageRequests addObject:host_value];

	NSURLSessionDataTask* task = [self.imageSession dataTaskWithURL:image_url completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
		#pragma unused(response)
		NSImage* image_value = nil;
		if (error == nil && data.length > 0) {
			image_value = [[NSImage alloc] initWithData:data];
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			[self.hostsWithPendingImageRequests removeObject:host_value];
			if (image_value == nil) {
				return;
			}

			self.iconImageByHost[host_value] = image_value;
			if ([self.headerFeedHost isEqualToString:host_value]) {
				[self updateHeaderAvatarImage];
			}
		});
	}];
	[task resume];
}

- (NSImage*) defaultAvatarImage
{
	static NSImage* fallback_image;
	static dispatch_once_t once_token;
	dispatch_once(&once_token, ^{
		NSSize image_size = NSMakeSize(InkwellHighlightsAvatarSize, InkwellHighlightsAvatarSize);
		fallback_image = [[NSImage alloc] initWithSize:image_size];
		[fallback_image lockFocus];
		[[NSColor clearColor] setFill];
		NSRectFill(NSMakeRect(0.0, 0.0, image_size.width, image_size.height));

		NSBezierPath* circle_path = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0.0, 0.0, image_size.width, image_size.height)];
		[[NSColor colorWithWhite:0.78 alpha:1.0] setFill];
		[circle_path fill];
		[fallback_image unlockFocus];
	});

	return fallback_image;
}

- (void) setFetchingState:(BOOL) is_fetching
{
	self.isFetching = is_fetching;
	[self updateProgressIndicator];
}

- (void) updateProgressIndicator
{
	if (self.progressIndicator == nil) {
		return;
	}

	if (self.isFetching) {
		self.progressIndicator.hidden = NO;
		[self.progressIndicator startAnimation:nil];
	}
	else {
		[self.progressIndicator stopAnimation:nil];
		self.progressIndicator.hidden = YES;
	}
}

@end
