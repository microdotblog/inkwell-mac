//
//  MBHighlightsController.m
//  Inkwell
//
//  Created by Codex on 3/4/26.
//

#import "MBHighlightsController.h"
#import "MBAvatarLoader.h"
#import "MBClient.h"
#import "MBEntry.h"
#import "MBHighlight.h"
#import "MBHighlightCellView.h"
#import "NSStrings+Extras.h"

static NSUserInterfaceItemIdentifier const InkwellHighlightsCellIdentifier = @"InkwellHighlightsCell";
static NSUserInterfaceItemIdentifier const InkwellHighlightsRowIdentifier = @"InkwellHighlightsRow";
static CGFloat const InkwellHighlightsTopBarHeight = 44.0;
static CGFloat const InkwellHighlightsAvatarSize = 20.0;
static CGFloat const InkwellHighlightsRowSpacing = 5.0;
static CGFloat const InkwellHighlightsRowBackgroundHorizontalInset = 10.0;
static CGFloat const InkwellHighlightsRowBackgroundVerticalInset = 2.5;
static CGFloat const InkwellHighlightsRowCornerRadius = 10.0;
static NSString* const InkwellHighlightColorName = @"color_highlight";

@interface MBHighlightsTableView : NSTableView

@property (copy, nullable) BOOL (^deleteSelectedHighlightHandler)(void);
@property (copy, nullable) NSMenu* (^contextMenuHandler)(void);

@end

@implementation MBHighlightsTableView

- (void) keyDown:(NSEvent*) event
{
	NSString* characters = event.charactersIgnoringModifiers ?: @"";
	if (characters.length > 0) {
		unichar key_code = [characters characterAtIndex:0];
		NSEventModifierFlags modifier_flags = (event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask);
		BOOL has_command_modifier = ((modifier_flags & NSEventModifierFlagCommand) != 0);
		BOOL has_other_modifiers = ((modifier_flags & (NSEventModifierFlagOption | NSEventModifierFlagControl | NSEventModifierFlagShift)) != 0);
		BOOL is_delete_key = (key_code == NSDeleteCharacter || key_code == NSBackspaceCharacter || key_code == NSDeleteFunctionKey);
		if (has_command_modifier && !has_other_modifiers && is_delete_key && self.deleteSelectedHighlightHandler != nil && self.deleteSelectedHighlightHandler()) {
			return;
		}
	}

	[super keyDown:event];
}

- (NSMenu*) menuForEvent:(NSEvent*) event
{
	if (self.contextMenuHandler == nil) {
		return [super menuForEvent:event];
	}

	NSPoint point_in_window = event.locationInWindow;
	NSPoint point_in_table = [self convertPoint:point_in_window fromView:nil];
	NSInteger row = [self rowAtPoint:point_in_table];
	if (row < 0 || row >= self.numberOfRows) {
		return nil;
	}

	NSIndexSet* index_set = [NSIndexSet indexSetWithIndex:(NSUInteger) row];
	[self selectRowIndexes:index_set byExtendingSelection:NO];

	NSMenu* menu = self.contextMenuHandler();
	if (menu != nil) {
		return menu;
	}

	return [super menuForEvent:event];
}

@end

@interface MBHighlightsRowView : NSTableRowView
@end

@implementation MBHighlightsRowView

- (void) drawBackgroundInRect:(NSRect) dirty_rect
{
	[super drawBackgroundInRect:dirty_rect];
	if (self.isSelected) {
		return;
	}

	NSColor* background_color = [NSColor colorNamed:InkwellHighlightColorName];
	if (background_color == nil) {
		background_color = [NSColor colorWithCalibratedRed:1.0 green:0.95 blue:0.56 alpha:1.0];
	}

	NSRect fill_rect = NSInsetRect(self.bounds, InkwellHighlightsRowBackgroundHorizontalInset, InkwellHighlightsRowBackgroundVerticalInset);
	NSBezierPath* path = [NSBezierPath bezierPathWithRoundedRect:fill_rect xRadius:InkwellHighlightsRowCornerRadius yRadius:InkwellHighlightsRowCornerRadius];
	[background_color setFill];
	[path fill];
}

@end

@interface MBHighlightsController () <NSTableViewDataSource, NSTableViewDelegate, NSMenuItemValidation, NSSearchFieldDelegate>

@property (nonatomic, strong) MBClient* client;
@property (nonatomic, copy) NSString* token;
@property (nonatomic, assign, readwrite) NSInteger entryID;
@property (nonatomic, copy) NSArray* highlights;
@property (nonatomic, strong) NSTableView* tableView;
@property (nonatomic, strong) NSImageView* avatarImageView;
@property (nonatomic, copy) NSArray* allPostsAvatarImageViews;
@property (nonatomic, strong) NSTextField* titleTextField;
@property (nonatomic, strong) NSSearchField* searchField;
@property (nonatomic, strong) NSProgressIndicator* progressIndicator;
@property (nonatomic, strong) NSLayoutConstraint* progressIndicatorWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint* titleLeadingToSingleAvatarConstraint;
@property (nonatomic, strong) NSLayoutConstraint* titleLeadingToNoAvatarConstraint;
@property (nonatomic, copy) NSArray* titleLeadingToAllPostsAvatarConstraints;
@property (nonatomic, copy) NSString* headerTitle;
@property (nonatomic, strong) NSImage* headerAvatarImage;
@property (nonatomic, copy) NSString* headerFeedHost;
@property (nonatomic, copy) NSString* entryTitleForPost;
@property (nonatomic, copy) NSString* entryURLString;
@property (nonatomic, copy) NSDictionary<NSString*, NSString*>* iconURLByHost;
@property (nonatomic, copy) NSArray* allPostsAvatarHosts;
@property (nonatomic, strong) MBAvatarLoader* avatarLoader;
@property (nonatomic, assign) BOOL hasLoadedFeedIcons;
@property (nonatomic, assign) BOOL isFetchingFeedIcons;
@property (nonatomic, assign) BOOL didSetupContent;
@property (nonatomic, assign) BOOL isFetching;

