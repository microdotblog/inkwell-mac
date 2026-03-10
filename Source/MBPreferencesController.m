//
//  MBPreferencesController.m
//  Inkwell
//
//  Created by Codex on 3/7/26.
//

#import "MBPreferencesController.h"
#import "MBClient.h"
#import "MBFeedsController.h"

static CGFloat const InkwellPreferencesAvatarSize = 44.0;
static CGFloat const InkwellPreferencesColorSwatchSize = 30.0;
static CGFloat const InkwellPreferencesPopupMinWidth = 180.0;
static CGFloat const InkwellPreferencesPopupMaxWidth = 240.0;
static CGFloat const InkwellPreferencesSettingsLabelFontSize = 15.0;
static CGFloat const InkwellPreferencesSectionLeadingInset = 33.0;
static CGFloat const InkwellPreferencesSectionTopSpacing = 19.0;
static CGFloat const InkwellPreferencesRowSpacing = 16.0;
static CGFloat const InkwellPreferencesWindowHeight = 600.0;
static NSString* const InkwellDefaultTextBackgroundHex = @"#ffffff";
static NSString* const InkwellDefaultTextFontName = @"San Francisco";
static NSString* const InkwellDefaultTextSizeName = @"Medium";

@interface MBPreferencesController ()

@property (nonatomic, strong) NSImageView* avatarImageView;
@property (nonatomic, strong) NSTextField* usernameTextField;
@property (nonatomic, strong) NSPopUpButton* fontPopUpButton;
@property (nonatomic, strong) NSPopUpButton* sizePopUpButton;
@property (nonatomic, strong) NSSearchField* feedsSearchField;
@property (nonatomic, copy) NSArray* backgroundColorHexes;
@property (nonatomic, copy) NSArray* fontNames;
@property (nonatomic, copy) NSArray* sizeNames;
@property (nonatomic, strong) NSMutableArray* backgroundColorButtons;
@property (nonatomic, strong) MBClient* client;
@property (nonatomic, copy) NSString* token;
@property (nonatomic, strong) MBFeedsController* feedsController;
@property (nonatomic, strong) NSURLSession* avatarSession;
@property (nonatomic, assign) BOOL didSetupContent;

@end

@implementation MBPreferencesController

- (instancetype) init
{
	return [self initWithClient:nil token:nil];
}

