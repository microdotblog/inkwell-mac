//
//  MBConversationController.m
//  Inkwell
//
//  Created by Codex on 3/7/26.
//

#import "MBConversationController.h"
#import "MBAvatarLoader.h"
#import "MBClient.h"
#import "MBConversationCellView.h"
#import "MBEntry.h"
#import "MBMention.h"

static NSUserInterfaceItemIdentifier const InkwellConversationCellIdentifier = @"InkwellConversationCell";
static CGFloat const InkwellConversationTopBarHeight = 44.0;
static CGFloat const InkwellConversationHeaderAvatarSize = 20.0;
static CGFloat const InkwellConversationEstimatedRowHeight = 72.0;
static CGFloat const InkwellConversationDefaultAvatarSize = 34.0;

@interface MBConversationController () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) MBClient* client;
@property (nonatomic, copy) NSString* token;
@property (nonatomic, copy) NSDictionary* conversationPayload;
@property (nonatomic, copy) NSArray* mentions;
@property (nonatomic, strong) NSTableView* tableView;
@property (nonatomic, strong) NSImageView* headerAvatarImageView;
@property (nonatomic, strong) NSTextField* headerTitleTextField;
@property (nonatomic, strong) MBAvatarLoader* avatarLoader;
@property (nonatomic, copy) NSString* headerTitle;
@property (nonatomic, strong) NSImage* headerAvatarImage;
@property (nonatomic, copy) NSString* headerFeedHost;
@property (nonatomic, copy) NSDictionary* iconURLByHost;
@property (nonatomic, assign) BOOL hasLoadedFeedIcons;
@property (nonatomic, assign) BOOL isFetchingFeedIcons;
@property (nonatomic, assign) BOOL didSetupContent;

@end

@implementation MBConversationController

- (instancetype) init
{
	return [self initWithClient:nil token:nil];
}

- (instancetype) initWithClient:(MBClient* _Nullable) client token:(NSString* _Nullable) token
{
	self = [super initWithWindow:nil];
	if (self) {
		self.client = client;
		self.token = token ?: @"";
		self.conversationPayload = @{};
		self.mentions = @[];
		self.avatarLoader = [MBAvatarLoader sharedLoader];
		self.headerTitle = @"Conversation";
		self.headerAvatarImage = [self defaultHeaderAvatarImage];
		self.headerFeedHost = @"";
		self.iconURLByHost = @{};
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(avatarImageDidLoad:) name:MBAvatarLoaderDidLoadImageNotification object:self.avatarLoader];
	}
	return self;
}

- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self name:MBAvatarLoaderDidLoadImageNotification object:self.avatarLoader];
}

- (void) showWindow:(id)sender
{
	[self setupWindowIfNeeded];
	[self setupContentIfNeeded];
	[super showWindow:sender];
	[self.window makeKeyAndOrderFront:sender];
}

- (void) updateWithConversationPayload:(NSDictionary* _Nullable) conversation_payload
{
	if (![conversation_payload isKindOfClass:[NSDictionary class]]) {
		self.conversationPayload = @{};
	}
	else {
		self.conversationPayload = [conversation_payload copy];
	}

	self.mentions = [self mentionsFromConversationPayload:self.conversationPayload];
	[self updateWindowTitleState];
	[self.tableView reloadData];
}