@end

@implementation MBHighlightsController

- (NSColor*) highlightsHeaderBackgroundColor
{
	return NSColor.secondarySystemFillColor;
}

- (NSImage*) flattenedHeaderAvatarImage:(NSImage*) image fadeAmount:(CGFloat) fade_amount
{
	if (image == nil) {
		return [self defaultAvatarImage];
	}

	NSSize image_size = NSMakeSize(InkwellHighlightsAvatarSize, InkwellHighlightsAvatarSize);
	NSImage* flattened_image = [[NSImage alloc] initWithSize:image_size];
	[flattened_image lockFocus];
	[[self highlightsHeaderBackgroundColor] setFill];
	NSRectFill(NSMakeRect(0.0, 0.0, image_size.width, image_size.height));
	[image drawInRect:NSMakeRect(0.0, 0.0, image_size.width, image_size.height) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
	CGFloat clamped_fade_amount = MAX(0.0, MIN(1.0, fade_amount));
	if (clamped_fade_amount > 0.0) {
		[[[self highlightsHeaderBackgroundColor] colorWithAlphaComponent:clamped_fade_amount] setFill];
		NSRectFillUsingOperation(NSMakeRect(0.0, 0.0, image_size.width, image_size.height), NSCompositingOperationSourceOver);
	}
	[flattened_image unlockFocus];
	return flattened_image;
}

- (instancetype) initWithClient:(MBClient*) client token:(NSString*) token
{
	self = [super initWithWindow:nil];
	if (self) {
		self.client = client;
		self.token = token ?: @"";
		self.highlights = @[];
		self.avatarLoader = [MBAvatarLoader sharedLoader];
		self.headerTitle = @"Highlights";
		self.headerAvatarImage = [self defaultAvatarImage];
		self.headerFeedHost = @"";
		self.entryTitleForPost = @"";
		self.entryURLString = @"";
		self.iconURLByHost = @{};
		self.allPostsAvatarImageViews = @[];
		self.allPostsAvatarHosts = @[];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(avatarImageDidLoad:) name:MBAvatarLoaderDidLoadImageNotification object:self.avatarLoader];
	}
	return self;
}

- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self name:MBAvatarLoaderDidLoadImageNotification object:self.avatarLoader];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSControlTextDidChangeNotification object:self.searchField];
}

- (void) showWindow:(id)sender
{
	[self setupWindowIfNeeded];
	[self setupContentIfNeeded];
	if ([self hasActiveSearchQuery]) {
		self.searchField.stringValue = @"";
		[self updateHighlightSearchWithText:@""];
	}
	[super showWindow:sender];
	[self.window makeKeyAndOrderFront:sender];
	[self focusHighlightsTable];
}

