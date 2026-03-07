//
//  MBConversationController.m
//  Inkwell
//
//  Created by Codex on 3/7/26.
//

#import "MBConversationController.h"
#import "MBConversationCellView.h"
#import "MBMention.h"

static NSUserInterfaceItemIdentifier const InkwellConversationCellIdentifier = @"InkwellConversationCell";
static CGFloat const InkwellConversationRowHeight = 96.0;
static CGFloat const InkwellConversationDefaultAvatarSize = 34.0;

@interface MBConversationController () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, copy) NSDictionary* conversationPayload;
@property (nonatomic, copy) NSArray* mentions;
@property (nonatomic, strong) NSTableView* tableView;
@property (nonatomic, strong) NSURLSession* imageSession;
@property (nonatomic, strong) NSMutableDictionary* avatarImageByURL;
@property (nonatomic, strong) NSMutableSet* pendingAvatarURLStrings;
@property (nonatomic, strong) NSDateFormatter* dateFormatter;
@property (nonatomic, assign) BOOL didSetupContent;

@end

@implementation MBConversationController

- (instancetype) init
{
	self = [super initWithWindow:nil];
	if (self) {
		self.conversationPayload = @{};
		self.mentions = @[];
		self.avatarImageByURL = [NSMutableDictionary dictionary];
		self.pendingAvatarURLStrings = [NSMutableSet set];
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

	NSTableView* table_view = [[NSTableView alloc] initWithFrame:NSZeroRect];
	table_view.translatesAutoresizingMaskIntoConstraints = NO;
	table_view.delegate = self;
	table_view.dataSource = self;
	table_view.headerView = nil;
	table_view.rowHeight = InkwellConversationRowHeight;
	table_view.intercellSpacing = NSMakeSize(0.0, 2.0);
	table_view.usesAutomaticRowHeights = NO;
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

	[content_view addSubview:scroll_view];
	[NSLayoutConstraint activateConstraints:@[
		[scroll_view.topAnchor constraintEqualToAnchor:content_view.topAnchor],
		[scroll_view.bottomAnchor constraintEqualToAnchor:content_view.bottomAnchor],
		[scroll_view.leadingAnchor constraintEqualToAnchor:content_view.leadingAnchor],
		[scroll_view.trailingAnchor constraintEqualToAnchor:content_view.trailingAnchor]
	]];

	self.tableView = table_view;
	self.didSetupContent = YES;
	[self updateWindowTitleState];
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
	NSString* title_string = @"Conversation";
	if (self.mentions.count == 1) {
		title_string = @"Conversation (1 reply)";
	}
	else if (self.mentions.count > 1) {
		title_string = [NSString stringWithFormat:@"Conversation (%ld replies)", (long) self.mentions.count];
	}

	self.window.title = title_string;
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

	if (self.dateFormatter == nil) {
		NSDateFormatter* date_formatter = [[NSDateFormatter alloc] init];
		date_formatter.dateStyle = NSDateFormatterMediumStyle;
		date_formatter.timeStyle = NSDateFormatterShortStyle;
		self.dateFormatter = date_formatter;
	}

	return [self.dateFormatter stringFromDate:date_value] ?: @"";
}

- (NSImage*) avatarImageForMention:(MBMention*) mention
{
	NSString* avatar_url = [mention.avatarURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (avatar_url.length == 0) {
		return [self defaultAvatarImage];
	}

	NSImage* cached_image = self.avatarImageByURL[avatar_url];
	if (cached_image != nil) {
		return cached_image;
	}

	[self requestAvatarImageForURLString:avatar_url];
	return [self defaultAvatarImage];
}

- (void) requestAvatarImageForURLString:(NSString*) avatar_url
{
	if (avatar_url.length == 0) {
		return;
	}
	if (self.avatarImageByURL[avatar_url] != nil) {
		return;
	}
	if ([self.pendingAvatarURLStrings containsObject:avatar_url]) {
		return;
	}

	NSURL* image_url = [NSURL URLWithString:avatar_url];
	if (image_url == nil) {
		return;
	}

	[self.pendingAvatarURLStrings addObject:avatar_url];
	__weak typeof(self) weak_self = self;
	NSURLSessionDataTask* task = [self.imageSession dataTaskWithURL:image_url completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
		#pragma unused(response)
		MBConversationController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		NSImage* image_value = nil;
		if (error == nil && data.length > 0) {
			image_value = [[NSImage alloc] initWithData:data];
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			[strong_self.pendingAvatarURLStrings removeObject:avatar_url];
			if (image_value == nil) {
				return;
			}

			strong_self.avatarImageByURL[avatar_url] = image_value;
			[strong_self.tableView reloadData];
		});
	}];
	[task resume];
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

@end