- (instancetype) initWithClient:(MBClient* _Nullable) client token:(NSString* _Nullable) token
{
	self = [super initWithWindow:nil];
	if (self) {
		self.backgroundColorHexes = @[ @"#ffffff", @"#f1f2f4", @"#e5dcc8", @"#1c2435", @"#000000" ];
		self.fontNames = @[ @"San Francisco", @"Avenir Next", @"Times New Roman" ];
		self.sizeNames = @[ @"Tiny", @"Small", @"Medium", @"Large", @"Huge" ];
		self.backgroundColorButtons = [NSMutableArray array];
		self.client = client ?: [[MBClient alloc] init];
		self.token = [token stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		self.feedsController = [[MBFeedsController alloc] initWithClient:self.client token:self.token];
		self.avatarSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
	}
	return self;
}

- (void) showWindow:(id)sender
{
	[self setupWindowIfNeeded];
	[self setupContentIfNeeded];
	[self applyWindowHeightIfNeeded];
	[self reloadFromDefaults];
	[self.feedsController reloadFeeds];
	[super showWindow:sender];
	[self.window makeKeyAndOrderFront:sender];
}

- (void) dealloc
{
	if (self.feedsSearchField != nil) {
		[[NSNotificationCenter defaultCenter] removeObserver:self name:NSControlTextDidChangeNotification object:self.feedsSearchField];
	}
}

- (void) setupWindowIfNeeded
{
	if (self.window != nil) {
		return;
	}

	NSRect frame = NSMakeRect(250.0, 250.0, 430.0, InkwellPreferencesWindowHeight);
	NSUInteger style_mask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
	NSWindow* window = [[NSWindow alloc] initWithContentRect:frame styleMask:style_mask backing:NSBackingStoreBuffered defer:NO];
	window.title = @"Preferences";
	window.releasedWhenClosed = NO;
	window.minSize = NSMakeSize(390.0, InkwellPreferencesWindowHeight);
	[window setFrameAutosaveName:@"PreferencesWindow"];
	self.window = window;
}

- (void) applyWindowHeightIfNeeded
{
	if (self.window == nil || self.window.contentView == nil) {
		return;
	}

	NSSize content_size = self.window.contentView.frame.size;
	if (fabs(content_size.height - InkwellPreferencesWindowHeight) < 0.5) {
		return;
	}

	[self.window setContentSize:NSMakeSize(content_size.width, InkwellPreferencesWindowHeight)];
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

	NSImageView* avatar_image_view = [[NSImageView alloc] initWithFrame:NSZeroRect];
	avatar_image_view.translatesAutoresizingMaskIntoConstraints = NO;
	avatar_image_view.wantsLayer = YES;
	avatar_image_view.layer.cornerRadius = (InkwellPreferencesAvatarSize / 2.0);
	avatar_image_view.layer.masksToBounds = YES;
	avatar_image_view.imageScaling = NSImageScaleAxesIndependently;
	[content_view addSubview:avatar_image_view];

	NSTextField* username_text_field = [NSTextField labelWithString:@""];
	username_text_field.translatesAutoresizingMaskIntoConstraints = NO;
	username_text_field.font = [NSFont systemFontOfSize:15.0 weight:NSFontWeightSemibold];
	username_text_field.lineBreakMode = NSLineBreakByTruncatingTail;
	username_text_field.maximumNumberOfLines = 1;
	username_text_field.usesSingleLineMode = YES;
	[content_view addSubview:username_text_field];

	NSButton* sign_out_button = [NSButton buttonWithTitle:@"Sign Out" target:self action:@selector(signOut:)];
	sign_out_button.translatesAutoresizingMaskIntoConstraints = NO;
	sign_out_button.bezelStyle = NSBezelStyleRounded;
	[content_view addSubview:sign_out_button];

	NSBox* separator_line = [[NSBox alloc] initWithFrame:NSZeroRect];
	separator_line.translatesAutoresizingMaskIntoConstraints = NO;
	separator_line.boxType = NSBoxSeparator;
	[content_view addSubview:separator_line];

	NSTextField* background_label = [NSTextField labelWithString:@"Background:"];
	background_label.translatesAutoresizingMaskIntoConstraints = NO;
	background_label.font = [NSFont systemFontOfSize:InkwellPreferencesSettingsLabelFontSize weight:NSFontWeightSemibold];
	background_label.alignment = NSTextAlignmentRight;
	[content_view addSubview:background_label];

	NSStackView* color_stack_view = [[NSStackView alloc] initWithFrame:NSZeroRect];
	color_stack_view.translatesAutoresizingMaskIntoConstraints = NO;
	color_stack_view.orientation = NSUserInterfaceLayoutOrientationHorizontal;
	color_stack_view.spacing = 8.0;
	color_stack_view.alignment = NSLayoutAttributeCenterY;
	[content_view addSubview:color_stack_view];

	[self.backgroundColorButtons removeAllObjects];
	for (NSInteger i = 0; i < self.backgroundColorHexes.count; i++) {
		NSString* color_hex = self.backgroundColorHexes[i];
		NSButton* color_button = [NSButton buttonWithTitle:@"" target:self action:@selector(selectBackgroundColor:)];
		color_button.translatesAutoresizingMaskIntoConstraints = NO;
		color_button.tag = i;
		color_button.bordered = NO;
		color_button.wantsLayer = YES;
		color_button.layer.cornerRadius = 9.0;
		color_button.layer.borderWidth = 1.0;
		color_button.layer.borderColor = [NSColor colorWithWhite:0.70 alpha:1.0].CGColor;
		color_button.layer.backgroundColor = [self colorFromHexString:color_hex].CGColor;
		[color_button.widthAnchor constraintEqualToConstant:InkwellPreferencesColorSwatchSize].active = YES;
		[color_button.heightAnchor constraintEqualToConstant:InkwellPreferencesColorSwatchSize].active = YES;
		[color_stack_view addArrangedSubview:color_button];
		[self.backgroundColorButtons addObject:color_button];
	}

	NSTextField* font_label = [NSTextField labelWithString:@"Font:"];
	font_label.translatesAutoresizingMaskIntoConstraints = NO;
	font_label.font = [NSFont systemFontOfSize:InkwellPreferencesSettingsLabelFontSize weight:NSFontWeightSemibold];
	font_label.alignment = NSTextAlignmentRight;
	[content_view addSubview:font_label];

	NSPopUpButton* font_popup_button = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
	font_popup_button.translatesAutoresizingMaskIntoConstraints = NO;
	font_popup_button.target = self;
	font_popup_button.action = @selector(selectFont:);
	for (NSString* font_name in self.fontNames) {
		[font_popup_button addItemWithTitle:font_name];
	}
	[content_view addSubview:font_popup_button];

	NSTextField* size_label = [NSTextField labelWithString:@"Size:"];
	size_label.translatesAutoresizingMaskIntoConstraints = NO;
	size_label.font = [NSFont systemFontOfSize:InkwellPreferencesSettingsLabelFontSize weight:NSFontWeightSemibold];
	size_label.alignment = NSTextAlignmentRight;
	[content_view addSubview:size_label];

	NSPopUpButton* size_popup_button = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
	size_popup_button.translatesAutoresizingMaskIntoConstraints = NO;
	size_popup_button.target = self;
	size_popup_button.action = @selector(selectSize:);
	for (NSString* size_name in self.sizeNames) {
		[size_popup_button addItemWithTitle:size_name];
	}
	[content_view addSubview:size_popup_button];

	NSBox* feeds_separator_line = [[NSBox alloc] initWithFrame:NSZeroRect];
	feeds_separator_line.translatesAutoresizingMaskIntoConstraints = NO;
	feeds_separator_line.boxType = NSBoxSeparator;
	[content_view addSubview:feeds_separator_line];

	NSTextField* feeds_label = [NSTextField labelWithString:@"Feeds:"];
	feeds_label.translatesAutoresizingMaskIntoConstraints = NO;
	feeds_label.font = [NSFont systemFontOfSize:InkwellPreferencesSettingsLabelFontSize weight:NSFontWeightSemibold];
	[content_view addSubview:feeds_label];

	NSSearchField* feeds_search_field = [[NSSearchField alloc] initWithFrame:NSZeroRect];
	feeds_search_field.translatesAutoresizingMaskIntoConstraints = NO;
	feeds_search_field.controlSize = NSControlSizeSmall;
	feeds_search_field.placeholderString = @"Search feeds";
	[feeds_search_field setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
	[feeds_search_field setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
	[content_view addSubview:feeds_search_field];

	NSView* feeds_view = self.feedsController.view;
	feeds_view.translatesAutoresizingMaskIntoConstraints = NO;
	[content_view addSubview:feeds_view];

	[NSLayoutConstraint activateConstraints:@[
		[avatar_image_view.topAnchor constraintEqualToAnchor:content_view.topAnchor constant:16.0],
		[avatar_image_view.leadingAnchor constraintEqualToAnchor:content_view.leadingAnchor constant:18.0],
		[avatar_image_view.widthAnchor constraintEqualToConstant:InkwellPreferencesAvatarSize],
		[avatar_image_view.heightAnchor constraintEqualToConstant:InkwellPreferencesAvatarSize],

		[username_text_field.centerYAnchor constraintEqualToAnchor:avatar_image_view.centerYAnchor],
		[username_text_field.leadingAnchor constraintEqualToAnchor:avatar_image_view.trailingAnchor constant:12.0],
		[username_text_field.trailingAnchor constraintLessThanOrEqualToAnchor:sign_out_button.leadingAnchor constant:-12.0],

		[sign_out_button.centerYAnchor constraintEqualToAnchor:avatar_image_view.centerYAnchor],
		[sign_out_button.trailingAnchor constraintEqualToAnchor:content_view.trailingAnchor constant:-18.0],

		[separator_line.topAnchor constraintEqualToAnchor:avatar_image_view.bottomAnchor constant:14.0],
		[separator_line.leadingAnchor constraintEqualToAnchor:content_view.leadingAnchor constant:18.0],
		[separator_line.trailingAnchor constraintEqualToAnchor:content_view.trailingAnchor constant:-18.0],

		[background_label.leadingAnchor constraintEqualToAnchor:content_view.leadingAnchor constant:InkwellPreferencesSectionLeadingInset],
		[background_label.widthAnchor constraintEqualToConstant:104.0],
		[background_label.centerYAnchor constraintEqualToAnchor:color_stack_view.centerYAnchor],
		[color_stack_view.topAnchor constraintEqualToAnchor:separator_line.bottomAnchor constant:InkwellPreferencesSectionTopSpacing],
		[color_stack_view.leadingAnchor constraintEqualToAnchor:background_label.trailingAnchor constant:12.0],
		[color_stack_view.trailingAnchor constraintLessThanOrEqualToAnchor:content_view.trailingAnchor constant:-18.0],

		[font_label.leadingAnchor constraintEqualToAnchor:background_label.leadingAnchor],
		[font_label.widthAnchor constraintEqualToAnchor:background_label.widthAnchor],
		[font_label.centerYAnchor constraintEqualToAnchor:font_popup_button.centerYAnchor],
		[font_popup_button.topAnchor constraintEqualToAnchor:color_stack_view.bottomAnchor constant:InkwellPreferencesRowSpacing],
		[font_popup_button.leadingAnchor constraintEqualToAnchor:font_label.trailingAnchor constant:12.0],
		[font_popup_button.widthAnchor constraintGreaterThanOrEqualToConstant:InkwellPreferencesPopupMinWidth],
		[font_popup_button.widthAnchor constraintLessThanOrEqualToConstant:InkwellPreferencesPopupMaxWidth],
		[font_popup_button.trailingAnchor constraintLessThanOrEqualToAnchor:content_view.trailingAnchor constant:-18.0],
		[size_label.leadingAnchor constraintEqualToAnchor:background_label.leadingAnchor],
		[size_label.widthAnchor constraintEqualToAnchor:background_label.widthAnchor],
		[size_label.centerYAnchor constraintEqualToAnchor:size_popup_button.centerYAnchor],
		[size_popup_button.topAnchor constraintEqualToAnchor:font_popup_button.bottomAnchor constant:InkwellPreferencesRowSpacing],
		[size_popup_button.leadingAnchor constraintEqualToAnchor:size_label.trailingAnchor constant:12.0],
		[size_popup_button.widthAnchor constraintGreaterThanOrEqualToConstant:InkwellPreferencesPopupMinWidth],
		[size_popup_button.widthAnchor constraintLessThanOrEqualToConstant:InkwellPreferencesPopupMaxWidth],
		[size_popup_button.trailingAnchor constraintLessThanOrEqualToAnchor:content_view.trailingAnchor constant:-18.0],
		[feeds_separator_line.topAnchor constraintEqualToAnchor:size_popup_button.bottomAnchor constant:18.0],
		[feeds_separator_line.leadingAnchor constraintEqualToAnchor:separator_line.leadingAnchor],
		[feeds_separator_line.trailingAnchor constraintEqualToAnchor:separator_line.trailingAnchor],

		[feeds_label.topAnchor constraintEqualToAnchor:feeds_separator_line.bottomAnchor constant:18.0],
		[feeds_label.leadingAnchor constraintEqualToAnchor:feeds_separator_line.leadingAnchor],
		[feeds_label.centerYAnchor constraintEqualToAnchor:feeds_search_field.centerYAnchor],
		[feeds_label.trailingAnchor constraintLessThanOrEqualToAnchor:feeds_search_field.leadingAnchor constant:-12.0],

		[feeds_search_field.trailingAnchor constraintEqualToAnchor:feeds_separator_line.trailingAnchor],
		[feeds_search_field.widthAnchor constraintEqualToConstant:200.0],

		[feeds_view.topAnchor constraintEqualToAnchor:feeds_label.bottomAnchor constant:14.0],
		[feeds_view.leadingAnchor constraintEqualToAnchor:content_view.leadingAnchor constant:18.0],
		[feeds_view.trailingAnchor constraintEqualToAnchor:content_view.trailingAnchor constant:-18.0],
		[feeds_view.bottomAnchor constraintEqualToAnchor:content_view.bottomAnchor constant:-18.0]
	]];

	self.avatarImageView = avatar_image_view;
	self.usernameTextField = username_text_field;
	self.fontPopUpButton = font_popup_button;
	self.sizePopUpButton = size_popup_button;
	self.feedsSearchField = feeds_search_field;
	self.didSetupContent = YES;

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(searchFieldTextDidChange:) name:NSControlTextDidChangeNotification object:feeds_search_field];
}

- (void) reloadFromDefaults
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	NSString* username = [defaults stringForKey:InkwellUsernameDefaultsKey] ?: @"";
	NSString* trimmed_username = [username stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (trimmed_username.length == 0) {
		trimmed_username = @"Signed In";
	}
	self.usernameTextField.stringValue = trimmed_username;

	NSString* avatar_url_string = [defaults stringForKey:InkwellUserAvatarURLDefaultsKey] ?: @"";
	[self applyAvatarImageFromURLString:avatar_url_string];

	NSString* selected_background_hex = [self selectedBackgroundColorHexFromDefaults];
	[defaults setObject:selected_background_hex forKey:InkwellTextBackgroundColorDefaultsKey];

	NSString* selected_font_name = [self selectedFontNameFromDefaults];
	[defaults setObject:selected_font_name forKey:InkwellTextFontNameDefaultsKey];
	[self.fontPopUpButton selectItemWithTitle:selected_font_name];
	NSString* selected_size_name = [self selectedSizeNameFromDefaults];
	[defaults setObject:selected_size_name forKey:InkwellTextSizeNameDefaultsKey];
	[self.sizePopUpButton selectItemWithTitle:selected_size_name];

	[self refreshBackgroundColorSelection];
}

- (void) searchFieldTextDidChange:(NSNotification*) notification
{
	NSSearchField* search_field = notification.object;
	if (![search_field isKindOfClass:[NSSearchField class]] || search_field != self.feedsSearchField) {
		return;
	}

	[self.feedsController updateSearchQuery:(search_field.stringValue ?: @"")];
}

- (void) selectBackgroundColor:(id) sender
{
	if (![sender isKindOfClass:[NSButton class]]) {
		return;
	}

	NSButton* selected_button = (NSButton*) sender;
	NSInteger selected_index = selected_button.tag;
	if (selected_index < 0 || selected_index >= self.backgroundColorHexes.count) {
		return;
	}

	NSString* selected_hex = self.backgroundColorHexes[(NSUInteger) selected_index];
	[[NSUserDefaults standardUserDefaults] setObject:selected_hex forKey:InkwellTextBackgroundColorDefaultsKey];
	[self refreshBackgroundColorSelection];
	[self notifyTextSettingsChanged];
}

- (void) selectFont:(id) sender
{
	#pragma unused(sender)
	NSString* selected_font_name = self.fontPopUpButton.selectedItem.title ?: @"";
	NSString* normalized_font_name = [selected_font_name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (normalized_font_name.length == 0) {
		normalized_font_name = InkwellDefaultTextFontName;
	}

	[[NSUserDefaults standardUserDefaults] setObject:normalized_font_name forKey:InkwellTextFontNameDefaultsKey];
	[self notifyTextSettingsChanged];
}

- (void) selectSize:(id) sender
{
	#pragma unused(sender)
	NSString* selected_size_name = self.sizePopUpButton.selectedItem.title ?: @"";
	NSString* normalized_size_name = [selected_size_name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (normalized_size_name.length == 0) {
		normalized_size_name = InkwellDefaultTextSizeName;
	}

	[[NSUserDefaults standardUserDefaults] setObject:normalized_size_name forKey:InkwellTextSizeNameDefaultsKey];
	[self notifyTextSettingsChanged];
}

- (void) signOut:(id) sender
{
	#pragma unused(sender)
	if (self.signOutHandler != nil) {
		self.signOutHandler();
	}
}

- (void) notifyTextSettingsChanged
{
	if (self.textSettingsChangedHandler != nil) {
		self.textSettingsChangedHandler();
	}
}

- (void) refreshBackgroundColorSelection
{
	NSString* selected_hex = [self selectedBackgroundColorHexFromDefaults];
	for (NSInteger i = 0; i < self.backgroundColorButtons.count; i++) {
		NSButton* button = self.backgroundColorButtons[(NSUInteger) i];
		NSString* button_hex = self.backgroundColorHexes[(NSUInteger) i];
		BOOL is_selected = [button_hex caseInsensitiveCompare:selected_hex] == NSOrderedSame;
		button.layer.borderColor = is_selected ? [NSColor controlAccentColor].CGColor : [NSColor colorWithWhite:0.70 alpha:1.0].CGColor;
		button.layer.borderWidth = is_selected ? 2.0 : 1.0;
	}
}

- (NSString*) selectedBackgroundColorHexFromDefaults
{
	NSString* selected_hex = [[NSUserDefaults standardUserDefaults] stringForKey:InkwellTextBackgroundColorDefaultsKey] ?: @"";
	NSString* normalized_hex = [selected_hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (normalized_hex.length == 0) {
		return InkwellDefaultTextBackgroundHex;
	}

	for (NSString* color_hex in self.backgroundColorHexes) {
		if ([color_hex caseInsensitiveCompare:normalized_hex] == NSOrderedSame) {
			return color_hex;
		}
	}

	return InkwellDefaultTextBackgroundHex;
}

- (NSString*) selectedFontNameFromDefaults
{
	NSString* saved_font_name = [[NSUserDefaults standardUserDefaults] stringForKey:InkwellTextFontNameDefaultsKey] ?: @"";
	NSString* normalized_name = [saved_font_name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (normalized_name.length == 0) {
		return InkwellDefaultTextFontName;
	}

	for (NSString* font_name in self.fontNames) {
		if ([font_name isEqualToString:normalized_name]) {
			return font_name;
		}
	}

	return InkwellDefaultTextFontName;
}

- (NSString*) selectedSizeNameFromDefaults
{
	NSString* saved_size_name = [[NSUserDefaults standardUserDefaults] stringForKey:InkwellTextSizeNameDefaultsKey] ?: @"";
	NSString* normalized_name = [saved_size_name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (normalized_name.length == 0) {
		return InkwellDefaultTextSizeName;
	}

	for (NSString* size_name in self.sizeNames) {
		if ([size_name isEqualToString:normalized_name]) {
			return size_name;
		}
	}

	return InkwellDefaultTextSizeName;
}

- (void) applyAvatarImageFromURLString:(NSString*) avatar_url_string
{
	NSString* trimmed_url_string = [avatar_url_string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (trimmed_url_string.length == 0) {
		self.avatarImageView.image = [self defaultAvatarImage];
		return;
	}

	NSURL* avatar_url = [NSURL URLWithString:trimmed_url_string];
	if (avatar_url == nil) {
		self.avatarImageView.image = [self defaultAvatarImage];
		return;
	}

	self.avatarImageView.image = [self defaultAvatarImage];
	__weak typeof(self) weak_self = self;
	NSURLSessionDataTask* task = [self.avatarSession dataTaskWithURL:avatar_url completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
		#pragma unused(response)
		if (error != nil || data.length == 0) {
			return;
		}

		NSImage* image = [[NSImage alloc] initWithData:data];
		if (image == nil) {
			return;
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			MBPreferencesController* strong_self = weak_self;
			if (strong_self == nil) {
				return;
			}
			strong_self.avatarImageView.image = image;
		});
	}];
	[task resume];
}

- (NSImage*) defaultAvatarImage
{
	NSImage* symbol_image = [NSImage imageWithSystemSymbolName:@"person.crop.circle.fill" accessibilityDescription:@"Avatar"];
	if (symbol_image != nil) {
		return symbol_image;
	}

	NSSize size = NSMakeSize(InkwellPreferencesAvatarSize, InkwellPreferencesAvatarSize);
	NSImage* fallback_image = [[NSImage alloc] initWithSize:size];
	[fallback_image lockFocus];
	[[NSColor colorWithWhite:0.82 alpha:1.0] setFill];
	NSBezierPath* circle_path = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0.0, 0.0, size.width, size.height)];
	[circle_path fill];
	[fallback_image unlockFocus];
	return fallback_image;
}

- (NSColor*) colorFromHexString:(NSString*) hex_string
{
	NSString* normalized_hex = [[hex_string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
	if ([normalized_hex hasPrefix:@"#"]) {
		normalized_hex = [normalized_hex substringFromIndex:1];
	}
	if (normalized_hex.length != 6) {
		return NSColor.whiteColor;
	}

	unsigned int rgb_value = 0;
	NSScanner* scanner = [NSScanner scannerWithString:normalized_hex];
	BOOL did_scan = [scanner scanHexInt:&rgb_value];
	if (!did_scan) {
		return NSColor.whiteColor;
	}

	CGFloat red = ((rgb_value >> 16) & 0xFF) / 255.0;
	CGFloat green = ((rgb_value >> 8) & 0xFF) / 255.0;
	CGFloat blue = (rgb_value & 0xFF) / 255.0;
	return [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:1.0];
}

@end