- (void) showHighlightsForEntry:(MBEntry*) entry
{
	if (entry == nil || entry.entryID <= 0) {
		[self updateForSelectedEntry:nil];
		[self showWindow:nil];
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
	self.entryTitleForPost = @"";
	self.entryURLString = @"";
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
		self.entryTitleForPost = @"";
		self.entryURLString = @"";
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
	NSString* search_query = [self activeSearchQuery];
	if (search_query.length > 0) {
		if (self.client == nil) {
			[self setFetchingState:NO];
			self.highlights = @[];
			[self.tableView reloadData];
			[self refreshAllPostsAvatarHosts];
			[self updateAllPostsAvatarImages];
			return;
		}

		NSArray* all_highlights = [self.client cachedAllHighlights];
		self.highlights = [self filteredHighlights:all_highlights matchingQuery:search_query];
		[self.tableView reloadData];
		[self refreshAllPostsAvatarHosts];
		[self updateAllPostsAvatarImages];
		return;
	}

	if (self.entryID <= 0 || self.client == nil) {
		[self setFetchingState:NO];
		self.highlights = @[];
		[self.tableView reloadData];
		[self refreshAllPostsAvatarHosts];
		[self updateAllPostsAvatarImages];
		return;
	}

	[self setFetchingState:NO];
	NSArray* cached_highlights = [self.client cachedHighlightsForEntryID:self.entryID];
	if (![cached_highlights isKindOfClass:[NSArray class]]) {
		self.highlights = @[];
	}
	else {
		self.highlights = [cached_highlights copy];
	}
	[self.tableView reloadData];
	[self refreshAllPostsAvatarHosts];
	[self updateAllPostsAvatarImages];
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
	top_container_view.layer.backgroundColor = [self highlightsHeaderBackgroundColor].CGColor;

	NSImageView* avatar_image_view = [[NSImageView alloc] initWithFrame:NSZeroRect];
	avatar_image_view.translatesAutoresizingMaskIntoConstraints = NO;
	avatar_image_view.imageScaling = NSImageScaleAxesIndependently;
	avatar_image_view.wantsLayer = YES;
	avatar_image_view.layer.cornerRadius = (InkwellHighlightsAvatarSize / 2.0);
	avatar_image_view.layer.backgroundColor = [self highlightsHeaderBackgroundColor].CGColor;
	avatar_image_view.layer.masksToBounds = YES;

	NSMutableArray* all_posts_avatar_image_views = [NSMutableArray array];
	for (NSInteger i = 0; i < 3; i++) {
		NSImageView* stacked_avatar_image_view = [[NSImageView alloc] initWithFrame:NSZeroRect];
		stacked_avatar_image_view.translatesAutoresizingMaskIntoConstraints = NO;
		stacked_avatar_image_view.imageScaling = NSImageScaleAxesIndependently;
		stacked_avatar_image_view.wantsLayer = YES;
		stacked_avatar_image_view.layer.cornerRadius = (InkwellHighlightsAvatarSize / 2.0);
		stacked_avatar_image_view.layer.backgroundColor = [self highlightsHeaderBackgroundColor].CGColor;
		stacked_avatar_image_view.layer.masksToBounds = YES;
		stacked_avatar_image_view.hidden = YES;
		[all_posts_avatar_image_views addObject:stacked_avatar_image_view];
	}

	NSTextField* title_text_field = [NSTextField labelWithString:@""];
	title_text_field.translatesAutoresizingMaskIntoConstraints = NO;
	title_text_field.lineBreakMode = NSLineBreakByTruncatingTail;
	title_text_field.maximumNumberOfLines = 1;
	title_text_field.usesSingleLineMode = YES;
	title_text_field.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
	[title_text_field setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
	[title_text_field setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

	NSSearchField* search_field = [[NSSearchField alloc] initWithFrame:NSZeroRect];
	search_field.translatesAutoresizingMaskIntoConstraints = NO;
	search_field.controlSize = NSControlSizeSmall;
	search_field.placeholderString = @"Search all highlights";
	search_field.delegate = self;
	[search_field setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
	[search_field setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

	NSProgressIndicator* progress_indicator = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
	progress_indicator.translatesAutoresizingMaskIntoConstraints = NO;
	progress_indicator.style = NSProgressIndicatorStyleSpinning;
	progress_indicator.controlSize = NSControlSizeSmall;
	progress_indicator.indeterminate = YES;
	progress_indicator.displayedWhenStopped = NO;
	progress_indicator.hidden = YES;
	[progress_indicator setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

	NSLayoutConstraint* progress_indicator_width_constraint = [progress_indicator.widthAnchor constraintEqualToConstant:0.0];

	[top_container_view addSubview:avatar_image_view];
	for (NSInteger i = (all_posts_avatar_image_views.count - 1); i >= 0; i--) {
		NSImageView* stacked_avatar_image_view = all_posts_avatar_image_views[(NSUInteger) i];
		[top_container_view addSubview:stacked_avatar_image_view];
	}
	[top_container_view addSubview:title_text_field];
	[top_container_view addSubview:search_field];
	[top_container_view addSubview:progress_indicator];

	NSImageView* first_all_posts_avatar_image_view = all_posts_avatar_image_views.firstObject;
	NSImageView* second_all_posts_avatar_image_view = (all_posts_avatar_image_views.count > 1) ? all_posts_avatar_image_views[1] : nil;
	NSImageView* third_all_posts_avatar_image_view = (all_posts_avatar_image_views.count > 2) ? all_posts_avatar_image_views[2] : nil;
	NSLayoutConstraint* title_leading_to_single_avatar_constraint = [title_text_field.leadingAnchor constraintEqualToAnchor:avatar_image_view.trailingAnchor constant:8.0];
	NSLayoutConstraint* title_leading_to_no_avatar_constraint = [title_text_field.leadingAnchor constraintEqualToAnchor:top_container_view.leadingAnchor constant:10.0];
	NSLayoutConstraint* title_leading_to_first_all_posts_avatar_constraint = [title_text_field.leadingAnchor constraintEqualToAnchor:first_all_posts_avatar_image_view.trailingAnchor constant:8.0];
	NSLayoutConstraint* title_leading_to_second_all_posts_avatar_constraint = [title_text_field.leadingAnchor constraintEqualToAnchor:second_all_posts_avatar_image_view.trailingAnchor constant:8.0];
	NSLayoutConstraint* title_leading_to_third_all_posts_avatar_constraint = [title_text_field.leadingAnchor constraintEqualToAnchor:third_all_posts_avatar_image_view.trailingAnchor constant:8.0];

	MBHighlightsTableView* table_view = [[MBHighlightsTableView alloc] initWithFrame:NSZeroRect];
	table_view.translatesAutoresizingMaskIntoConstraints = NO;
	table_view.delegate = self;
	table_view.dataSource = self;
	table_view.headerView = nil;
	table_view.rowHeight = 62.0;
	table_view.intercellSpacing = NSMakeSize(0.0, InkwellHighlightsRowSpacing);
	table_view.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
	table_view.backgroundColor = NSColor.clearColor;
	table_view.usesAutomaticRowHeights = NO;
	table_view.allowsMultipleSelection = NO;
	table_view.allowsEmptySelection = YES;

	__weak typeof(self) weak_self = self;
	table_view.deleteSelectedHighlightHandler = ^BOOL {
		MBHighlightsController* strong_self = weak_self;
		if (strong_self == nil) {
			return NO;
		}
		return [strong_self handleDeleteShortcut];
	};
	table_view.contextMenuHandler = ^NSMenu* {
		MBHighlightsController* strong_self = weak_self;
		if (strong_self == nil) {
			return nil;
		}
		return [strong_self highlightContextMenu];
	};

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
		[first_all_posts_avatar_image_view.leadingAnchor constraintEqualToAnchor:top_container_view.leadingAnchor constant:10.0],
		[first_all_posts_avatar_image_view.centerYAnchor constraintEqualToAnchor:top_container_view.centerYAnchor],
		[first_all_posts_avatar_image_view.widthAnchor constraintEqualToConstant:InkwellHighlightsAvatarSize],
		[first_all_posts_avatar_image_view.heightAnchor constraintEqualToConstant:InkwellHighlightsAvatarSize],
		[second_all_posts_avatar_image_view.leadingAnchor constraintEqualToAnchor:first_all_posts_avatar_image_view.leadingAnchor constant:8.0],
		[second_all_posts_avatar_image_view.centerYAnchor constraintEqualToAnchor:first_all_posts_avatar_image_view.centerYAnchor],
		[second_all_posts_avatar_image_view.widthAnchor constraintEqualToAnchor:first_all_posts_avatar_image_view.widthAnchor],
		[second_all_posts_avatar_image_view.heightAnchor constraintEqualToAnchor:first_all_posts_avatar_image_view.heightAnchor],
		[third_all_posts_avatar_image_view.leadingAnchor constraintEqualToAnchor:second_all_posts_avatar_image_view.leadingAnchor constant:8.0],
		[third_all_posts_avatar_image_view.centerYAnchor constraintEqualToAnchor:first_all_posts_avatar_image_view.centerYAnchor],
		[third_all_posts_avatar_image_view.widthAnchor constraintEqualToAnchor:first_all_posts_avatar_image_view.widthAnchor],
		[third_all_posts_avatar_image_view.heightAnchor constraintEqualToAnchor:first_all_posts_avatar_image_view.heightAnchor],
		[search_field.centerYAnchor constraintEqualToAnchor:top_container_view.centerYAnchor],
		[search_field.widthAnchor constraintEqualToConstant:170.0],
		[search_field.trailingAnchor constraintEqualToAnchor:progress_indicator.leadingAnchor],
		progress_indicator_width_constraint,
		[progress_indicator.trailingAnchor constraintEqualToAnchor:top_container_view.trailingAnchor constant:-10.0],
		[progress_indicator.centerYAnchor constraintEqualToAnchor:top_container_view.centerYAnchor],
		[title_text_field.trailingAnchor constraintLessThanOrEqualToAnchor:search_field.leadingAnchor constant:-8.0],
		[title_text_field.centerYAnchor constraintEqualToAnchor:top_container_view.centerYAnchor],
		[scroll_view.topAnchor constraintEqualToAnchor:top_container_view.bottomAnchor],
		[scroll_view.bottomAnchor constraintEqualToAnchor:content_view.bottomAnchor],
		[scroll_view.leadingAnchor constraintEqualToAnchor:content_view.leadingAnchor],
		[scroll_view.trailingAnchor constraintEqualToAnchor:content_view.trailingAnchor]
	]];

	self.tableView = table_view;
	self.avatarImageView = avatar_image_view;
	self.allPostsAvatarImageViews = [all_posts_avatar_image_views copy];
	self.titleTextField = title_text_field;
	self.searchField = search_field;
	self.progressIndicator = progress_indicator;
	self.progressIndicatorWidthConstraint = progress_indicator_width_constraint;
	self.titleLeadingToSingleAvatarConstraint = title_leading_to_single_avatar_constraint;
	self.titleLeadingToNoAvatarConstraint = title_leading_to_no_avatar_constraint;
	self.titleLeadingToAllPostsAvatarConstraints = @[
		title_leading_to_first_all_posts_avatar_constraint,
		title_leading_to_second_all_posts_avatar_constraint,
		title_leading_to_third_all_posts_avatar_constraint
	];
	self.didSetupContent = YES;
	self.titleLeadingToSingleAvatarConstraint.active = YES;
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(searchFieldTextDidChange:) name:NSControlTextDidChangeNotification object:search_field];
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

- (BOOL) focusHighlightsTable
{
	if (self.tableView == nil || self.window == nil) {
		return NO;
	}

	if (self.highlights.count > 0 && self.tableView.selectedRow < 0) {
		NSIndexSet* index_set = [NSIndexSet indexSetWithIndex:0];
		[self.tableView selectRowIndexes:index_set byExtendingSelection:NO];
		[self.tableView scrollRowToVisible:0];
	}

	return [self.window makeFirstResponder:self.tableView];
}

- (NSTableRowView*) tableView:(NSTableView*) tableView rowViewForRow:(NSInteger) row
{
	#pragma unused(row)
	MBHighlightsRowView* row_view = [tableView makeViewWithIdentifier:InkwellHighlightsRowIdentifier owner:self];
	if (row_view == nil) {
		row_view = [[MBHighlightsRowView alloc] initWithFrame:NSZeroRect];
		row_view.identifier = InkwellHighlightsRowIdentifier;
		row_view.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
	}
	return row_view;
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
	self.entryTitleForPost = title_string;
	self.entryURLString = [entry.url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	[self applyHeaderIfNeeded];
	[self fetchFeedIconsIfNeeded];
}

- (void) applyHeaderIfNeeded
{
	BOOL shows_all_posts_header = [self hasActiveSearchQuery];
	BOOL shows_entry_header = (self.entryID > 0 && !shows_all_posts_header);

	if (shows_all_posts_header) {
		[self fetchFeedIconsIfNeeded];
		[self refreshAllPostsAvatarHosts];
	}
	else {
		self.allPostsAvatarHosts = @[];
	}

	if (self.titleTextField != nil) {
		self.titleTextField.hidden = (!shows_entry_header && !shows_all_posts_header);
		if (shows_all_posts_header) {
			self.titleTextField.stringValue = @"All posts";
		}
		else if (shows_entry_header) {
			self.titleTextField.stringValue = self.headerTitle ?: @"Highlights";
		}
		else {
			self.titleTextField.stringValue = @"";
		}
	}

	if (self.avatarImageView != nil) {
		self.avatarImageView.hidden = !shows_entry_header;
		self.avatarImageView.image = shows_entry_header ? (self.headerAvatarImage ?: [self defaultAvatarImage]) : nil;
	}

	[self updateAllPostsAvatarImages];
	[self updateAllPostsTitleLeadingConstraint];
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
		[self refreshAllPostsAvatarHosts];
		[self updateHeaderAvatarImage];
	}];
}

- (void) updateHeaderAvatarImage
{
	self.headerAvatarImage = [self avatarImageForHost:self.headerFeedHost];
	[self applyHeaderIfNeeded];
}

- (void) avatarImageDidLoad:(NSNotification*) notification
{
	NSString* url_string = notification.userInfo[MBAvatarLoaderURLStringUserInfoKey];
	if (![url_string isKindOfClass:[NSString class]] || url_string.length == 0) {
		return;
	}

	NSString* header_url_string = [self avatarURLStringForHost:self.headerFeedHost];
	if ([header_url_string isEqualToString:url_string]) {
		[self updateHeaderAvatarImage];
		return;
	}

	for (NSString* host_value in self.allPostsAvatarHosts) {
		NSString* avatar_url_string = [self avatarURLStringForHost:host_value];
		if ([avatar_url_string isEqualToString:url_string]) {
			[self updateAllPostsAvatarImages];
			return;
		}
	}
}

- (void) searchFieldTextDidChange:(NSNotification*) notification
{
	NSSearchField* search_field = notification.object;
	if (![search_field isKindOfClass:[NSSearchField class]]) {
		return;
	}

	[self updateHighlightSearchWithText:(search_field.stringValue ?: @"")];
}

- (BOOL) control:(NSControl*) control textView:(NSTextView*) text_view doCommandBySelector:(SEL) command_selector
{
	#pragma unused(text_view)

	if (control != self.searchField) {
		return NO;
	}

	if (command_selector == @selector(insertNewline:) || command_selector == @selector(insertLineBreak:) || command_selector == @selector(insertNewlineIgnoringFieldEditor:)) {
		return [self focusHighlightsTable];
	}

	return NO;
}

- (void) updateHighlightSearchWithText:(NSString*) search_text
{
	#pragma unused(search_text)
	[self applyHeaderIfNeeded];
	[self reloadHighlights];
}

- (IBAction) performFindPanelAction:(id) sender
{
	if (![sender respondsToSelector:@selector(tag)]) {
		return;
	}

	NSInteger action_tag = [(id) sender tag];
	if (action_tag != NSFindPanelActionShowFindPanel) {
		return;
	}

	if (self.searchField == nil) {
		return;
	}

	[self.searchField selectText:nil];
}

- (NSString*) activeSearchQuery
{
	NSString* query_string = [self.searchField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	return query_string;
}

- (BOOL) hasActiveSearchQuery
{
	return ([self activeSearchQuery].length > 0);
}

- (NSArray*) filteredHighlights:(NSArray*) highlights matchingQuery:(NSString*) query_string
{
	NSString* trimmed_query = [query_string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (trimmed_query.length == 0 || ![highlights isKindOfClass:[NSArray class]]) {
		return @[];
	}

	NSMutableArray* matching_highlights = [NSMutableArray array];
	NSStringCompareOptions compare_options = (NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch);
	for (id object in highlights) {
		if (![object isKindOfClass:[MBHighlight class]]) {
			continue;
		}

		MBHighlight* highlight = (MBHighlight*) object;
		NSString* selection_text = [highlight.selectionText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		NSString* post_title = [highlight.postTitle stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		NSString* post_url = [highlight.postURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		BOOL matches_selection_text = (selection_text.length > 0 && [selection_text rangeOfString:trimmed_query options:compare_options].location != NSNotFound);
		BOOL matches_post_title = (post_title.length > 0 && [post_title rangeOfString:trimmed_query options:compare_options].location != NSNotFound);
		BOOL matches_post_url = (post_url.length > 0 && [post_url rangeOfString:trimmed_query options:compare_options].location != NSNotFound);
		if (!matches_selection_text && !matches_post_title && !matches_post_url) {
			continue;
		}

		[matching_highlights addObject:highlight];
	}

	return [matching_highlights copy];
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

- (void) refreshAllPostsAvatarHosts
{
	if (![self hasActiveSearchQuery]) {
		self.allPostsAvatarHosts = @[];
		return;
	}

	NSArray* matching_hosts = [self randomHostsForMatchingHighlights];
	if (matching_hosts.count > 0) {
		self.allPostsAvatarHosts = matching_hosts;
	}
	else {
		self.allPostsAvatarHosts = @[];
	}
}

- (NSArray*) randomHostsForAllPostsAvatars
{
	NSArray* available_hosts = self.iconURLByHost.allKeys ?: @[];
	if (available_hosts.count == 0) {
		return @[];
	}

	NSMutableArray* shuffled_hosts = [available_hosts mutableCopy];
	for (NSInteger i = (shuffled_hosts.count - 1); i > 0; i--) {
		u_int32_t random_index = arc4random_uniform((u_int32_t) (i + 1));
		[shuffled_hosts exchangeObjectAtIndex:i withObjectAtIndex:(NSInteger) random_index];
	}

	NSUInteger selected_count = MIN((NSUInteger) 3, shuffled_hosts.count);
	return [shuffled_hosts subarrayWithRange:NSMakeRange(0, selected_count)];
}

- (NSArray*) randomHostsForMatchingHighlights
{
	if (self.highlights.count == 0) {
		return @[];
	}

	NSMutableOrderedSet* unique_hosts = [[NSMutableOrderedSet alloc] init];
	NSMutableArray* highlight_hosts = [NSMutableArray array];
	for (id object in self.highlights) {
		if (![object isKindOfClass:[MBHighlight class]]) {
			continue;
		}

		MBHighlight* highlight = (MBHighlight*) object;
		NSString* host_value = [self normalizedHostFromURLString:highlight.postURL ?: @""];
		if (host_value.length == 0) {
			continue;
		}

		[unique_hosts addObject:host_value];
		[highlight_hosts addObject:host_value];
	}

	if (highlight_hosts.count == 0) {
		return @[];
	}

	NSMutableArray* shuffled_hosts = [[unique_hosts array] mutableCopy];
	for (NSInteger i = (shuffled_hosts.count - 1); i > 0; i--) {
		u_int32_t random_index = arc4random_uniform((u_int32_t) (i + 1));
		[shuffled_hosts exchangeObjectAtIndex:i withObjectAtIndex:(NSInteger) random_index];
	}

	NSMutableArray* selected_hosts = [NSMutableArray array];
	NSUInteger preferred_count = MIN((NSUInteger) 3, shuffled_hosts.count);
	for (NSUInteger i = 0; i < preferred_count; i++) {
		[selected_hosts addObject:shuffled_hosts[i]];
	}
	return [selected_hosts copy];
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

- (void) updateAllPostsAvatarImages
{
	BOOL shows_all_posts_header = [self hasActiveSearchQuery];
	for (NSInteger i = 0; i < self.allPostsAvatarImageViews.count; i++) {
		NSImageView* image_view = self.allPostsAvatarImageViews[(NSUInteger) i];
		BOOL should_show_fallback_avatar = (shows_all_posts_header && self.allPostsAvatarHosts.count == 0 && i == 0);
		BOOL should_show_image_view = (shows_all_posts_header && i < self.allPostsAvatarHosts.count);
		BOOL should_show_any_avatar = (should_show_image_view || should_show_fallback_avatar);
		image_view.hidden = !should_show_image_view;
		image_view.hidden = !should_show_any_avatar;
		if (!should_show_any_avatar) {
			image_view.image = nil;
			continue;
		}

		if (should_show_fallback_avatar) {
			image_view.image = [self defaultAvatarImage];
			continue;
		}

		NSString* host_value = self.allPostsAvatarHosts[(NSUInteger) i];
		CGFloat fade_amount = ((CGFloat) i) * 0.1;
		if (host_value.length > 0) {
			image_view.image = [self avatarImageForHost:host_value fadeAmount:fade_amount];
		}
		else {
			image_view.image = [self flattenedHeaderAvatarImage:[self defaultAvatarImage] fadeAmount:fade_amount];
		}
	}
}

- (void) updateAllPostsTitleLeadingConstraint
{
	self.titleLeadingToSingleAvatarConstraint.active = NO;
	self.titleLeadingToNoAvatarConstraint.active = NO;
	for (NSLayoutConstraint* constraint in self.titleLeadingToAllPostsAvatarConstraints) {
		constraint.active = NO;
	}

	if (![self hasActiveSearchQuery]) {
		self.titleLeadingToSingleAvatarConstraint.active = YES;
		return;
	}

	if (self.allPostsAvatarHosts.count == 0) {
		NSLayoutConstraint* active_constraint = self.titleLeadingToAllPostsAvatarConstraints.firstObject;
		active_constraint.active = YES;
		return;
	}

	NSUInteger last_avatar_index = MIN((NSUInteger) (self.allPostsAvatarHosts.count - 1), (NSUInteger) (self.titleLeadingToAllPostsAvatarConstraints.count - 1));
	NSLayoutConstraint* active_constraint = self.titleLeadingToAllPostsAvatarConstraints[last_avatar_index];
	active_constraint.active = YES;
}

- (BOOL) handleDeleteShortcut
{
	if (![self canDeleteSelectedHighlight]) {
		return NO;
	}

	[self promptToDeleteSelectedHighlight:nil];
	return YES;
}

- (NSMenu*) highlightContextMenu
{
	NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Highlights"];

	NSMenuItem* new_post_item = [[NSMenuItem alloc] initWithTitle:@"New Post..." action:@selector(newPostFromSelectedHighlight:) keyEquivalent:@""];
	new_post_item.target = self;
	[menu addItem:new_post_item];

	[menu addItem:[NSMenuItem separatorItem]];

	NSMenuItem* delete_item = [[NSMenuItem alloc] initWithTitle:@"Delete" action:@selector(promptToDeleteSelectedHighlight:) keyEquivalent:@""];
	delete_item.target = self;
	[menu addItem:delete_item];

	[menu addItem:[NSMenuItem separatorItem]];

	NSMenuItem* open_item = [[NSMenuItem alloc] initWithTitle:[NSString mb_openInBrowserString] action:@selector(openSelectedHighlightInBrowser:) keyEquivalent:@""];
	open_item.target = self;
	[menu addItem:open_item];

	NSMenuItem* copy_link_item = [[NSMenuItem alloc] initWithTitle:@"Copy Link" action:@selector(copySelectedHighlightLink:) keyEquivalent:@""];
	copy_link_item.target = self;
	[menu addItem:copy_link_item];

	NSMenuItem* copy_item = [[NSMenuItem alloc] initWithTitle:@"Copy Text" action:@selector(copySelectedHighlight:) keyEquivalent:@""];
	copy_item.target = self;
	[menu addItem:copy_item];

	return menu;
}

- (MBHighlight* _Nullable) selectedHighlight
{
	NSInteger selected_row = self.tableView.selectedRow;
	if (selected_row < 0 || selected_row >= self.highlights.count) {
		return nil;
	}

	id object = self.highlights[selected_row];
	if (![object isKindOfClass:[MBHighlight class]]) {
		return nil;
	}

	return (MBHighlight*) object;
}

- (BOOL) canDeleteSelectedHighlight
{
	return [self canDeleteHighlight:[self selectedHighlight]];
}

- (BOOL) canDeleteHighlight:(MBHighlight*) highlight
{
	if (self.isFetching || self.client == nil || self.token.length == 0) {
		return NO;
	}
	if (![highlight isKindOfClass:[MBHighlight class]] || highlight.entryID <= 0) {
		return NO;
	}

	NSString* highlight_id = [highlight.highlightID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	return (highlight_id.length > 0);
}

- (BOOL) canCopySelectedHighlight
{
	MBHighlight* highlight = [self selectedHighlight];
	if (![highlight isKindOfClass:[MBHighlight class]]) {
		return NO;
	}

	NSString* selection_text = highlight.selectionText ?: @"";
	return (selection_text.length > 0);
}

- (BOOL) canCopySelectedHighlightLink
{
	MBHighlight* highlight = [self selectedHighlight];
	if (![highlight isKindOfClass:[MBHighlight class]]) {
		return NO;
	}

	NSString* url_string = [self URLStringForHighlight:highlight];
	return (url_string.length > 0);
}

- (BOOL) canOpenSelectedHighlightInBrowser
{
	return [self canCopySelectedHighlightLink];
}

- (BOOL) canCreatePostFromSelectedHighlight
{
	MBHighlight* highlight = [self selectedHighlight];
	if (![highlight isKindOfClass:[MBHighlight class]]) {
		return NO;
	}

	NSString* title_string = [self titleForHighlight:highlight];
	NSString* url_string = [self URLStringForHighlight:highlight];
	return (title_string.length > 0 && url_string.length > 0 && [self canCopySelectedHighlight]);
}

- (IBAction) newPostFromSelectedHighlight:(id) sender
{
	#pragma unused(sender)
	MBHighlight* highlight = [self selectedHighlight];
	if (![highlight isKindOfClass:[MBHighlight class]]) {
		return;
	}

	NSString* markdown_text = [self markdownTextForNewPostFromHighlight:highlight];
	if (markdown_text.length == 0) {
		return;
	}

	NSMutableCharacterSet* allowed_character_set = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
	[allowed_character_set removeCharactersInString:@":#[]@!$&'()*+,;=/?"];
	NSString* encoded_text = [markdown_text stringByAddingPercentEncodingWithAllowedCharacters:allowed_character_set] ?: @"";
	if (encoded_text.length == 0) {
		return;
	}

	BOOL has_microblog_app = ([[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:@"blog.micro.mac"] != nil);
	NSString* open_url_string = nil;
	if (has_microblog_app) {
		open_url_string = [NSString stringWithFormat:@"microblog://post?text=%@", encoded_text];
	}
	else {
		open_url_string = [NSString stringWithFormat:@"https://micro.blog/post?text=%@", encoded_text];
	}

	NSURL* open_url = [NSURL URLWithString:open_url_string];
	if (open_url == nil) {
		return;
	}

	[[NSWorkspace sharedWorkspace] openURL:open_url];
}

- (IBAction) promptToDeleteSelectedHighlight:(id) sender
{
	#pragma unused(sender)
	MBHighlight* highlight = [self selectedHighlight];
	if (![self canDeleteHighlight:highlight] || self.window == nil) {
		return;
	}

	NSAlert* alert = [[NSAlert alloc] init];
	alert.alertStyle = NSAlertStyleWarning;
	alert.messageText = @"Delete Highlight?";
	alert.informativeText = @"This will delete the selected highlight from your account.";
	[alert addButtonWithTitle:@"Delete"];
	[alert addButtonWithTitle:@"Cancel"];

	__weak typeof(self) weak_self = self;
	[alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse return_code) {
		if (return_code != NSAlertFirstButtonReturn) {
			return;
		}

		MBHighlightsController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		[strong_self deleteHighlight:highlight];
	}];
}

- (IBAction) copySelectedHighlight:(id) sender
{
	#pragma unused(sender)
	MBHighlight* highlight = [self selectedHighlight];
	if (![highlight isKindOfClass:[MBHighlight class]]) {
		return;
	}

	NSString* selection_text = highlight.selectionText ?: @"";
	if (selection_text.length == 0) {
		return;
	}

	NSPasteboard* pasteboard = [NSPasteboard generalPasteboard];
	[pasteboard clearContents];
	[pasteboard setString:selection_text forType:NSPasteboardTypeString];
}

- (IBAction) openSelectedHighlightInBrowser:(id) sender
{
	#pragma unused(sender)
	MBHighlight* highlight = [self selectedHighlight];
	if (![highlight isKindOfClass:[MBHighlight class]]) {
		return;
	}

	NSString* url_string = [self URLStringForHighlight:highlight];
	if (url_string.length == 0) {
		return;
	}

	[NSString mb_openURLStringInBrowser:url_string];
}

- (IBAction) copySelectedHighlightLink:(id) sender
{
	#pragma unused(sender)
	MBHighlight* highlight = [self selectedHighlight];
	if (![highlight isKindOfClass:[MBHighlight class]]) {
		return;
	}

	NSString* url_string = [self URLStringForHighlight:highlight];
	if (url_string.length == 0) {
		return;
	}

	NSPasteboard* pasteboard = [NSPasteboard generalPasteboard];
	[pasteboard clearContents];
	[pasteboard setString:url_string forType:NSPasteboardTypeString];
}

- (void) deleteHighlight:(MBHighlight*) highlight
{
	if (![self canDeleteHighlight:highlight]) {
		return;
	}

	[self setFetchingState:YES];

	__weak typeof(self) weak_self = self;
	[self.client deleteHighlight:highlight token:self.token completion:^(NSError* _Nullable error) {
		MBHighlightsController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		[strong_self setFetchingState:NO];
		if (error != nil) {
			[strong_self presentDeleteError:error];
			return;
		}

		if (strong_self.highlightDeletedHandler != nil) {
			strong_self.highlightDeletedHandler(highlight);
		}
		[strong_self reloadHighlights];
	}];
}

- (void) presentDeleteError:(NSError*) error
{
	if (error == nil || self.window == nil) {
		return;
	}

	NSAlert* alert = [[NSAlert alloc] init];
	alert.alertStyle = NSAlertStyleWarning;
	alert.messageText = @"Delete Failed";
	alert.informativeText = error.localizedDescription ?: @"The highlight could not be deleted.";
	[alert beginSheetModalForWindow:self.window completionHandler:nil];
}

- (NSString*) markdownTextForNewPostFromHighlight:(MBHighlight*) highlight
{
	if (![highlight isKindOfClass:[MBHighlight class]]) {
		return @"";
	}

	NSString* title_string = [self titleForHighlight:highlight];
	NSString* url_string = [self URLStringForHighlight:highlight];
	NSString* selection_text = highlight.selectionText ?: @"";
	NSString* blockquote_text = [self blockquoteMarkdownFromText:selection_text];
	if (title_string.length == 0 || url_string.length == 0 || blockquote_text.length == 0) {
		return @"";
	}

	return [NSString stringWithFormat:@"[%@](%@):\n\n%@", title_string, url_string, blockquote_text];
}

- (NSString*) titleForHighlight:(MBHighlight*) highlight
{
	if (![highlight isKindOfClass:[MBHighlight class]]) {
		return @"";
	}

	NSString* title_string = [highlight.postTitle stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (title_string.length == 0 && highlight.entryID == self.entryID) {
		title_string = [self.entryTitleForPost stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	}

	return title_string;
}

- (NSString*) URLStringForHighlight:(MBHighlight*) highlight
{
	if (![highlight isKindOfClass:[MBHighlight class]]) {
		return @"";
	}

	NSString* url_string = [highlight.postURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (url_string.length == 0 && highlight.entryID == self.entryID) {
		url_string = [self.entryURLString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	}

	return url_string;
}

- (NSString*) blockquoteMarkdownFromText:(NSString*) text_string
{
	NSString* normalized_text = [text_string stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] ?: @"";
	normalized_text = [normalized_text stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"] ?: @"";
	if (normalized_text.length == 0) {
		return @"";
	}

	NSArray* lines = [normalized_text componentsSeparatedByString:@"\n"];
	NSMutableArray* quoted_lines = [NSMutableArray array];
	for (NSString* line in lines) {
		[quoted_lines addObject:[NSString stringWithFormat:@"> %@", line ?: @""]];
	}

	return [quoted_lines componentsJoinedByString:@"\n"] ?: @"";
}

- (BOOL) validateMenuItem:(NSMenuItem*) menu_item
{
	if (menu_item.action == @selector(newPostFromSelectedHighlight:)) {
		return [self canCreatePostFromSelectedHighlight];
	}
	if (menu_item.action == @selector(promptToDeleteSelectedHighlight:)) {
		return [self canDeleteSelectedHighlight];
	}
	if (menu_item.action == @selector(openSelectedHighlightInBrowser:)) {
		return [self canOpenSelectedHighlightInBrowser];
	}
	if (menu_item.action == @selector(copySelectedHighlightLink:)) {
		return [self canCopySelectedHighlightLink];
	}
	if (menu_item.action == @selector(copySelectedHighlight:)) {
		return [self canCopySelectedHighlight];
	}

	return YES;
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

- (NSImage*) avatarImageForHost:(NSString*) host_value fadeAmount:(CGFloat) fade_amount
{
	NSString* icon_url_string = [self avatarURLStringForHost:host_value];
	if (icon_url_string.length == 0) {
		return [self flattenedHeaderAvatarImage:[self defaultAvatarImage] fadeAmount:fade_amount];
	}

	NSImage* cached_image = [self.avatarLoader cachedImageForURLString:icon_url_string];
	if (cached_image != nil) {
		return [self flattenedHeaderAvatarImage:cached_image fadeAmount:fade_amount];
	}

	[self.avatarLoader loadImageForURLString:icon_url_string];
	return [self flattenedHeaderAvatarImage:[self defaultAvatarImage] fadeAmount:fade_amount];
}

- (NSImage*) avatarImageForHost:(NSString*) host_value
{
	return [self avatarImageForHost:host_value fadeAmount:0.0];
}

- (NSString*) avatarURLStringForHost:(NSString*) host_value
{
	NSString* icon_url_string = self.iconURLByHost[host_value] ?: @"";
	return [icon_url_string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
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
	if (self.progressIndicator == nil || self.progressIndicatorWidthConstraint == nil) {
		return;
	}

	if (self.isFetching) {
		self.progressIndicatorWidthConstraint.constant = 16.0;
		self.progressIndicator.hidden = NO;
		[self.progressIndicator startAnimation:nil];
	}
	else {
		[self.progressIndicator stopAnimation:nil];
		self.progressIndicator.hidden = YES;
		self.progressIndicatorWidthConstraint.constant = 0.0;
	}
}

@end
