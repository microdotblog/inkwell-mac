//
//  MBFeedsController.m
//  Inkwell
//
//  Created by Codex on 3/10/26.
//

#import "MBFeedsController.h"
#import "MBAvatarLoader.h"
#import "MBClient.h"
#import "MBSubscription.h"

static NSUserInterfaceItemIdentifier const InkwellFeedsCellIdentifier = @"InkwellFeedsCell";
static CGFloat const InkwellFeedsAvatarSize = 16.0;
static CGFloat const InkwellFeedsRowHeight = 55.0;

@interface MBFeedsTableView : NSTableView

@property (copy, nullable) BOOL (^deleteSelectedFeedHandler)(void);

@end

@implementation MBFeedsTableView

- (void) keyDown:(NSEvent*) event
{
	NSString* characters = event.charactersIgnoringModifiers ?: @"";
	if (characters.length > 0) {
		unichar key_code = [characters characterAtIndex:0];
		NSEventModifierFlags modifier_flags = (event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask);
		BOOL has_command_modifier = ((modifier_flags & NSEventModifierFlagCommand) != 0);
		BOOL has_other_modifiers = ((modifier_flags & (NSEventModifierFlagOption | NSEventModifierFlagControl | NSEventModifierFlagShift)) != 0);
		BOOL is_delete_key = (key_code == NSDeleteCharacter || key_code == NSBackspaceCharacter || key_code == NSDeleteFunctionKey);
		if (has_command_modifier && !has_other_modifiers && is_delete_key && self.deleteSelectedFeedHandler != nil && self.deleteSelectedFeedHandler()) {
			return;
		}
	}

	[super keyDown:event];
}

@end

@interface MBFeedsCellView : NSTableCellView

@property (nonatomic, strong) NSImageView* avatarImageView;
@property (nonatomic, strong) NSStackView* textStackView;
@property (nonatomic, strong) NSTextField* titleTextField;
@property (nonatomic, strong) NSTextField* siteURLTextField;

- (void) configureWithSubscription:(MBSubscription*) subscription avatarImage:(NSImage*) avatar_image;

@end

@implementation MBFeedsCellView

- (instancetype) initWithFrame:(NSRect) frame_rect
{
	self = [super initWithFrame:frame_rect];
	if (self) {
		[self setupViews];
	}
	return self;
}

- (void) prepareForReuse
{
	[super prepareForReuse];
	self.avatarImageView.image = nil;
	self.titleTextField.stringValue = @"";
	self.siteURLTextField.stringValue = @"";
	[self applyTextColors];
}

- (void) configureWithSubscription:(MBSubscription*) subscription avatarImage:(NSImage*) avatar_image
{
	NSString* title_value = [self trimmedString:subscription.title];
	NSString* site_url_value = [self trimmedString:subscription.siteURL];
	NSString* feed_url_value = [self trimmedString:subscription.feedURL];
	if (title_value.length == 0) {
		title_value = (site_url_value.length > 0) ? site_url_value : feed_url_value;
	}
	if (title_value.length == 0) {
		title_value = @"Untitled Feed";
	}
	if (site_url_value.length == 0) {
		site_url_value = feed_url_value;
	}

	self.avatarImageView.image = avatar_image;
	self.titleTextField.stringValue = title_value;
	self.siteURLTextField.stringValue = site_url_value;
	[self applyTextColors];
}

- (void) setBackgroundStyle:(NSBackgroundStyle) background_style
{
	[super setBackgroundStyle:background_style];
	[self applyTextColors];
}

- (void) viewDidChangeEffectiveAppearance
{
	[super viewDidChangeEffectiveAppearance];
	[self applyTextColors];
}