- (void) updateForSelectedEntry:(MBEntry* _Nullable) entry
{
	if (entry == nil) {
		self.headerTitle = @"Conversation";
		self.headerFeedHost = @"";
		self.headerAvatarImage = [self defaultHeaderAvatarImage];
		[self applyHeaderIfNeeded];
		return;
	}

	NSString* title_string = [entry.title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (title_string.length == 0) {
		title_string = [entry.subscriptionTitle stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	}
	if (title_string.length == 0) {
		title_string = @"Conversation";
	}

	self.headerTitle = title_string;
	self.headerFeedHost = [self normalizedHostString:entry.feedHost ?: @""];
	self.headerAvatarImage = [self headerAvatarImageForHost:self.headerFeedHost];
	[self applyHeaderIfNeeded];
	[self fetchFeedIconsIfNeeded];
}

- (void) setupWindowIfNeeded
{
	if (self.window != nil) {
		return;
	}

	NSRect frame = NSMakeRect(260.0, 260.0, 460.0, 520.0);
	NSUInteger style_mask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow;
	NSPanel* panel = [[NSPanel alloc] initWithContentRect:frame styleMask:style_mask backing:NSBackingStoreBuffered defer:NO];
	panel.floatingPanel = YES;
	panel.hidesOnDeactivate = YES;
	panel.level = NSFloatingWindowLevel;
	panel.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace;
	panel.releasedWhenClosed = NO;
	panel.minSize = NSMakeSize(320.0, 260.0);
	panel.title = @"Conversation";
	[panel setFrameAutosaveName:@"ConversationWindow"];
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
	avatar_image_view.layer.cornerRadius = (InkwellConversationHeaderAvatarSize / 2.0);
	avatar_image_view.layer.masksToBounds = YES;

	NSTextField* title_text_field = [NSTextField labelWithString:@""];
	title_text_field.translatesAutoresizingMaskIntoConstraints = NO;
	title_text_field.lineBreakMode = NSLineBreakByTruncatingTail;
	title_text_field.maximumNumberOfLines = 1;
	title_text_field.usesSingleLineMode = YES;
	title_text_field.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
	[title_text_field setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
	[title_text_field setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

	[top_container_view addSubview:avatar_image_view];
	[top_container_view addSubview:title_text_field];

	NSTableView* table_view = [[NSTableView alloc] initWithFrame:NSZeroRect];
	table_view.translatesAutoresizingMaskIntoConstraints = NO;
	table_view.delegate = self;
	table_view.dataSource = self;
	table_view.headerView = nil;
	table_view.rowHeight = InkwellConversationEstimatedRowHeight;
	table_view.intercellSpacing = NSMakeSize(0.0, 0.0);
	table_view.usesAutomaticRowHeights = YES;
	table_view.allowsMultipleSelection = NO;
	table_view.allowsEmptySelection = YES;

	NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"ConversationColumn"];
	column.resizingMask = NSTableColumnAutoresizingMask;
	column.editable = NO;
	[table_view addTableColumn:column];

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
		[top_container_view.heightAnchor constraintEqualToConstant:InkwellConversationTopBarHeight],
		[avatar_image_view.leadingAnchor constraintEqualToAnchor:top_container_view.leadingAnchor constant:10.0],
		[avatar_image_view.centerYAnchor constraintEqualToAnchor:top_container_view.centerYAnchor],
		[avatar_image_view.widthAnchor constraintEqualToConstant:InkwellConversationHeaderAvatarSize],
		[avatar_image_view.heightAnchor constraintEqualToConstant:InkwellConversationHeaderAvatarSize],
		[title_text_field.leadingAnchor constraintEqualToAnchor:avatar_image_view.trailingAnchor constant:8.0],
		[title_text_field.trailingAnchor constraintEqualToAnchor:top_container_view.trailingAnchor constant:-10.0],
		[title_text_field.centerYAnchor constraintEqualToAnchor:top_container_view.centerYAnchor],
		[scroll_view.topAnchor constraintEqualToAnchor:top_container_view.bottomAnchor],
		[scroll_view.bottomAnchor constraintEqualToAnchor:content_view.bottomAnchor],
		[scroll_view.leadingAnchor constraintEqualToAnchor:content_view.leadingAnchor],
		[scroll_view.trailingAnchor constraintEqualToAnchor:content_view.trailingAnchor]
	]];

	self.tableView = table_view;
	self.headerAvatarImageView = avatar_image_view;
	self.headerTitleTextField = title_text_field;
	self.didSetupContent = YES;
	[self updateWindowTitleState];
	[self applyHeaderIfNeeded];
}

- (NSInteger) numberOfRowsInTableView:(NSTableView*) tableView
{
	#pragma unused(tableView)
	return self.mentions.count;
}

- (NSView*) tableView:(NSTableView*) tableView viewForTableColumn:(NSTableColumn*) tableColumn row:(NSInteger) row
{
	#pragma unused(tableColumn)
	if (row < 0 || row >= self.mentions.count) {
		return nil;
	}

	MBConversationCellView* cell_view = [tableView makeViewWithIdentifier:InkwellConversationCellIdentifier owner:self];
	if (cell_view == nil) {
		cell_view = [[MBConversationCellView alloc] initWithFrame:NSZeroRect];
		cell_view.identifier = InkwellConversationCellIdentifier;
	}

	MBMention* mention = self.mentions[row];
	NSImage* avatar_image = [self avatarImageForMention:mention];
	NSString* date_text = [self formattedDateString:mention.date];
	[cell_view configureWithMention:mention dateText:date_text avatarImage:avatar_image];
	return cell_view;
}

- (void) updateWindowTitleState
{
	self.window.title = @"Conversation";
}

- (void) applyHeaderIfNeeded
{
	if (self.headerTitleTextField != nil) {
		self.headerTitleTextField.stringValue = self.headerTitle ?: @"Conversation";
	}

	if (self.headerAvatarImageView != nil) {
		self.headerAvatarImageView.image = self.headerAvatarImage ?: [self defaultHeaderAvatarImage];
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
	[self.client fetchFeedIconsWithToken:self.token completion:^(NSDictionary* _Nullable icons_by_host, NSError* _Nullable error) {
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
	self.headerAvatarImage = [self headerAvatarImageForHost:self.headerFeedHost];
	[self applyHeaderIfNeeded];
}

- (void) avatarImageDidLoad:(NSNotification*) notification
{
	NSString* url_string = [self stringValueFromObject:notification.userInfo[MBAvatarLoaderURLStringUserInfoKey]];
	if (url_string.length == 0) {
		return;
	}

	NSString* header_url_string = [self headerAvatarURLStringForHost:self.headerFeedHost];
	if ([header_url_string isEqualToString:url_string]) {
		[self updateHeaderAvatarImage];
	}

	for (MBMention* mention in self.mentions) {
		NSString* mention_avatar_url = [mention.avatarURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		if ([mention_avatar_url isEqualToString:url_string]) {
			[self.tableView reloadData];
			break;
		}
	}
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

		NSString* url_value = [self stringValueFromObject:icons_by_host[host_value]];
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

- (NSImage*) headerAvatarImageForHost:(NSString*) host_value
{
	NSString* icon_url_string = [self headerAvatarURLStringForHost:host_value];
	if (icon_url_string.length == 0) {
		return [self defaultHeaderAvatarImage];
	}

	NSImage* cached_image = [self.avatarLoader cachedImageForURLString:icon_url_string];
	if (cached_image != nil) {
		return cached_image;
	}

	[self.avatarLoader loadImageForURLString:icon_url_string];
	return [self defaultHeaderAvatarImage];
}

- (NSString*) headerAvatarURLStringForHost:(NSString*) host_value
{
	NSString* icon_url_string = [self stringValueFromObject:self.iconURLByHost[host_value]];
	return [icon_url_string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

- (NSArray*) mentionsFromConversationPayload:(NSDictionary*) conversation_payload
{
	id items_object = conversation_payload[@"items"];
	if (![items_object isKindOfClass:[NSArray class]]) {
		return @[];
	}

	NSMutableArray* mentions = [NSMutableArray array];
	for (id object in (NSArray*) items_object) {
		if (![object isKindOfClass:[NSDictionary class]]) {
			continue;
		}

		NSDictionary* item = (NSDictionary*) object;
		NSDictionary* author = [self dictionaryValueFromObject:item[@"author"]];
		NSDictionary* microblog = [self dictionaryValueFromObject:author[@"_microblog"]];

		MBMention* mention = [[MBMention alloc] init];
		mention.avatarURL = [self stringValueFromObject:author[@"avatar"]];
		mention.fullName = [self stringValueFromObject:author[@"name"]];
		mention.username = [self stringValueFromObject:microblog[@"username"]];

		NSString* content_html = [self stringValueFromObject:item[@"content_html"]];
		NSString* content_text = [self stringValueFromObject:item[@"content_text"]];
		NSString* text_value = [self plainTextFromHTMLString:content_html];
		if (text_value.length == 0) {
			text_value = [self normalizedTextString:content_text];
		}
		mention.text = text_value;

		NSString* date_string = [self stringValueFromObject:item[@"date_published"]];
		mention.date = [self dateFromISO8601String:date_string];
		[mentions addObject:mention];
	}

	return [mentions copy];
}

- (NSDictionary*) dictionaryValueFromObject:(id) object
{
	if ([object isKindOfClass:[NSDictionary class]]) {
		return (NSDictionary*) object;
	}
	return @{};
}

- (NSString*) stringValueFromObject:(id) object
{
	if ([object isKindOfClass:[NSString class]]) {
		return (NSString*) object;
	}
	if ([object isKindOfClass:[NSNumber class]]) {
		return [(NSNumber*) object stringValue] ?: @"";
	}
	return @"";
}

- (NSString*) plainTextFromHTMLString:(NSString*) html_string
{
	NSString* trimmed_html = [html_string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (trimmed_html.length == 0) {
		return @"";
	}

	NSData* html_data = [trimmed_html dataUsingEncoding:NSUTF8StringEncoding];
	if (html_data.length == 0) {
		return @"";
	}

	NSDictionary* options = @{
		NSDocumentTypeDocumentOption: NSHTMLTextDocumentType,
		NSCharacterEncodingDocumentOption: @(NSUTF8StringEncoding)
	};
	NSAttributedString* attributed_string = [[NSAttributedString alloc] initWithData:html_data options:options documentAttributes:nil error:nil];
	NSString* plain_text = attributed_string.string ?: @"";
	return [self normalizedTextString:plain_text];
}

- (NSString*) normalizedTextString:(NSString*) text_string
{
	NSString* normalized_text = [text_string stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] ?: @"";
	normalized_text = [normalized_text stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"] ?: @"";

	while ([normalized_text containsString:@"\n\n\n"]) {
		normalized_text = [normalized_text stringByReplacingOccurrencesOfString:@"\n\n\n" withString:@"\n\n"];
	}

	NSString* trimmed_text = [normalized_text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	return trimmed_text;
}

- (NSDate* _Nullable) dateFromISO8601String:(NSString*) date_string
{
	NSString* trimmed_string = [date_string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (trimmed_string.length == 0) {
		return nil;
	}

	static NSISO8601DateFormatter* fractional_date_formatter;
	static NSISO8601DateFormatter* default_date_formatter;
	static dispatch_once_t once_token;
	dispatch_once(&once_token, ^{
		fractional_date_formatter = [[NSISO8601DateFormatter alloc] init];
		fractional_date_formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;

		default_date_formatter = [[NSISO8601DateFormatter alloc] init];
		default_date_formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
	});

	NSDate* date_value = [fractional_date_formatter dateFromString:trimmed_string];
	if (date_value == nil) {
		date_value = [default_date_formatter dateFromString:trimmed_string];
	}
	return date_value;
}

- (NSString*) formattedDateString:(NSDate*) date_value
{
	if (date_value == nil) {
		return @"";
	}

	return [NSDateFormatter localizedStringFromDate:date_value dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle] ?: @"";
}

- (NSImage*) avatarImageForMention:(MBMention*) mention
{
	NSString* avatar_url = [mention.avatarURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
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

- (NSImage*) defaultAvatarImage
{
	static NSImage* fallback_image;
	static dispatch_once_t once_token;
	dispatch_once(&once_token, ^{
		NSSize image_size = NSMakeSize(InkwellConversationDefaultAvatarSize, InkwellConversationDefaultAvatarSize);
		fallback_image = [[NSImage alloc] initWithSize:image_size];
		[fallback_image lockFocus];
		[[NSColor clearColor] setFill];
		NSRectFill(NSMakeRect(0.0, 0.0, image_size.width, image_size.height));

		NSBezierPath* circle_path = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0.0, 0.0, image_size.width, image_size.height)];
		[[NSColor colorWithWhite:0.82 alpha:1.0] setFill];
		[circle_path fill];
		[fallback_image unlockFocus];
	});

	return fallback_image;
}

- (NSImage*) defaultHeaderAvatarImage
{
	static NSImage* fallback_image;
	static dispatch_once_t once_token;
	dispatch_once(&once_token, ^{
		NSSize image_size = NSMakeSize(InkwellConversationHeaderAvatarSize, InkwellConversationHeaderAvatarSize);
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

@end