- (void) setupViews
{
	NSImageView* avatar_image_view = [[NSImageView alloc] initWithFrame:NSZeroRect];
	avatar_image_view.translatesAutoresizingMaskIntoConstraints = NO;
	avatar_image_view.imageScaling = NSImageScaleProportionallyUpOrDown;
	avatar_image_view.wantsLayer = YES;
	avatar_image_view.layer.cornerRadius = (InkwellFeedsAvatarSize / 2.0);
	avatar_image_view.layer.masksToBounds = YES;
	[self addSubview:avatar_image_view];

	NSTextField* title_text_field = [NSTextField labelWithString:@""];
	title_text_field.translatesAutoresizingMaskIntoConstraints = NO;
	title_text_field.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
	title_text_field.lineBreakMode = NSLineBreakByTruncatingTail;
	title_text_field.maximumNumberOfLines = 1;
	title_text_field.usesSingleLineMode = YES;

	NSTextField* site_url_text_field = [NSTextField labelWithString:@""];
	site_url_text_field.translatesAutoresizingMaskIntoConstraints = NO;
	site_url_text_field.font = [NSFont systemFontOfSize:11.0];
	site_url_text_field.lineBreakMode = NSLineBreakByTruncatingTail;
	site_url_text_field.maximumNumberOfLines = 1;
	site_url_text_field.usesSingleLineMode = YES;
	[site_url_text_field setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
	[site_url_text_field setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

	NSStackView* text_stack_view = [[NSStackView alloc] initWithFrame:NSZeroRect];
	text_stack_view.translatesAutoresizingMaskIntoConstraints = NO;
	text_stack_view.orientation = NSUserInterfaceLayoutOrientationVertical;
	text_stack_view.alignment = NSLayoutAttributeLeading;
	text_stack_view.distribution = NSStackViewDistributionFill;
	text_stack_view.spacing = 2.0;
	[text_stack_view addArrangedSubview:title_text_field];
	[text_stack_view addArrangedSubview:site_url_text_field];
	[self addSubview:text_stack_view];

	[NSLayoutConstraint activateConstraints:@[
		[avatar_image_view.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10.0],
		[avatar_image_view.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
		[avatar_image_view.widthAnchor constraintEqualToConstant:InkwellFeedsAvatarSize],
		[avatar_image_view.heightAnchor constraintEqualToConstant:InkwellFeedsAvatarSize],

		[text_stack_view.leadingAnchor constraintEqualToAnchor:avatar_image_view.trailingAnchor constant:10.0],
		[text_stack_view.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10.0],
		[text_stack_view.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
	]];

	self.avatarImageView = avatar_image_view;
	self.textStackView = text_stack_view;
	self.titleTextField = title_text_field;
	self.siteURLTextField = site_url_text_field;
	self.textField = title_text_field;
	[self applyTextColors];
}

- (void) applyTextColors
{
	BOOL is_selected = (self.backgroundStyle == NSBackgroundStyleEmphasized);
	NSColor* primary_color = is_selected ? [NSColor alternateSelectedControlTextColor] : [NSColor labelColor];
	NSColor* secondary_color = is_selected ? [[NSColor alternateSelectedControlTextColor] colorWithAlphaComponent:0.78] : [NSColor secondaryLabelColor];
	self.titleTextField.textColor = primary_color;
	self.siteURLTextField.textColor = secondary_color;
}

- (NSString*) trimmedString:(NSString*) string_value
{
	return [string_value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

@end

@interface MBFeedsController () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) MBClient* client;
@property (nonatomic, copy) NSString* token;
@property (nonatomic, copy) NSArray* allSubscriptions;
@property (nonatomic, copy) NSArray* subscriptions;
@property (nonatomic, copy) NSString* searchQuery;
@property (nonatomic, strong) MBFeedsTableView* tableView;
@property (nonatomic, strong) NSTextField* emptyStateTextField;
@property (nonatomic, strong) MBAvatarLoader* avatarLoader;
@property (nonatomic, copy) NSDictionary* iconURLByHost;
@property (nonatomic, assign) BOOL hasLoadedFeedIcons;
@property (nonatomic, assign) BOOL isFetchingFeedIcons;
@property (nonatomic, assign) BOOL isFetching;

@end

@implementation MBFeedsController

- (instancetype) init
{
	return [self initWithClient:nil token:nil];
}

- (instancetype) initWithClient:(MBClient* _Nullable) client token:(NSString* _Nullable) token
{
	self = [super initWithNibName:nil bundle:nil];
	if (self) {
		self.client = client ?: [[MBClient alloc] init];
		self.token = [token stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		self.allSubscriptions = @[];
		self.subscriptions = @[];
		self.searchQuery = @"";
		self.avatarLoader = [MBAvatarLoader sharedLoader];
		self.iconURLByHost = @{};
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(avatarImageDidLoad:) name:MBAvatarLoaderDidLoadImageNotification object:self.avatarLoader];
	}
	return self;
}

- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self name:MBAvatarLoaderDidLoadImageNotification object:self.avatarLoader];
}

- (void) loadView
{
	NSView* container_view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 394.0, 300.0)];
	container_view.translatesAutoresizingMaskIntoConstraints = NO;

	MBFeedsTableView* table_view = [[MBFeedsTableView alloc] initWithFrame:NSZeroRect];
	table_view.translatesAutoresizingMaskIntoConstraints = NO;
	table_view.delegate = self;
	table_view.dataSource = self;
	table_view.headerView = nil;
	table_view.rowHeight = InkwellFeedsRowHeight;
	table_view.intercellSpacing = NSMakeSize(0.0, 0.0);
	table_view.usesAutomaticRowHeights = NO;
	table_view.allowsEmptySelection = YES;
	table_view.allowsMultipleSelection = NO;
	table_view.style = NSTableViewStylePlain;

	__weak typeof(self) weak_self = self;
	table_view.deleteSelectedFeedHandler = ^BOOL {
		MBFeedsController* strong_self = weak_self;
		if (strong_self == nil) {
			return NO;
		}

		return [strong_self deleteSelectedFeed];
	};

	NSTableColumn* table_column = [[NSTableColumn alloc] initWithIdentifier:@"FeedsColumn"];
	table_column.resizingMask = NSTableColumnAutoresizingMask;
	table_column.editable = NO;
	[table_view addTableColumn:table_column];

	NSScrollView* scroll_view = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	scroll_view.translatesAutoresizingMaskIntoConstraints = NO;
	scroll_view.drawsBackground = NO;
	scroll_view.hasVerticalScroller = YES;
	scroll_view.autohidesScrollers = YES;
	scroll_view.borderType = NSBezelBorder;
	scroll_view.documentView = table_view;

	NSTextField* empty_state_text_field = [NSTextField labelWithString:@""];
	empty_state_text_field.translatesAutoresizingMaskIntoConstraints = NO;
	empty_state_text_field.textColor = [NSColor secondaryLabelColor];
	empty_state_text_field.alignment = NSTextAlignmentCenter;
	empty_state_text_field.lineBreakMode = NSLineBreakByWordWrapping;
	empty_state_text_field.maximumNumberOfLines = 0;
	empty_state_text_field.hidden = YES;

	[container_view addSubview:scroll_view];
	[container_view addSubview:empty_state_text_field];

	[NSLayoutConstraint activateConstraints:@[
		[scroll_view.topAnchor constraintEqualToAnchor:container_view.topAnchor],
		[scroll_view.leadingAnchor constraintEqualToAnchor:container_view.leadingAnchor],
		[scroll_view.trailingAnchor constraintEqualToAnchor:container_view.trailingAnchor],
		[scroll_view.bottomAnchor constraintEqualToAnchor:container_view.bottomAnchor],

		[empty_state_text_field.centerXAnchor constraintEqualToAnchor:container_view.centerXAnchor],
		[empty_state_text_field.centerYAnchor constraintEqualToAnchor:container_view.centerYAnchor],
		[empty_state_text_field.leadingAnchor constraintGreaterThanOrEqualToAnchor:container_view.leadingAnchor constant:16.0],
		[empty_state_text_field.trailingAnchor constraintLessThanOrEqualToAnchor:container_view.trailingAnchor constant:-16.0]
	]];

	self.tableView = table_view;
	self.emptyStateTextField = empty_state_text_field;
	self.view = container_view;
	[self updateEmptyState];
}

- (void) reloadFeeds
{
	if (self.isFetching) {
		return;
	}

	if (self.token.length == 0) {
		self.allSubscriptions = @[];
		self.subscriptions = @[];
		[self.tableView reloadData];
		[self updateEmptyStateMessage:@"Sign in to load your feeds."];
		return;
	}

	self.isFetching = YES;
	[self updateEmptyState];

	__weak typeof(self) weak_self = self;
	[self.client fetchFeedSubscriptionsWithToken:self.token completion:^(NSArray* _Nullable subscriptions, NSError* _Nullable error) {
		MBFeedsController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		strong_self.isFetching = NO;
		if (error != nil) {
			if (strong_self.subscriptions.count == 0) {
				[strong_self updateEmptyStateMessage:@"Couldn't load feeds."];
			}
			else {
				[strong_self updateEmptyState];
			}
			return;
		}

		strong_self.allSubscriptions = subscriptions ?: @[];
		strong_self.iconURLByHost = @{};
		strong_self.hasLoadedFeedIcons = NO;
		strong_self.isFetchingFeedIcons = NO;
		[strong_self applySearchFilterPreservingSelection:NO preferredSubscriptionID:0];
		[strong_self fetchFeedIconsIfNeeded];
	}];
}

- (BOOL) focusFeedsTable
{
	if (self.tableView == nil) {
		return NO;
	}

	if (self.subscriptions.count > 0 && self.tableView.selectedRow < 0) {
		NSIndexSet* index_set = [NSIndexSet indexSetWithIndex:0];
		[self.tableView selectRowIndexes:index_set byExtendingSelection:NO];
		[self.tableView scrollRowToVisible:0];
	}

	NSWindow* window = self.view.window;
	if (window == nil) {
		return NO;
	}

	return [window makeFirstResponder:self.tableView];
}

- (void) updateSearchQuery:(NSString*) search_query
{
	NSString* normalized_query = [search_query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if ([self.searchQuery isEqualToString:normalized_query]) {
		return;
	}

	self.searchQuery = normalized_query;
	[self applySearchFilterPreservingSelection:NO preferredSubscriptionID:0];
}

- (NSInteger) numberOfRowsInTableView:(NSTableView*) tableView
{
	#pragma unused(tableView)
	return self.subscriptions.count;
}

- (NSView*) tableView:(NSTableView*) tableView viewForTableColumn:(NSTableColumn*) tableColumn row:(NSInteger) row
{
	#pragma unused(tableColumn)
	if (row < 0 || row >= self.subscriptions.count) {
		return nil;
	}

	MBFeedsCellView* cell_view = [tableView makeViewWithIdentifier:InkwellFeedsCellIdentifier owner:self];
	if (cell_view == nil) {
		cell_view = [[MBFeedsCellView alloc] initWithFrame:NSZeroRect];
		cell_view.identifier = InkwellFeedsCellIdentifier;
	}

	MBSubscription* subscription = self.subscriptions[(NSUInteger) row];
	NSImage* avatar_image = [self avatarImageForSubscription:subscription];
	[cell_view configureWithSubscription:subscription avatarImage:avatar_image];
	return cell_view;
}

- (NSImage*) avatarImageForSubscription:(MBSubscription*) subscription
{
	NSString* avatar_url = [self avatarURLStringForSubscription:subscription];
	if (avatar_url.length == 0) {
		return [self defaultAvatarImage];
	}

	NSImage* cached_image = [self.avatarLoader cachedImageForURLString:avatar_url];
	if (cached_image != nil) {
		return cached_image;
	}

	[self.avatarLoader loadImageForURLString:avatar_url];
	return [self defaultAvatarImage];
}

- (void) avatarImageDidLoad:(NSNotification*) notification
{
	NSString* url_string = [self normalizedURLString:notification.userInfo[MBAvatarLoaderURLStringUserInfoKey]];
	if (url_string.length == 0 || self.subscriptions.count == 0 || self.tableView == nil) {
		return;
	}

	NSMutableIndexSet* row_indexes = [NSMutableIndexSet indexSet];
	for (NSInteger i = 0; i < self.subscriptions.count; i++) {
		MBSubscription* subscription = self.subscriptions[(NSUInteger) i];
		NSString* avatar_url = [self avatarURLStringForSubscription:subscription];
		if ([avatar_url isEqualToString:url_string]) {
			[row_indexes addIndex:(NSUInteger) i];
		}
	}

	if (row_indexes.count == 0) {
		return;
	}

	NSIndexSet* column_indexes = [NSIndexSet indexSetWithIndex:0];
	[self.tableView reloadDataForRowIndexes:row_indexes columnIndexes:column_indexes];
}

- (BOOL) deleteSelectedFeed
{
	MBSubscription* subscription = [self selectedSubscription];
	if (![self canDeleteSubscription:subscription] || self.view.window == nil) {
		return NO;
	}

	NSAlert* alert = [[NSAlert alloc] init];
	alert.alertStyle = NSAlertStyleWarning;
	alert.messageText = @"Are you sure you want to unsubscribe from this feed?";
	[alert addButtonWithTitle:@"Unsubscribe"];
	[alert addButtonWithTitle:@"Cancel"];

	NSInteger selected_row = self.tableView.selectedRow;
	__weak typeof(self) weak_self = self;
	[alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse return_code) {
		if (return_code != NSAlertFirstButtonReturn) {
			return;
		}

		MBFeedsController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		strong_self.isFetching = YES;
		[strong_self updateEmptyState];

		[strong_self.client deleteFeedSubscription:subscription token:strong_self.token completion:^(NSError* _Nullable error) {
			MBFeedsController* inner_self = weak_self;
			if (inner_self == nil) {
				return;
			}

			inner_self.isFetching = NO;
			if (error != nil) {
				[inner_self updateEmptyState];
				[inner_self presentDeleteError:error];
				return;
			}

			[inner_self removeSubscriptionWithID:subscription.subscriptionID preferredRow:selected_row];
		}];
	}];
	return YES;
}

- (MBSubscription* _Nullable) selectedSubscription
{
	NSInteger selected_row = self.tableView.selectedRow;
	if (selected_row < 0 || selected_row >= self.subscriptions.count) {
		return nil;
	}

	return self.subscriptions[(NSUInteger) selected_row];
}

- (BOOL) canDeleteSubscription:(MBSubscription*) subscription
{
	return ([subscription isKindOfClass:[MBSubscription class]] && subscription.subscriptionID > 0 && self.token.length > 0 && !self.isFetching);
}

- (void) removeSubscriptionWithID:(NSInteger) subscription_id preferredRow:(NSInteger) preferred_row
{
	NSMutableArray* updated_subscriptions = [NSMutableArray arrayWithArray:self.allSubscriptions ?: @[]];
	NSInteger removed_row = -1;
	for (NSInteger i = 0; i < updated_subscriptions.count; i++) {
		id object = updated_subscriptions[(NSUInteger) i];
		if (![object isKindOfClass:[MBSubscription class]]) {
			continue;
		}

		MBSubscription* subscription = (MBSubscription*) object;
		if (subscription.subscriptionID == subscription_id) {
			removed_row = i;
			[updated_subscriptions removeObjectAtIndex:(NSUInteger) i];
			break;
		}
	}

	self.allSubscriptions = [updated_subscriptions copy];

	NSInteger selection_row = (removed_row >= 0) ? removed_row : preferred_row;
	NSInteger preferred_subscription_id = 0;
	if (selection_row >= 0 && selection_row < self.allSubscriptions.count) {
		MBSubscription* next_subscription = self.allSubscriptions[(NSUInteger) selection_row];
		preferred_subscription_id = next_subscription.subscriptionID;
	}
	else if (self.allSubscriptions.count > 0) {
		MBSubscription* last_subscription = [self.allSubscriptions lastObject];
		preferred_subscription_id = last_subscription.subscriptionID;
	}

	[self applySearchFilterPreservingSelection:YES preferredSubscriptionID:preferred_subscription_id];
}

- (void) presentDeleteError:(NSError*) error
{
	if (error == nil || self.view.window == nil) {
		return;
	}

	NSAlert* alert = [[NSAlert alloc] init];
	alert.alertStyle = NSAlertStyleWarning;
	alert.messageText = @"Delete Failed";
	alert.informativeText = error.localizedDescription ?: @"The feed could not be removed.";
	[alert beginSheetModalForWindow:self.view.window completionHandler:nil];
}

- (void) updateEmptyState
{
	if (self.isFetching && self.subscriptions.count == 0) {
		[self updateEmptyStateMessage:@"Loading feeds..."];
		return;
	}

	if (self.subscriptions.count == 0) {
		if (self.searchQuery.length > 0 && self.allSubscriptions.count > 0) {
			[self updateEmptyStateMessage:@"No matching feeds."];
			return;
		}

		[self updateEmptyStateMessage:@"No feeds."];
		return;
	}

	[self updateEmptyStateMessage:@""];
}

- (void) updateEmptyStateMessage:(NSString*) message
{
	self.emptyStateTextField.stringValue = message ?: @"";
	self.emptyStateTextField.hidden = (self.emptyStateTextField.stringValue.length == 0);
}

- (NSString*) normalizedURLString:(NSString*) url_string
{
	return [url_string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

- (void) fetchFeedIconsIfNeeded
{
	if (self.client == nil || self.token.length == 0) {
		return;
	}

	if (![self needsFeedIcons] || self.hasLoadedFeedIcons || self.isFetchingFeedIcons) {
		return;
	}

	self.isFetchingFeedIcons = YES;
	__weak typeof(self) weak_self = self;
	[self.client fetchFeedIconsWithToken:self.token completion:^(NSDictionary* _Nullable icons_by_host, NSError* _Nullable error) {
		MBFeedsController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		strong_self.isFetchingFeedIcons = NO;
		if (error != nil) {
			return;
		}

		strong_self.iconURLByHost = [strong_self normalizedIconURLByHostFromMap:icons_by_host ?: @{}];
		strong_self.hasLoadedFeedIcons = YES;
		[strong_self.tableView reloadData];
	}];
}

- (BOOL) needsFeedIcons
{
	for (MBSubscription* subscription in self.allSubscriptions) {
		if (![subscription isKindOfClass:[MBSubscription class]]) {
			continue;
		}

		if ([self normalizedURLString:subscription.avatarURL].length == 0) {
			return YES;
		}
	}

	return NO;
}

- (NSDictionary*) normalizedIconURLByHostFromMap:(NSDictionary*) icons_by_host
{
	if (icons_by_host.count == 0) {
		return @{};
	}

	NSMutableDictionary* normalized_icons_by_host = [NSMutableDictionary dictionary];
	for (NSString* host_value in icons_by_host) {
		NSString* normalized_host = [self normalizedHostString:host_value];
		if (normalized_host.length == 0) {
			continue;
		}

		NSString* url_value = [self normalizedURLString:icons_by_host[host_value]];
		if (url_value.length == 0) {
			continue;
		}

		normalized_icons_by_host[normalized_host] = url_value;
	}

	return [normalized_icons_by_host copy];
}

- (NSString*) avatarURLStringForSubscription:(MBSubscription*) subscription
{
	NSString* avatar_url = [self normalizedURLString:subscription.avatarURL];
	if (avatar_url.length > 0) {
		return avatar_url;
	}

	NSString* site_host = [self normalizedHostFromURLString:subscription.siteURL ?: @""];
	if (site_host.length == 0) {
		return @"";
	}

	return [self normalizedURLString:self.iconURLByHost[site_host]];
}

- (NSString*) normalizedHostFromURLString:(NSString*) url_string
{
	if (url_string.length == 0) {
		return @"";
	}

	NSURLComponents* components = [NSURLComponents componentsWithString:url_string];
	NSString* host_value = components.host ?: @"";
	if (host_value.length == 0) {
		NSString* possible_url_string = [NSString stringWithFormat:@"https://%@", url_string];
		NSURLComponents* host_only_components = [NSURLComponents componentsWithString:possible_url_string];
		host_value = host_only_components.host ?: @"";
	}

	return [self normalizedHostString:host_value];
}

- (NSString*) normalizedHostString:(NSString*) host_string
{
	if (host_string.length == 0) {
		return @"";
	}

	NSString* normalized_host = [[host_string lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if ([normalized_host hasPrefix:@"www."]) {
		normalized_host = [normalized_host substringFromIndex:4];
	}
	if ([normalized_host hasSuffix:@"."]) {
		normalized_host = [normalized_host substringToIndex:(normalized_host.length - 1)];
	}

	return normalized_host;
}

- (void) applySearchFilterPreservingSelection:(BOOL) preserve_selection preferredSubscriptionID:(NSInteger) preferred_subscription_id
{
	NSInteger selected_subscription_id = preferred_subscription_id;
	if (selected_subscription_id <= 0 && preserve_selection) {
		MBSubscription* selected_subscription = [self selectedSubscription];
		selected_subscription_id = selected_subscription.subscriptionID;
	}

	NSString* normalized_query = [[self.searchQuery lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (normalized_query.length == 0) {
		self.subscriptions = [self.allSubscriptions copy];
	}
	else {
		NSMutableArray* filtered_subscriptions = [NSMutableArray array];
		for (MBSubscription* subscription in self.allSubscriptions) {
			if (![subscription isKindOfClass:[MBSubscription class]]) {
				continue;
			}

			NSString* title_value = [[self normalizedURLString:subscription.title] lowercaseString];
			NSString* site_url_value = [[self normalizedURLString:subscription.siteURL] lowercaseString];
			NSString* feed_url_value = [[self normalizedURLString:subscription.feedURL] lowercaseString];
			BOOL matches_query = ([title_value rangeOfString:normalized_query].location != NSNotFound ||
				[site_url_value rangeOfString:normalized_query].location != NSNotFound ||
				[feed_url_value rangeOfString:normalized_query].location != NSNotFound);
			if (matches_query) {
				[filtered_subscriptions addObject:subscription];
			}
		}

		self.subscriptions = [filtered_subscriptions copy];
	}

	[self.tableView reloadData];
	[self restoreSelectionForSubscriptionID:selected_subscription_id];
	[self updateEmptyState];
}

- (void) restoreSelectionForSubscriptionID:(NSInteger) subscription_id
{
	if (subscription_id <= 0 || self.subscriptions.count == 0) {
		return;
	}

	for (NSInteger i = 0; i < self.subscriptions.count; i++) {
		MBSubscription* subscription = self.subscriptions[(NSUInteger) i];
		if (subscription.subscriptionID != subscription_id) {
			continue;
		}

		NSIndexSet* index_set = [NSIndexSet indexSetWithIndex:(NSUInteger) i];
		[self.tableView selectRowIndexes:index_set byExtendingSelection:NO];
		return;
	}
}

- (NSImage*) defaultAvatarImage
{
	static NSImage* fallback_image;
	static dispatch_once_t once_token;
	dispatch_once(&once_token, ^{
		NSSize image_size = NSMakeSize(InkwellFeedsAvatarSize, InkwellFeedsAvatarSize);
		fallback_image = [[NSImage alloc] initWithSize:image_size];
		[fallback_image lockFocus];
		[[NSColor colorWithWhite:0.82 alpha:1.0] setFill];
		NSBezierPath* rounded_path = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0.0, 0.0, image_size.width, image_size.height) xRadius:4.0 yRadius:4.0];
		[rounded_path fill];
		[fallback_image unlockFocus];
	});

	return fallback_image;
}

@end
