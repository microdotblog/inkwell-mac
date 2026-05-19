//
//  MBNewPostController.m
//  Inkwell
//
//  Created by Codex on 5/3/26.
//

#import "MBNewPostController.h"

#import "MBClient.h"
#import "MBPreviewButton.h"

#import <QuartzCore/QuartzCore.h>
#import <WebKit/WebKit.h>

static CGFloat const InkwellNewPostWindowWidth = 600.0;
static CGFloat const InkwellNewPostWindowHeight = 400.0;
static CGFloat const InkwellNewPostStatusHeight = 44.0;
static CGFloat const InkwellNewPostTitleHeight = 44.0;
static NSToolbarItemIdentifier const InkwellNewPostToolbarPreviewIdentifier = @"InkwellNewPostToolbarPreview";
static NSToolbarItemIdentifier const InkwellNewPostToolbarProgressIdentifier = @"InkwellNewPostToolbarProgress";
static NSToolbarItemIdentifier const InkwellNewPostToolbarPostIdentifier = @"InkwellNewPostToolbarPost";
static NSString* const InkwellNewPostMicropubEndpoint = @"https://micro.blog/micropub";
static NSString* const InkwellNewPostPreviewEndpoint = @"https://micro.blog/pages/preview";
static NSString* const InkwellNewPostErrorDomain = @"InkwellNewPostErrorDomain";
static NSString* const InkwellNewPostContentChangedScriptMessageName = @"newPostContentChanged";
static NSString* const InkwellNewPostCharacterCountOverLimitColorName = @"color_chars_remaining";
static NSString* const InkwellNewPostEditorBackgroundColorName = @"color_post_editor_background";
static NSString* const InkwellNewPostPreviewBackgroundColorName = @"color_post_preview_background";
static NSString* const InkwellNewPostWindowAutosaveName = @"PostWindow";
static NSString* const InkwellShowTitleFieldDefaultsKey = @"ShowTitleField";
static BOOL InkwellHasNewPostWindowCascadePoint = NO;
static NSPoint InkwellNewPostWindowCascadePoint = { 0.0, 0.0 };

@interface MBNewPostHostnameHoverView : NSView

@property (nonatomic, copy) void (^hoverChangedHandler)(BOOL isHovering);
@property (nonatomic, copy) void (^clickHandler)(NSView* view, NSEvent* event);
@property (nonatomic, strong) NSTrackingArea* trackingArea;

@end

@implementation MBNewPostHostnameHoverView

- (void) updateTrackingAreas
{
	[super updateTrackingAreas];

	if (self.trackingArea != nil) {
		[self removeTrackingArea:self.trackingArea];
	}

	NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect;
	self.trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect options:options owner:self userInfo:nil];
	[self addTrackingArea:self.trackingArea];
}

- (void) mouseEntered:(NSEvent*) event
{
	#pragma unused(event)

	if (self.hoverChangedHandler != nil) {
		self.hoverChangedHandler(YES);
	}
}

- (void) mouseExited:(NSEvent*) event
{
	#pragma unused(event)

	if (self.hoverChangedHandler != nil) {
		self.hoverChangedHandler(NO);
	}
}

- (NSView *) hitTest:(NSPoint)point
{
	NSView* hit_view = [super hitTest:point];
	return (hit_view == nil) ? nil : self;
}

- (void) mouseDown:(NSEvent *)event
{
	if (self.clickHandler != nil) {
		self.clickHandler(self, event);
		return;
	}

	[super mouseDown:event];
}

@end

@interface MBNewPostEditorBackgroundView : NSView

@property (nonatomic, assign) BOOL usesPreviewBackground;

@end

@implementation MBNewPostEditorBackgroundView

- (BOOL) isOpaque
{
	return YES;
}

- (void) drawRect:(NSRect)dirty_rect
{
	#pragma unused(dirty_rect)

	NSString* color_name = self.usesPreviewBackground ? InkwellNewPostPreviewBackgroundColorName : InkwellNewPostEditorBackgroundColorName;
	NSColor* fallback_color = self.usesPreviewBackground ? NSColor.windowBackgroundColor : NSColor.textBackgroundColor;
	NSColor* background_color = [NSColor colorNamed:color_name] ?: fallback_color;
	[background_color setFill];
	NSRectFill(self.bounds);
}

- (void) setUsesPreviewBackground:(BOOL)uses_preview_background
{
	if (_usesPreviewBackground == uses_preview_background) {
		return;
	}

	_usesPreviewBackground = uses_preview_background;
	self.needsDisplay = YES;
}

- (void) viewDidChangeEffectiveAppearance
{
	[super viewDidChangeEffectiveAppearance];
	self.needsDisplay = YES;
}

@end

@interface MBNewPostSeparatorView : NSView

@end

@implementation MBNewPostSeparatorView

- (BOOL) isOpaque
{
	return NO;
}

- (void) drawRect:(NSRect)dirty_rect
{
	#pragma unused(dirty_rect)

	[NSColor.separatorColor setFill];
	NSRectFill(self.bounds);
}

- (void) viewDidChangeEffectiveAppearance
{
	[super viewDidChangeEffectiveAppearance];
	self.needsDisplay = YES;
}

@end

@interface MBNewPostWeakScriptMessageHandler : NSObject <WKScriptMessageHandler>

@property (nonatomic, weak) id<WKScriptMessageHandler> target;

- (instancetype) initWithTarget:(id<WKScriptMessageHandler>)target;

@end

@implementation MBNewPostWeakScriptMessageHandler

- (instancetype) initWithTarget:(id<WKScriptMessageHandler>)target
{
	self = [super init];
	if (self) {
		self.target = target;
	}
	return self;
}

- (void) userContentController:(WKUserContentController *)user_content_controller didReceiveScriptMessage:(WKScriptMessage *)script_message
{
	[self.target userContentController:user_content_controller didReceiveScriptMessage:script_message];
}

@end

@interface MBNewPostController () <NSTextFieldDelegate, NSToolbarDelegate, NSToolbarItemValidation, NSWindowDelegate, WKNavigationDelegate, WKScriptMessageHandler>

@property (nonatomic, strong, readwrite) NSTextField* blogHostnameField;
@property (nonatomic, strong) NSTextField* characterCountField;
@property (nonatomic, strong) NSTextField* titleField;
@property (nonatomic, strong) NSView* titleSeparatorView;
@property (nonatomic, strong) MBNewPostEditorBackgroundView* editorBackgroundView;
@property (nonatomic, strong) MBNewPostEditorBackgroundView* bottomBackgroundView;
@property (nonatomic, strong) WKWebView* webView;
@property (nonatomic, strong) NSLayoutConstraint* webViewTopConstraint;
@property (nonatomic, strong) NSButton* previewButton;
@property (nonatomic, strong) NSButton* postButton;
@property (nonatomic, strong) NSProgressIndicator* progressIndicator;
@property (nonatomic, strong) NSToolbarItem* progressToolbarItem;
@property (nonatomic, strong) NSToolbarItem* postToolbarItem;
@property (nonatomic, strong) MBNewPostWeakScriptMessageHandler* contentChangedScriptMessageHandler;
@property (nonatomic, strong) id commandReturnEventMonitor;
@property (nonatomic, copy) NSString* markdownText;
@property (nonatomic, copy) NSString* initialMarkdownText;
@property (nonatomic, copy) NSString* currentMarkdownText;
@property (nonatomic, copy) NSString* initialTitleText;
@property (nonatomic, copy) NSString* editingPostURLString;
@property (nonatomic, copy) NSString* destinationName;
@property (nonatomic, copy) NSString* destinationUID;
@property (nonatomic, copy) NSArray* destinations;
@property (nonatomic, copy) NSString* token;
@property (nonatomic, assign) BOOL didLoadEditorHTML;
@property (nonatomic, assign) BOOL isPosting;
@property (nonatomic, assign) BOOL isLoadingEditingPostSource;
@property (nonatomic, assign) BOOL isPreviewing;
@property (nonatomic, assign) BOOL isTitleFieldVisible;
@property (nonatomic, assign) BOOL isContentOverCharacterLimit;
@property (nonatomic, assign) BOOL isApplyingInitialMarkdownText;
@property (nonatomic, assign) BOOL isClosingAfterPost;
@property (nonatomic, assign) BOOL isSettingWindowFrame;
@property (nonatomic, assign) NSInteger editingPostSourceRequestIdentifier;
@property (nonatomic, assign) NSInteger applyMarkdownTextRequestIdentifier;

- (void) loadEditorHTMLIfNeeded;
- (void) applyMarkdownTextToEditor;
- (void) applyMarkdownTextToEditorWithCompletion:(void (^)(void))completionHandler;
- (void) resetPostingState;
- (void) resetPreviewState;
- (void) resetCharacterCount;
- (void) updateDocumentEditedState;
- (void) updateTitleAndCharacterCountVisibilityAnimated:(BOOL)animated;
- (void) setPreviewBackgroundEnabled:(BOOL)is_enabled;
- (BOOL) shouldShowTitleField;
- (BOOL) hasExplicitTitleFieldVisibilityPreference;
- (void) setTitleFieldVisible:(BOOL)is_visible animated:(BOOL)animated;
- (void) installCommandReturnEventMonitor;
- (void) removeCommandReturnEventMonitor;
- (NSEvent *) handleCommandReturnEvent:(NSEvent *)event;
- (BOOL) isEditingExistingPost;
- (NSString *) postToolbarButtonTitle;
- (void) updatePostButtonTitle;
- (void) setPosting:(BOOL) is_posting;
- (void) finishPostingWithError:(NSError * _Nullable)error;
- (void) postContent:(NSString *)content;
- (void) postContent:(NSString *)content asDraft:(BOOL)is_draft;
- (void) updatePostContent:(NSString *)content asDraft:(BOOL)is_draft postURL:(NSString *)postURL;
- (void) saveDraftAndClose;
- (void) fetchEditingPostSource;
- (void) finishEditingPostSourceWithMarkdown:(NSString *)markdown title:(NSString *)title error:(NSError * _Nullable)error;
- (void) showEditingPostSourceErrorAlert:(NSError *)error;
- (NSString *) markdownTextFromMicropubSourcePayload:(id)payload;
- (NSString *) titleTextFromMicropubSourcePayload:(id)payload;
- (NSString *) sourceStringValueFromObject:(id)object;
- (void) postPreviewContent:(NSString *)content completion:(void (^)(NSString* _Nullable html, NSError* _Nullable error))completion;
- (void) showPreviewHTML:(NSString *)html;
- (void) updateCharacterCountWithPayload:(id)payload;
- (void) savePostWindowFrameIfNeeded;
- (void) showDestinationsMenuFromView:(NSView *)view event:(NSEvent *)event;
- (void) selectDestinationFromMenuItem:(NSMenuItem *)menu_item;
- (NSString *) stringValueFromObject:(id)object;
- (NSInteger) integerValueFromObject:(id)object;
- (NSString *) urlEncodedString:(NSString *)string;
- (NSString *) responseDescriptionForData:(NSData *)data defaultMessage:(NSString *)default_message;

@end

@implementation MBNewPostController

+ (void) resetPostWindowCascade
{
	InkwellHasNewPostWindowCascadePoint = NO;
	InkwellNewPostWindowCascadePoint = NSZeroPoint;
}

- (instancetype) init
{
	self = [super initWithWindow:nil];
	if (self) {
		self.markdownText = @"";
		self.initialMarkdownText = @"";
		self.currentMarkdownText = @"";
		self.initialTitleText = @"";
		self.editingPostURLString = @"";
		self.destinationName = @"";
		self.destinationUID = @"";
		self.destinations = @[];
		self.token = @"";
	}
	return self;
}

- (void) dealloc
{
	[self removeCommandReturnEventMonitor];
	[self.webView.configuration.userContentController removeScriptMessageHandlerForName:InkwellNewPostContentChangedScriptMessageName];
}

- (void) showWithMarkdownText:(NSString *)markdownText
{
	[self showWithMarkdownText:markdownText destinationName:@"" destinationUID:@"" token:@""];
}

- (void) showWithMarkdownText:(NSString *)markdownText destinationName:(NSString *)destinationName destinationUID:(NSString *)destinationUID token:(NSString *)token
{
	[self showWithMarkdownText:markdownText destinationName:destinationName destinationUID:destinationUID destinations:@[] token:token];
}

- (void) showWithMarkdownText:(NSString *)markdownText destinationName:(NSString *)destinationName destinationUID:(NSString *)destinationUID destinations:(NSArray *)destinations token:(NSString *)token
{
	[self setupWindowIfNeeded];
	self.editingPostURLString = @"";
	self.isLoadingEditingPostSource = NO;
	[self updatePostButtonTitle];
	self.markdownText = markdownText ?: @"";
	self.initialMarkdownText = self.markdownText;
	self.currentMarkdownText = self.markdownText;
	self.destinationName = destinationName ?: @"";
	self.destinationUID = destinationUID ?: @"";
	self.destinations = destinations ?: @[];
	self.token = token ?: @"";
	self.blogHostnameField.stringValue = self.destinationName;
	[self resetCharacterCount];
	self.initialTitleText = self.titleField.stringValue ?: @"";
	if (self.destinationUID.length > 0) {
		[[NSUserDefaults standardUserDefaults] setObject:self.destinationUID forKey:InkwellCurrentDestinationDefaultsKey];
	}
	[self resetPostingState];
	[self resetPreviewState];
	[self updateDocumentEditedState];
	[self loadEditorHTMLIfNeeded];
	[self showWindow:nil];
	[self.window makeKeyAndOrderFront:nil];
	if (self.didLoadEditorHTML) {
		self.webView.hidden = NO;
		[self.window makeFirstResponder:self.webView];
		[self applyMarkdownTextToEditor];
		[self updateDocumentEditedState];
	}
}

- (void) showEditingPostURL:(NSString *)postURLString destinationName:(NSString *)destinationName destinationUID:(NSString *)destinationUID destinations:(NSArray *)destinations token:(NSString *)token
{
	[self setupWindowIfNeeded];
	self.editingPostURLString = postURLString ?: @"";
	self.isLoadingEditingPostSource = YES;
	[self updatePostButtonTitle];
	self.markdownText = @"";
	self.initialMarkdownText = @"";
	self.currentMarkdownText = @"";
	self.destinationName = destinationName ?: @"";
	self.destinationUID = destinationUID ?: @"";
	self.destinations = destinations ?: @[];
	self.token = token ?: @"";
	self.blogHostnameField.stringValue = self.destinationName;
	[self resetCharacterCount];
	self.initialTitleText = self.titleField.stringValue ?: @"";
	if (self.destinationUID.length > 0) {
		[[NSUserDefaults standardUserDefaults] setObject:self.destinationUID forKey:InkwellCurrentDestinationDefaultsKey];
	}
	[self resetPostingState];
	[self resetPreviewState];
	[self updateDocumentEditedState];
	[self loadEditorHTMLIfNeeded];
	[self showWindow:nil];
	[self.window makeKeyAndOrderFront:nil];
	[self fetchEditingPostSource];
}

- (IBAction) post:(id) sender
{
	#pragma unused(sender)

	if (self.isPosting) {
		return;
	}

	__weak typeof(self) weak_self = self;
	[self.webView evaluateJavaScript:@"window.InkwellNewPostEditor ? window.InkwellNewPostEditor.markdown() : ''" completionHandler:^(id _Nullable result, NSError* _Nullable error) {
		MBNewPostController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		if (error != nil) {
			[strong_self finishPostingWithError:error];
			return;
		}

		NSString* content = [result isKindOfClass:[NSString class]] ? (NSString*) result : @"";
		NSString* trimmed_content = [content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		if (trimmed_content.length == 0) {
			return;
		}

		[strong_self setPosting:YES];
		[strong_self postContent:content asDraft:NO];
	}];
}

- (IBAction) preview:(id) sender
{
	#pragma unused(sender)

	if (self.isPreviewing) {
		self.isPreviewing = NO;
		self.previewButton.state = NSControlStateValueOff;
		[self setPreviewBackgroundEnabled:NO];
		[self.webView evaluateJavaScript:@"window.InkwellNewPostEditor && window.InkwellNewPostEditor.togglePreview('');" completionHandler:nil];
		return;
	}

	self.isPreviewing = YES;
	self.previewButton.state = NSControlStateValueOn;
	self.previewButton.enabled = NO;
	__weak typeof(self) weak_self = self;
	[self.webView evaluateJavaScript:@"window.InkwellNewPostEditor ? window.InkwellNewPostEditor.markdown() : ''" completionHandler:^(id _Nullable result, NSError* _Nullable error) {
		MBNewPostController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		if (error != nil) {
			strong_self.isPreviewing = NO;
			strong_self.previewButton.state = NSControlStateValueOff;
			strong_self.previewButton.enabled = YES;
			[strong_self setPreviewBackgroundEnabled:NO];
			[strong_self.webView evaluateJavaScript:@"window.InkwellNewPostEditor && window.InkwellNewPostEditor.setPreviewBackground(false);" completionHandler:nil];
			NSBeep();
			return;
		}

		NSString* content = [result isKindOfClass:[NSString class]] ? (NSString*) result : @"";
		[strong_self postPreviewContent:content completion:^(NSString* _Nullable html, NSError* _Nullable preview_error) {
			strong_self.previewButton.enabled = YES;
			if (preview_error != nil) {
				strong_self.isPreviewing = NO;
				strong_self.previewButton.state = NSControlStateValueOff;
				[strong_self setPreviewBackgroundEnabled:NO];
				[strong_self.webView evaluateJavaScript:@"window.InkwellNewPostEditor && window.InkwellNewPostEditor.setPreviewBackground(false);" completionHandler:nil];
				NSBeep();
				return;
			}

			[strong_self showPreviewHTML:(html ?: @"")];
		}];
	}];
}

- (BOOL) isPreviewEnabled
{
	return self.isPreviewing;
}

- (IBAction) toggleTitleField:(id) sender
{
	#pragma unused(sender)

	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	BOOL should_show_title = ![defaults boolForKey:InkwellShowTitleFieldDefaultsKey];
	[defaults setBool:should_show_title forKey:InkwellShowTitleFieldDefaultsKey];
	[self updateTitleAndCharacterCountVisibilityAnimated:YES];

	if (should_show_title) {
		[self.window makeFirstResponder:self.titleField];
	}
	else if (self.window.firstResponder == self.titleField.currentEditor) {
		[self.window makeFirstResponder:self.webView];
	}
}

- (void) setupWindowIfNeeded
{
	if (self.window != nil) {
		return;
	}

	NSRect content_rect = NSMakeRect(0.0, 0.0, InkwellNewPostWindowWidth, InkwellNewPostWindowHeight);
	NSWindow* post_window = [[NSWindow alloc] initWithContentRect:content_rect styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable) backing:NSBackingStoreBuffered defer:NO];
	post_window.releasedWhenClosed = NO;
	post_window.delegate = self;
	post_window.title = @"New Post";
	post_window.titleVisibility = NSWindowTitleHidden;
	post_window.backgroundColor = [NSColor colorNamed:InkwellNewPostEditorBackgroundColorName] ?: NSColor.windowBackgroundColor;
	post_window.minSize = NSMakeSize(420.0, 280.0);
	post_window.toolbarStyle = NSWindowToolbarStyleUnified;

	NSToolbar* toolbar = [[NSToolbar alloc] initWithIdentifier:@"InkwellNewPostToolbar"];
	toolbar.delegate = self;
	toolbar.allowsUserCustomization = NO;
	toolbar.autosavesConfiguration = NO;
	toolbar.displayMode = NSToolbarDisplayModeIconOnly;
	post_window.toolbar = toolbar;

	MBNewPostEditorBackgroundView* content_view = [[MBNewPostEditorBackgroundView alloc] initWithFrame:content_rect];
	content_view.translatesAutoresizingMaskIntoConstraints = NO;

	WKWebViewConfiguration* configuration = [[WKWebViewConfiguration alloc] init];
	WKUserContentController* user_content_controller = [[WKUserContentController alloc] init];
	self.contentChangedScriptMessageHandler = [[MBNewPostWeakScriptMessageHandler alloc] initWithTarget:self];
	[user_content_controller addScriptMessageHandler:self.contentChangedScriptMessageHandler name:InkwellNewPostContentChangedScriptMessageName];
	configuration.userContentController = user_content_controller;
	WKWebView* web_view = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
	web_view.translatesAutoresizingMaskIntoConstraints = NO;
	web_view.navigationDelegate = self;
	web_view.hidden = YES;
	NSColor* web_view_background_color = [self postBackgroundColorForPreviewEnabled:NO];
	web_view.underPageBackgroundColor = web_view_background_color;

	MBNewPostEditorBackgroundView* bottom_view = [[MBNewPostEditorBackgroundView alloc] initWithFrame:NSZeroRect];
	bottom_view.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField* title_field = [[NSTextField alloc] initWithFrame:NSZeroRect];
	title_field.translatesAutoresizingMaskIntoConstraints = NO;
	title_field.placeholderString = @"Title";
	title_field.font = [NSFont boldSystemFontOfSize:18.0];
	title_field.textColor = NSColor.labelColor;
	title_field.bordered = NO;
	title_field.bezeled = NO;
	title_field.drawsBackground = NO;
	title_field.focusRingType = NSFocusRingTypeNone;
	title_field.delegate = self;
	title_field.hidden = YES;
	title_field.alphaValue = 0.0;

	MBNewPostSeparatorView* title_separator_view = [[MBNewPostSeparatorView alloc] initWithFrame:NSZeroRect];
	title_separator_view.translatesAutoresizingMaskIntoConstraints = NO;
	title_separator_view.hidden = YES;
	title_separator_view.alphaValue = 0.0;

	MBNewPostHostnameHoverView* hostname_hover_view = [[MBNewPostHostnameHoverView alloc] initWithFrame:NSZeroRect];
	hostname_hover_view.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField* blog_hostname_field = [NSTextField labelWithString:@""];
	blog_hostname_field.translatesAutoresizingMaskIntoConstraints = NO;
	blog_hostname_field.textColor = NSColor.secondaryLabelColor;
	blog_hostname_field.font = [NSFont systemFontOfSize:NSFont.systemFontSize];
	blog_hostname_field.alignment = NSTextAlignmentCenter;

	NSTextField* character_count_field = [NSTextField labelWithString:@"0/300"];
	character_count_field.translatesAutoresizingMaskIntoConstraints = NO;
	character_count_field.textColor = NSColor.secondaryLabelColor;
	character_count_field.font = [NSFont systemFontOfSize:NSFont.systemFontSize weight:NSFontWeightThin];
	character_count_field.alignment = NSTextAlignmentRight;
	[character_count_field setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
	[character_count_field setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

	NSImageView* blog_hostname_chevron_view = [[NSImageView alloc] initWithFrame:NSZeroRect];
	blog_hostname_chevron_view.translatesAutoresizingMaskIntoConstraints = NO;
	NSImage* chevron_image = [NSImage imageWithSystemSymbolName:@"chevron.down" accessibilityDescription:@"Show blogs"];
	NSImageSymbolConfiguration* chevron_configuration = [NSImageSymbolConfiguration configurationWithPointSize:10.0 weight:NSFontWeightSemibold];
	blog_hostname_chevron_view.image = [chevron_image imageWithSymbolConfiguration:chevron_configuration] ?: chevron_image;
	blog_hostname_chevron_view.contentTintColor = NSColor.secondaryLabelColor;
	blog_hostname_chevron_view.imageScaling = NSImageScaleProportionallyDown;
	blog_hostname_chevron_view.hidden = YES;

	__weak NSImageView* weak_chevron_view = blog_hostname_chevron_view;
	__weak typeof(self) weak_self = self;
	hostname_hover_view.hoverChangedHandler = ^(BOOL isHovering) {
		MBNewPostController* strong_self = weak_self;
		if (strong_self != nil && [strong_self isEditingExistingPost]) {
			weak_chevron_view.hidden = YES;
			return;
		}

		weak_chevron_view.hidden = !isHovering;
	};
	hostname_hover_view.clickHandler = ^(NSView* view, NSEvent* event) {
		MBNewPostController* strong_self = weak_self;
		if (strong_self != nil && [strong_self isEditingExistingPost]) {
			return;
		}

		[weak_self showDestinationsMenuFromView:view event:event];
	};

	NSLayoutConstraint* web_view_top_constraint = [web_view.topAnchor constraintEqualToAnchor:content_view.topAnchor];

	[content_view addSubview:title_field];
	[content_view addSubview:title_separator_view];
	[content_view addSubview:web_view];
	[content_view addSubview:bottom_view];
	[bottom_view addSubview:hostname_hover_view];
	[bottom_view addSubview:character_count_field];
	[hostname_hover_view addSubview:blog_hostname_field];
	[hostname_hover_view addSubview:blog_hostname_chevron_view];

	[NSLayoutConstraint activateConstraints:@[
		web_view_top_constraint,
		[title_field.topAnchor constraintEqualToAnchor:content_view.topAnchor constant:11.0],
		[title_field.leadingAnchor constraintEqualToAnchor:content_view.leadingAnchor constant:18.0],
		[title_field.trailingAnchor constraintEqualToAnchor:content_view.trailingAnchor constant:-18.0],
		[title_field.heightAnchor constraintEqualToConstant:24.0],
		[title_separator_view.leadingAnchor constraintEqualToAnchor:content_view.leadingAnchor],
		[title_separator_view.trailingAnchor constraintEqualToAnchor:content_view.trailingAnchor],
		[title_separator_view.topAnchor constraintEqualToAnchor:content_view.topAnchor constant:(InkwellNewPostTitleHeight - 1.0)],
		[title_separator_view.heightAnchor constraintEqualToConstant:1.0],
		[web_view.leadingAnchor constraintEqualToAnchor:content_view.leadingAnchor],
		[web_view.trailingAnchor constraintEqualToAnchor:content_view.trailingAnchor],
		[web_view.bottomAnchor constraintEqualToAnchor:bottom_view.topAnchor],
		[bottom_view.leadingAnchor constraintEqualToAnchor:content_view.leadingAnchor],
		[bottom_view.trailingAnchor constraintEqualToAnchor:content_view.trailingAnchor],
		[bottom_view.bottomAnchor constraintEqualToAnchor:content_view.bottomAnchor],
		[bottom_view.heightAnchor constraintEqualToConstant:InkwellNewPostStatusHeight],
		[hostname_hover_view.leadingAnchor constraintGreaterThanOrEqualToAnchor:bottom_view.leadingAnchor constant:20.0],
		[hostname_hover_view.trailingAnchor constraintLessThanOrEqualToAnchor:character_count_field.leadingAnchor constant:-16.0],
		[hostname_hover_view.centerXAnchor constraintEqualToAnchor:bottom_view.centerXAnchor],
		[hostname_hover_view.centerYAnchor constraintEqualToAnchor:bottom_view.centerYAnchor],
		[character_count_field.trailingAnchor constraintEqualToAnchor:bottom_view.trailingAnchor constant:-19.0],
		[character_count_field.centerYAnchor constraintEqualToAnchor:bottom_view.centerYAnchor],
		[character_count_field.widthAnchor constraintEqualToConstant:76.0],
		[blog_hostname_field.topAnchor constraintEqualToAnchor:hostname_hover_view.topAnchor],
		[blog_hostname_field.leadingAnchor constraintEqualToAnchor:hostname_hover_view.leadingAnchor],
		[blog_hostname_field.bottomAnchor constraintEqualToAnchor:hostname_hover_view.bottomAnchor],
		[blog_hostname_chevron_view.leadingAnchor constraintEqualToAnchor:blog_hostname_field.trailingAnchor constant:2.0],
		[blog_hostname_chevron_view.trailingAnchor constraintEqualToAnchor:hostname_hover_view.trailingAnchor],
		[blog_hostname_chevron_view.centerYAnchor constraintEqualToAnchor:blog_hostname_field.centerYAnchor constant:1.0],
		[blog_hostname_chevron_view.widthAnchor constraintEqualToConstant:10.0],
		[blog_hostname_chevron_view.heightAnchor constraintEqualToConstant:10.0]
	]];

	post_window.contentView = content_view;
	self.isSettingWindowFrame = YES;
	BOOL did_restore_frame = [post_window setFrameUsingName:InkwellNewPostWindowAutosaveName];
	if (!did_restore_frame) {
		[post_window center];
	}
	if (!InkwellHasNewPostWindowCascadePoint) {
		NSRect window_frame = post_window.frame;
		InkwellNewPostWindowCascadePoint = NSMakePoint(NSMinX(window_frame), NSMaxY(window_frame));
		InkwellHasNewPostWindowCascadePoint = YES;
	}
	InkwellNewPostWindowCascadePoint = [post_window cascadeTopLeftFromPoint:InkwellNewPostWindowCascadePoint];
	self.isSettingWindowFrame = NO;

	self.window = post_window;
	self.editorBackgroundView = content_view;
	self.bottomBackgroundView = bottom_view;
	self.webView = web_view;
	self.webViewTopConstraint = web_view_top_constraint;
	self.titleField = title_field;
	self.titleSeparatorView = title_separator_view;
	self.blogHostnameField = blog_hostname_field;
	self.characterCountField = character_count_field;

	[self installCommandReturnEventMonitor];
}

- (void) loadEditorHTMLIfNeeded
{
	if (self.didLoadEditorHTML) {
		return;
	}

	NSURL* editor_url = [[NSBundle mainBundle] URLForResource:@"new_post_editor" withExtension:@"html" subdirectory:@"NewPost"];
	if (editor_url == nil) {
		editor_url = [[NSBundle mainBundle] URLForResource:@"new_post_editor" withExtension:@"html"];
	}
	if (editor_url == nil) {
		return;
	}

	NSURL* directory_url = [editor_url URLByDeletingLastPathComponent];
	self.webView.hidden = YES;
	[self.webView loadFileURL:editor_url allowingReadAccessToURL:directory_url];
}

- (void) applyMarkdownTextToEditor
{
	[self applyMarkdownTextToEditorWithCompletion:nil];
}

- (void) applyMarkdownTextToEditorWithCompletion:(void (^)(void))completionHandler
{
	if (![NSThread isMainThread]) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self applyMarkdownTextToEditorWithCompletion:completionHandler];
		});
		return;
	}

	if (!self.didLoadEditorHTML) {
		if (completionHandler != nil) {
			completionHandler();
		}
		return;
	}

	NSString* text = self.markdownText ?: @"";
	self.applyMarkdownTextRequestIdentifier += 1;
	NSInteger apply_request_id = self.applyMarkdownTextRequestIdentifier;
	self.isApplyingInitialMarkdownText = YES;
	NSDictionary* payload = @{ @"text": text };
	NSError* error = nil;
	NSData* json_data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&error];
	if (json_data == nil || error != nil) {
		self.isApplyingInitialMarkdownText = NO;
		if (completionHandler != nil) {
			completionHandler();
		}
		return;
	}

	NSString* json_string = [[NSString alloc] initWithData:json_data encoding:NSUTF8StringEncoding];
	if (json_string.length == 0) {
		self.isApplyingInitialMarkdownText = NO;
		if (completionHandler != nil) {
			completionHandler();
		}
		return;
	}

	NSString* script = [NSString stringWithFormat:@"window.InkwellNewPostEditor && window.InkwellNewPostEditor.setText(%@.text);", json_string];
	__weak typeof(self) weak_self = self;
	__block BOOL did_complete = NO;
	void (^complete_once)(void) = ^{
		MBNewPostController* strong_self = weak_self;
		if (strong_self != nil && strong_self.applyMarkdownTextRequestIdentifier != apply_request_id) {
			return;
		}

		if (did_complete) {
			return;
		}

		did_complete = YES;
		if (completionHandler != nil) {
			completionHandler();
		}
	};

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		MBNewPostController* strong_self = weak_self;
		if (strong_self == nil || did_complete || strong_self.applyMarkdownTextRequestIdentifier != apply_request_id) {
			return;
		}

		strong_self.isApplyingInitialMarkdownText = NO;
		strong_self.initialMarkdownText = strong_self.currentMarkdownText ?: @"";
		[strong_self updateDocumentEditedState];
		complete_once();
	});

	[self.webView evaluateJavaScript:script completionHandler:^(id _Nullable result, NSError* _Nullable error) {
		#pragma unused(result)
		#pragma unused(error)

		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			MBNewPostController* strong_self = weak_self;
			if (strong_self == nil || strong_self.applyMarkdownTextRequestIdentifier != apply_request_id || !strong_self.isApplyingInitialMarkdownText) {
				return;
			}

			strong_self.isApplyingInitialMarkdownText = NO;
			strong_self.initialMarkdownText = strong_self.currentMarkdownText ?: @"";
			[strong_self updateDocumentEditedState];
		});
		complete_once();
	}];
}

- (void) resetPostingState
{
	self.isPosting = NO;
	self.postButton.enabled = YES;
	[self.progressIndicator stopAnimation:nil];
	self.progressIndicator.hidden = YES;
	self.progressToolbarItem.hidden = YES;
}

- (void) resetPreviewState
{
	self.isPreviewing = NO;
	self.previewButton.state = NSControlStateValueOff;
	[self setPreviewBackgroundEnabled:NO];
	[self.webView evaluateJavaScript:@"window.InkwellNewPostEditor && window.InkwellNewPostEditor.setPreviewBackground(false);" completionHandler:nil];
}

- (void) setPreviewBackgroundEnabled:(BOOL)is_enabled
{
	self.editorBackgroundView.usesPreviewBackground = is_enabled;
	self.bottomBackgroundView.usesPreviewBackground = is_enabled;
	NSColor* background_color = [self postBackgroundColorForPreviewEnabled:is_enabled];
	self.window.backgroundColor = background_color;
	self.webView.underPageBackgroundColor = background_color;
}

- (NSColor*) postBackgroundColorForPreviewEnabled:(BOOL)previewEnabled
{
	NSString* color_name = previewEnabled ? InkwellNewPostPreviewBackgroundColorName : InkwellNewPostEditorBackgroundColorName;
	return [NSColor colorNamed:color_name] ?: NSColor.windowBackgroundColor;
}

- (void) resetCharacterCount
{
	self.isContentOverCharacterLimit = NO;
	self.characterCountField.stringValue = @"0/300";
	self.characterCountField.textColor = NSColor.secondaryLabelColor;
	self.characterCountField.hidden = NO;
	self.titleField.stringValue = @"";
	[self updateTitleAndCharacterCountVisibilityAnimated:NO];
}

- (void) updateTitleAndCharacterCountVisibilityAnimated:(BOOL)animated
{
	NSString* title = [self.titleField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	BOOL has_title = (title.length > 0);
	self.characterCountField.hidden = has_title;
	[self setTitleFieldVisible:[self shouldShowTitleField] animated:animated];
}

- (BOOL) shouldShowTitleField
{
	if ([self hasExplicitTitleFieldVisibilityPreference]) {
		return [[NSUserDefaults standardUserDefaults] boolForKey:InkwellShowTitleFieldDefaultsKey];
	}

	NSString* title = [self.titleField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	return (self.isContentOverCharacterLimit || title.length > 0);
}

- (BOOL) hasExplicitTitleFieldVisibilityPreference
{
	return ([[NSUserDefaults standardUserDefaults] objectForKey:InkwellShowTitleFieldDefaultsKey] != nil);
}

- (void) setTitleFieldVisible:(BOOL)is_visible animated:(BOOL)animated
{
	if (self.titleField == nil || self.webViewTopConstraint == nil) {
		return;
	}

	if (self.isTitleFieldVisible == is_visible) {
		return;
	}

	self.isTitleFieldVisible = is_visible;
	CGFloat top_constant = is_visible ? InkwellNewPostTitleHeight : 0.0;

	NSView* content_view = self.window.contentView;
	if (is_visible) {
		self.titleField.hidden = NO;
		self.titleSeparatorView.hidden = NO;
	}

	if (!animated || content_view == nil) {
		self.titleField.alphaValue = is_visible ? 1.0 : 0.0;
		self.titleSeparatorView.alphaValue = is_visible ? 1.0 : 0.0;
		self.titleField.hidden = !is_visible;
		self.titleSeparatorView.hidden = !is_visible;
		self.webViewTopConstraint.constant = top_constant;
		[content_view layoutSubtreeIfNeeded];
		return;
	}

	[content_view layoutSubtreeIfNeeded];
	[NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
		context.duration = 0.18;
		context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
		self.titleField.animator.alphaValue = is_visible ? 1.0 : 0.0;
		self.titleSeparatorView.animator.alphaValue = is_visible ? 1.0 : 0.0;
		self.webViewTopConstraint.animator.constant = top_constant;
		[content_view.animator layoutSubtreeIfNeeded];
	} completionHandler:^{
		self.titleField.hidden = !is_visible;
		self.titleSeparatorView.hidden = !is_visible;
	}];
}

- (void) installCommandReturnEventMonitor
{
	if (self.commandReturnEventMonitor != nil) {
		return;
	}

	__weak typeof(self) weak_self = self;
	self.commandReturnEventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent* _Nullable(NSEvent* event) {
		MBNewPostController* strong_self = weak_self;
		if (strong_self == nil) {
			return event;
		}

		return [strong_self handleCommandReturnEvent:event];
	}];
}

- (void) removeCommandReturnEventMonitor
{
	if (self.commandReturnEventMonitor == nil) {
		return;
	}

	[NSEvent removeMonitor:self.commandReturnEventMonitor];
	self.commandReturnEventMonitor = nil;
}

- (NSEvent *) handleCommandReturnEvent:(NSEvent *)event
{
	if (event.window != self.window) {
		return event;
	}

	BOOL is_return_key = (event.keyCode == 36 || event.keyCode == 76);
	if (!is_return_key) {
		return event;
	}

	NSEventModifierFlags flags = (event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask);
	if ((flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption)) == 0) {
		if ((self.window.firstResponder == self.titleField) || (self.window.firstResponder == self.titleField.currentEditor)) {
			return event;
		}

		[self.webView evaluateJavaScript:@"window.InkwellNewPostEditor && window.InkwellNewPostEditor.insertLineBreak();" completionHandler:nil];
		return nil;
	}

	if ((flags & NSEventModifierFlagCommand) == 0) {
		return event;
	}
	if ((flags & (NSEventModifierFlagControl | NSEventModifierFlagOption)) != 0) {
		return event;
	}

	if (self.postButton.enabled) {
		[self.postButton performClick:nil];
	}

	return nil;
}

- (BOOL) isEditingExistingPost
{
	NSString* post_url = [self.editingPostURLString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	return (post_url.length > 0);
}

- (NSString *) postToolbarButtonTitle
{
	return [self isEditingExistingPost] ? @"Update" : @"Post";
}

- (void) updatePostButtonTitle
{
	NSString* button_title = [self postToolbarButtonTitle];
	self.postToolbarItem.label = button_title;
	self.postToolbarItem.paletteLabel = button_title;
	self.postToolbarItem.toolTip = button_title;
	self.postButton.title = button_title;
	[self.postButton sizeToFit];
}

- (void) setPosting:(BOOL) is_posting
{
	self.isPosting = is_posting;
	self.postButton.enabled = !is_posting;
	self.progressIndicator.hidden = !is_posting;
	self.progressToolbarItem.hidden = !is_posting;
	if (is_posting) {
		[self.progressIndicator startAnimation:nil];
	}
	else {
		[self.progressIndicator stopAnimation:nil];
	}
}

- (void) finishPostingWithError:(NSError *)error
{
	if (error == nil) {
		[self setPosting:NO];
		self.isClosingAfterPost = YES;
		self.window.documentEdited = NO;
		[self close];
		return;
	}

	[self setPosting:NO];
	NSBeep();
}

- (void) postContent:(NSString *)content
{
	[self postContent:content asDraft:NO];
}

- (void) postContent:(NSString *)content asDraft:(BOOL)is_draft
{
	if (self.token.length == 0) {
		NSError* error = [NSError errorWithDomain:InkwellNewPostErrorDomain code:1001 userInfo:@{ NSLocalizedDescriptionKey: @"Missing token for posting." }];
		[self finishPostingWithError:error];
		return;
	}

	NSURL* request_url = [NSURL URLWithString:InkwellNewPostMicropubEndpoint];
	if (request_url == nil) {
		NSError* error = [NSError errorWithDomain:InkwellNewPostErrorDomain code:1002 userInfo:@{ NSLocalizedDescriptionKey: @"Micropub endpoint URL was invalid." }];
		[self finishPostingWithError:error];
		return;
	}

	NSString* editing_post_url = [self.editingPostURLString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (editing_post_url.length > 0) {
		[self updatePostContent:content asDraft:is_draft postURL:editing_post_url];
		return;
	}

	NSMutableArray* body_parts = [NSMutableArray array];
	[body_parts addObject:[NSString stringWithFormat:@"content=%@", [self urlEncodedString:(content ?: @"")]]];
	[body_parts addObject:[NSString stringWithFormat:@"mp-destination=%@", [self urlEncodedString:(self.destinationUID ?: @"")]]];
	if (is_draft) {
		[body_parts addObject:@"post-status=draft"];
	}
	NSString* title = [self.titleField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (title.length > 0) {
		[body_parts addObject:[NSString stringWithFormat:@"name=%@", [self urlEncodedString:title]]];
	}
	NSString* body_string = [body_parts componentsJoinedByString:@"&"] ?: @"";

	NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:request_url];
	request.HTTPMethod = @"POST";
	request.HTTPBody = [body_string dataUsingEncoding:NSUTF8StringEncoding];
	[request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
	[request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
	[request setValue:[NSString stringWithFormat:@"Bearer %@", self.token] forHTTPHeaderField:@"Authorization"];

	NSURLSessionDataTask* task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
		NSError* result_error = error;
		if (result_error == nil) {
			NSHTTPURLResponse* http_response = (NSHTTPURLResponse*) response;
			if (http_response.statusCode < 200 || http_response.statusCode >= 300) {
				NSString* description = [self responseDescriptionForData:data defaultMessage:@"Posting failed."];
				result_error = [NSError errorWithDomain:InkwellNewPostErrorDomain code:http_response.statusCode userInfo:@{ NSLocalizedDescriptionKey: description }];
			}
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			[self finishPostingWithError:result_error];
		});
	}];
	[task resume];
}

- (void) updatePostContent:(NSString *)content asDraft:(BOOL)is_draft postURL:(NSString *)postURL
{
	NSURL* request_url = [NSURL URLWithString:InkwellNewPostMicropubEndpoint];
	if (request_url == nil) {
		NSError* error = [NSError errorWithDomain:InkwellNewPostErrorDomain code:1010 userInfo:@{ NSLocalizedDescriptionKey: @"Micropub endpoint URL was invalid." }];
		[self finishPostingWithError:error];
		return;
	}

	NSMutableDictionary* replace = [NSMutableDictionary dictionary];
	replace[@"content"] = @[ content ?: @"" ];

	NSString* title = [self.titleField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	NSString* initial_title = self.initialTitleText ?: @"";
	if (title.length > 0 || initial_title.length > 0) {
		replace[@"name"] = @[ title ];
	}
	if (is_draft) {
		replace[@"post-status"] = @[ @"draft" ];
	}

	NSMutableDictionary* payload = [@{
		@"action": @"update",
		@"url": postURL ?: @"",
		@"replace": replace
	} mutableCopy];
	NSString* destination_uid = [self.destinationUID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (destination_uid.length > 0) {
		payload[@"mp-destination"] = destination_uid;
	}

	NSError* json_error = nil;
	NSData* json_data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&json_error];
	if (json_data == nil || json_error != nil) {
		NSError* error = json_error ?: [NSError errorWithDomain:InkwellNewPostErrorDomain code:1011 userInfo:@{ NSLocalizedDescriptionKey: @"Could not encode update request." }];
		[self finishPostingWithError:error];
		return;
	}

	NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:request_url];
	request.HTTPMethod = @"POST";
	request.HTTPBody = json_data;
	[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	[request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
	[request setValue:[NSString stringWithFormat:@"Bearer %@", self.token] forHTTPHeaderField:@"Authorization"];

	NSURLSessionDataTask* task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
		NSError* result_error = error;
		if (result_error == nil) {
			NSHTTPURLResponse* http_response = (NSHTTPURLResponse*) response;
			if (http_response.statusCode < 200 || http_response.statusCode >= 300) {
				NSString* description = [self responseDescriptionForData:data defaultMessage:@"Updating failed."];
				result_error = [NSError errorWithDomain:InkwellNewPostErrorDomain code:http_response.statusCode userInfo:@{ NSLocalizedDescriptionKey: description }];
			}
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			[self finishPostingWithError:result_error];
		});
	}];
	[task resume];
}

- (void) saveDraftAndClose
{
	if (self.isPosting) {
		return;
	}

	__weak typeof(self) weak_self = self;
	[self.webView evaluateJavaScript:@"window.InkwellNewPostEditor ? window.InkwellNewPostEditor.markdown() : ''" completionHandler:^(id _Nullable result, NSError* _Nullable error) {
		MBNewPostController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		if (error != nil) {
			[strong_self finishPostingWithError:error];
			return;
		}

		NSString* content = [result isKindOfClass:[NSString class]] ? (NSString*) result : @"";
		[strong_self setPosting:YES];
		[strong_self postContent:content asDraft:YES];
	}];
}

- (void) fetchEditingPostSource
{
	if (![NSThread isMainThread]) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self fetchEditingPostSource];
		});
		return;
	}

	[self setPosting:YES];
	self.editingPostSourceRequestIdentifier += 1;
	NSInteger request_id = self.editingPostSourceRequestIdentifier;

	if (self.token.length == 0) {
		NSError* error = [NSError errorWithDomain:InkwellNewPostErrorDomain code:1006 userInfo:@{ NSLocalizedDescriptionKey: @"Missing token for source request." }];
		[self finishEditingPostSourceWithMarkdown:@"" title:@"" error:error];
		return;
	}

	NSString* post_url = [self.editingPostURLString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (post_url.length == 0) {
		NSError* error = [NSError errorWithDomain:InkwellNewPostErrorDomain code:1007 userInfo:@{ NSLocalizedDescriptionKey: @"Missing post URL for source request." }];
		[self finishEditingPostSourceWithMarkdown:@"" title:@"" error:error];
		return;
	}

	NSMutableArray* query_items = [NSMutableArray arrayWithArray:@[
		[NSURLQueryItem queryItemWithName:@"q" value:@"source"],
		[NSURLQueryItem queryItemWithName:@"url" value:post_url]
	]];
	NSString* destination_uid = [self.destinationUID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (destination_uid.length > 0) {
		[query_items addObject:[NSURLQueryItem queryItemWithName:@"mp-destination" value:destination_uid]];
	}

	NSURLComponents* components = [NSURLComponents componentsWithString:InkwellNewPostMicropubEndpoint];
	components.queryItems = query_items;
	NSURL* request_url = components.URL;
	if (request_url == nil) {
		NSError* error = [NSError errorWithDomain:InkwellNewPostErrorDomain code:1008 userInfo:@{ NSLocalizedDescriptionKey: @"Micropub source endpoint URL was invalid." }];
		[self finishEditingPostSourceWithMarkdown:@"" title:@"" error:error];
		return;
	}

	NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:request_url];
	request.HTTPMethod = @"GET";
	[request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
	[request setValue:[NSString stringWithFormat:@"Bearer %@", self.token] forHTTPHeaderField:@"Authorization"];

	__weak typeof(self) weak_self = self;
	NSURLSessionDataTask* task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
		MBNewPostController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		NSError* result_error = error;
		NSString* markdown = @"";
		NSString* title = @"";
		NSHTTPURLResponse* http_response = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse*) response : nil;
		NSInteger status_code = http_response.statusCode;

		if (result_error == nil) {
			if (status_code < 200 || status_code >= 300) {
				NSString* description = [strong_self responseDescriptionForData:data defaultMessage:@"Source request failed."];
				result_error = [NSError errorWithDomain:InkwellNewPostErrorDomain code:status_code userInfo:@{ NSLocalizedDescriptionKey: description }];
			}
		}

		if (result_error == nil) {
			id payload = [NSJSONSerialization JSONObjectWithData:(data ?: [NSData data]) options:0 error:nil];
			if (![payload isKindOfClass:[NSDictionary class]]) {
				result_error = [NSError errorWithDomain:InkwellNewPostErrorDomain code:1009 userInfo:@{ NSLocalizedDescriptionKey: @"Source response was invalid." }];
			}
			else {
				markdown = [strong_self markdownTextFromMicropubSourcePayload:payload] ?: @"";
				title = [strong_self titleTextFromMicropubSourcePayload:payload] ?: @"";
			}
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			MBNewPostController* main_self = weak_self;
			if (main_self == nil) {
				return;
			}
			if (main_self.editingPostSourceRequestIdentifier != request_id) {
				return;
			}

			[main_self finishEditingPostSourceWithMarkdown:markdown title:title error:result_error];
		});
	}];
	[task resume];
}

- (void) finishEditingPostSourceWithMarkdown:(NSString *)markdown title:(NSString *)title error:(NSError *)error
{
	if (![NSThread isMainThread]) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self finishEditingPostSourceWithMarkdown:markdown title:title error:error];
		});
		return;
	}

	self.isLoadingEditingPostSource = NO;
	[self setPosting:NO];

	if (error != nil) {
		if (self.didLoadEditorHTML) {
			self.webView.hidden = NO;
			[self.window makeFirstResponder:self.webView];
		}
		[self showEditingPostSourceErrorAlert:error];
		return;
	}

	self.markdownText = markdown ?: @"";
	self.initialMarkdownText = self.markdownText;
	self.currentMarkdownText = self.markdownText;
	[self resetCharacterCount];
	self.titleField.stringValue = title ?: @"";
	self.initialTitleText = self.titleField.stringValue ?: @"";
	[self updateTitleAndCharacterCountVisibilityAnimated:NO];
	[self updateDocumentEditedState];

	if (self.didLoadEditorHTML) {
		__weak typeof(self) weak_self = self;
		[self applyMarkdownTextToEditorWithCompletion:^{
			MBNewPostController* strong_self = weak_self;
			if (strong_self == nil) {
				return;
			}

			strong_self.webView.hidden = NO;
			[strong_self.window makeFirstResponder:strong_self.webView];
		}];
	}
}

- (void) showEditingPostSourceErrorAlert:(NSError *)error
{
	NSAlert* alert = [[NSAlert alloc] init];
	alert.alertStyle = NSAlertStyleWarning;
	alert.messageText = @"Could Not Load Post";
	alert.informativeText = error.localizedDescription.length > 0 ? error.localizedDescription : @"The post could not be loaded for editing.";
	[alert addButtonWithTitle:@"OK"];

	if (self.window != nil) {
		[alert beginSheetModalForWindow:self.window completionHandler:nil];
	}
	else {
		[alert runModal];
	}
}

- (NSString *) markdownTextFromMicropubSourcePayload:(id)payload
{
	if (![payload isKindOfClass:[NSDictionary class]]) {
		return @"";
	}

	NSDictionary* dictionary = (NSDictionary*) payload;
	id properties_object = dictionary[@"properties"];
	if ([properties_object isKindOfClass:[NSDictionary class]]) {
		NSString* value = [self sourceStringValueFromObject:((NSDictionary*) properties_object)[@"content"]];
		if (value.length > 0) {
			return value;
		}
	}

	return [self sourceStringValueFromObject:dictionary[@"content"]];
}

- (NSString *) titleTextFromMicropubSourcePayload:(id)payload
{
	if (![payload isKindOfClass:[NSDictionary class]]) {
		return @"";
	}

	NSDictionary* dictionary = (NSDictionary*) payload;
	id properties_object = dictionary[@"properties"];
	if ([properties_object isKindOfClass:[NSDictionary class]]) {
		NSString* value = [self sourceStringValueFromObject:((NSDictionary*) properties_object)[@"name"]];
		if (value.length > 0) {
			return value;
		}
	}

	return [self sourceStringValueFromObject:dictionary[@"name"]];
}

- (NSString *) sourceStringValueFromObject:(id)object
{
	if ([object isKindOfClass:[NSArray class]]) {
		for (id item in (NSArray*) object) {
			NSString* value = [self sourceStringValueFromObject:item];
			if (value.length > 0) {
				return value;
			}
		}

		return @"";
	}

	if ([object isKindOfClass:[NSDictionary class]]) {
		NSDictionary* dictionary = (NSDictionary*) object;
		id value_object = dictionary[@"value"];
		if (value_object != nil && ![value_object isKindOfClass:[NSNull class]]) {
			return [self sourceStringValueFromObject:value_object];
		}

		return [self sourceStringValueFromObject:dictionary[@"html"]];
	}

	return [self stringValueFromObject:object];
}

- (void) postPreviewContent:(NSString *)content completion:(void (^)(NSString* _Nullable html, NSError* _Nullable error))completion
{
	if (self.token.length == 0) {
		NSError* error = [NSError errorWithDomain:InkwellNewPostErrorDomain code:1003 userInfo:@{ NSLocalizedDescriptionKey: @"Missing token for preview." }];
		completion(nil, error);
		return;
	}

	NSURL* request_url = [NSURL URLWithString:InkwellNewPostPreviewEndpoint];
	if (request_url == nil) {
		NSError* error = [NSError errorWithDomain:InkwellNewPostErrorDomain code:1004 userInfo:@{ NSLocalizedDescriptionKey: @"Preview endpoint URL was invalid." }];
		completion(nil, error);
		return;
	}

	NSString* body_string = [NSString stringWithFormat:@"content=%@", [self urlEncodedString:(content ?: @"")]];
	NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:request_url];
	request.HTTPMethod = @"POST";
	request.HTTPBody = [body_string dataUsingEncoding:NSUTF8StringEncoding];
	[request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
	[request setValue:@"text/html" forHTTPHeaderField:@"Accept"];
	[request setValue:[NSString stringWithFormat:@"Bearer %@", self.token] forHTTPHeaderField:@"Authorization"];

	NSURLSessionDataTask* task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
		NSError* result_error = error;
		if (result_error == nil) {
			NSHTTPURLResponse* http_response = (NSHTTPURLResponse*) response;
			if (http_response.statusCode < 200 || http_response.statusCode >= 300) {
				NSString* description = [self responseDescriptionForData:data defaultMessage:@"Preview failed."];
				result_error = [NSError errorWithDomain:InkwellNewPostErrorDomain code:http_response.statusCode userInfo:@{ NSLocalizedDescriptionKey: description }];
			}
		}

		NSString* html = nil;
		if (result_error == nil) {
			html = [[NSString alloc] initWithData:(data ?: [NSData data]) encoding:NSUTF8StringEncoding] ?: @"";
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			completion(html, result_error);
		});
	}];
	[task resume];
}

- (void) showPreviewHTML:(NSString *)html
{
	NSDictionary* payload = @{ @"html": html ?: @"" };
	NSData* json_data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
	NSString* json_string = [[NSString alloc] initWithData:json_data encoding:NSUTF8StringEncoding] ?: @"{\"html\":\"\"}";
	NSString* script = [NSString stringWithFormat:@"window.InkwellNewPostEditor && window.InkwellNewPostEditor.togglePreview(%@.html);", json_string];
	[self setPreviewBackgroundEnabled:YES];
	[self.webView evaluateJavaScript:script completionHandler:nil];
}

- (void) controlTextDidChange:(NSNotification *)notification
{
	if (notification.object == self.titleField) {
		[self updateTitleAndCharacterCountVisibilityAnimated:YES];
		[self updateDocumentEditedState];
	}
}

- (void) updateDocumentEditedState
{
	if (self.isClosingAfterPost) {
		self.window.documentEdited = NO;
		return;
	}

	NSString* initial_markdown = self.initialMarkdownText ?: @"";
	NSString* current_markdown = self.currentMarkdownText ?: @"";
	if (initial_markdown.length == 0) {
		current_markdown = [current_markdown stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	}
	NSString* initial_title = self.initialTitleText ?: @"";
	NSString* current_title = self.titleField.stringValue ?: @"";
	self.window.documentEdited = (![current_markdown isEqualToString:initial_markdown] || ![current_title isEqualToString:initial_title]);
}

- (void) updateCharacterCountWithPayload:(id)payload
{
	if (![payload isKindOfClass:[NSDictionary class]]) {
		return;
	}

	NSDictionary* dictionary = (NSDictionary*) payload;
	NSString* markdown = [self stringValueFromObject:dictionary[@"markdown"]];
	self.currentMarkdownText = markdown;
	NSInteger count = [self integerValueFromObject:dictionary[@"count"]];
	BOOL is_blockquote = [dictionary[@"is_blockquote"] respondsToSelector:@selector(boolValue)] ? [dictionary[@"is_blockquote"] boolValue] : NO;
	NSInteger max_count = is_blockquote ? 600 : 300;
	BOOL is_over_limit = (count > max_count);
	self.isContentOverCharacterLimit = is_over_limit;

	NSString* count_string = [NSString stringWithFormat:@"%ld", (long) count];
	NSString* limit_string = [NSString stringWithFormat:@"/%ld", (long) max_count];
	NSString* display_string = [count_string stringByAppendingString:limit_string];

	if (is_over_limit) {
		NSColor* over_limit_color = [NSColor colorNamed:InkwellNewPostCharacterCountOverLimitColorName] ?: NSColor.systemRedColor;
		NSMutableParagraphStyle* paragraph_style = [[NSMutableParagraphStyle alloc] init];
		paragraph_style.alignment = NSTextAlignmentRight;
		NSMutableAttributedString* attributed_string = [[NSMutableAttributedString alloc] initWithString:display_string attributes:@{
			NSFontAttributeName: self.characterCountField.font ?: [NSFont systemFontOfSize:NSFont.systemFontSize],
			NSForegroundColorAttributeName: NSColor.secondaryLabelColor,
			NSParagraphStyleAttributeName: paragraph_style
		}];
		[attributed_string addAttribute:NSForegroundColorAttributeName value:over_limit_color range:NSMakeRange(0, count_string.length)];
		self.characterCountField.attributedStringValue = attributed_string;
	}
	else {
		self.characterCountField.stringValue = display_string;
		self.characterCountField.textColor = NSColor.secondaryLabelColor;
	}

	[self updateTitleAndCharacterCountVisibilityAnimated:YES];
	if (self.isApplyingInitialMarkdownText) {
		self.isApplyingInitialMarkdownText = NO;
		self.initialMarkdownText = self.currentMarkdownText ?: @"";
		[self updateDocumentEditedState];
		return;
	}

	[self updateDocumentEditedState];
}

- (void) showDestinationsMenuFromView:(NSView *)view event:(NSEvent *)event
{
	if ([self isEditingExistingPost]) {
		return;
	}

	if (self.destinationsProvider != nil) {
		NSArray* cached_destinations = self.destinationsProvider();
		self.destinations = cached_destinations ?: @[];
	}

	if (self.destinations.count == 0) {
		return;
	}

	NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Blogs"];
	for (id object in self.destinations) {
		if (![object isKindOfClass:[NSDictionary class]]) {
			continue;
		}

		NSDictionary* destination = (NSDictionary*) object;
		NSString* name = [self stringValueFromObject:destination[@"name"]];
		if (name.length == 0) {
			continue;
		}

		NSMenuItem* menu_item = [[NSMenuItem alloc] initWithTitle:name action:@selector(selectDestinationFromMenuItem:) keyEquivalent:@""];
		menu_item.target = self;
		menu_item.representedObject = destination;

		NSString* uid = [self stringValueFromObject:destination[@"uid"]];
		if (uid.length > 0 && [uid isEqualToString:self.destinationUID]) {
			menu_item.state = NSControlStateValueOn;
		}

		[menu addItem:menu_item];
	}

	if (menu.numberOfItems == 0) {
		return;
	}

	[NSMenu popUpContextMenu:menu withEvent:event forView:view];
}

- (void) selectDestinationFromMenuItem:(NSMenuItem *)menu_item
{
	id represented_object = menu_item.representedObject;
	if (![represented_object isKindOfClass:[NSDictionary class]]) {
		return;
	}

	NSDictionary* destination = (NSDictionary*) represented_object;
	self.destinationName = [self stringValueFromObject:destination[@"name"]];
	self.destinationUID = [self stringValueFromObject:destination[@"uid"]];
	self.blogHostnameField.stringValue = self.destinationName;
	if (self.destinationUID.length > 0) {
		[[NSUserDefaults standardUserDefaults] setObject:self.destinationUID forKey:InkwellCurrentDestinationDefaultsKey];
	}
}

- (NSString *) stringValueFromObject:(id)object
{
	if ([object isKindOfClass:[NSString class]]) {
		return (NSString*) object;
	}

	if ([object isKindOfClass:[NSNumber class]]) {
		return [(NSNumber*) object stringValue];
	}

	return @"";
}

- (NSInteger) integerValueFromObject:(id)object
{
	if ([object isKindOfClass:[NSNumber class]]) {
		return [(NSNumber*) object integerValue];
	}

	if ([object isKindOfClass:[NSString class]]) {
		return [(NSString*) object integerValue];
	}

	return 0;
}

- (NSString *) urlEncodedString:(NSString *)string
{
	NSMutableCharacterSet* allowed_character_set = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
	[allowed_character_set removeCharactersInString:@"=&+?"];
	NSString* encoded_string = [string stringByAddingPercentEncodingWithAllowedCharacters:allowed_character_set];
	return encoded_string ?: @"";
}

- (NSString *) responseDescriptionForData:(NSData *)data defaultMessage:(NSString *)default_message
{
	if (data.length == 0) {
		return default_message;
	}

	id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
	if ([payload isKindOfClass:[NSDictionary class]]) {
		NSDictionary* dictionary = (NSDictionary*) payload;
		NSString* error_description = dictionary[@"error_description"];
		if (error_description.length > 0) {
			return error_description;
		}

		NSString* error_value = dictionary[@"error"];
		if (error_value.length > 0) {
			return error_value;
		}
	}

	NSString* string_value = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	return (string_value.length > 0) ? string_value : default_message;
}

- (void) webView:(WKWebView *)web_view didFinishNavigation:(WKNavigation *)navigation
{
	#pragma unused(web_view)
	#pragma unused(navigation)

	self.didLoadEditorHTML = YES;
	__weak typeof(self) weak_self = self;
	[self applyMarkdownTextToEditorWithCompletion:^{
		MBNewPostController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		// slight delay for good measure
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			MBNewPostController* delayed_strong_self = weak_self;
			if (delayed_strong_self == nil) {
				return;
			}

			if (delayed_strong_self.isLoadingEditingPostSource) {
				return;
			}

			delayed_strong_self.webView.hidden = NO;
			[delayed_strong_self.window makeFirstResponder:delayed_strong_self.webView];
		});
	}];
}

- (void) userContentController:(WKUserContentController *)user_content_controller didReceiveScriptMessage:(WKScriptMessage *)script_message
{
	#pragma unused(user_content_controller)

	if ([script_message.name isEqualToString:InkwellNewPostContentChangedScriptMessageName]) {
		[self updateCharacterCountWithPayload:script_message.body];
	}
}

- (void) savePostWindowFrameIfNeeded
{
	if (self.isSettingWindowFrame || self.window == nil) {
		return;
	}

	[self.window saveFrameUsingName:InkwellNewPostWindowAutosaveName];
}

- (BOOL) windowShouldClose:(id)sender
{
	#pragma unused(sender)

	if (self.isClosingAfterPost || !self.window.documentEdited) {
		return YES;
	}
	if (self.isPosting) {
		return NO;
	}

	NSAlert* alert = [[NSAlert alloc] init];
	alert.alertStyle = NSAlertStyleWarning;
	alert.messageText = @"Save changes to blog post before closing?";
	alert.informativeText = @"Saving will store the draft on Micro.blog. You can use Micro.blog to edit and publish the post.";
	[alert addButtonWithTitle:@"Save"];
	[alert addButtonWithTitle:@"Don't Save"];
	[alert addButtonWithTitle:@"Cancel"];

	NSModalResponse response = [alert runModal];
	if (response == NSAlertFirstButtonReturn) {
		[self saveDraftAndClose];
		return NO;
	}
	if (response == NSAlertSecondButtonReturn) {
		self.window.documentEdited = NO;
		return YES;
	}

	return NO;
}

- (void) windowWillClose:(NSNotification *)notification
{
	#pragma unused(notification)

	[self removeCommandReturnEventMonitor];
	self.editingPostSourceRequestIdentifier += 1;
	self.applyMarkdownTextRequestIdentifier += 1;
	self.isLoadingEditingPostSource = NO;
	self.isApplyingInitialMarkdownText = NO;

	void (^did_close_handler)(MBNewPostController* controller) = self.didCloseHandler;
	self.didCloseHandler = nil;
	if (did_close_handler != nil) {
		did_close_handler(self);
	}
}

- (void) windowDidMove:(NSNotification *)notification
{
	#pragma unused(notification)

	[self savePostWindowFrameIfNeeded];
}

- (void) windowDidResize:(NSNotification *)notification
{
	#pragma unused(notification)

	[self savePostWindowFrameIfNeeded];
}

- (BOOL) validateToolbarItem:(NSToolbarItem *)toolbar_item
{
	#pragma unused(toolbar_item)

	return YES;
}

- (NSArray<NSToolbarItemIdentifier> *) toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
	#pragma unused(toolbar)

	return @[
		NSToolbarFlexibleSpaceItemIdentifier,
		InkwellNewPostToolbarProgressIdentifier,
		InkwellNewPostToolbarPreviewIdentifier,
		InkwellNewPostToolbarPostIdentifier
	];
}

- (NSArray<NSToolbarItemIdentifier> *) toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
	#pragma unused(toolbar)

	return @[
		NSToolbarFlexibleSpaceItemIdentifier,
		InkwellNewPostToolbarProgressIdentifier,
		InkwellNewPostToolbarPreviewIdentifier,
		InkwellNewPostToolbarPostIdentifier
	];
}

- (NSToolbarItem *) toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)item_identifier willBeInsertedIntoToolbar:(BOOL)flag
{
	#pragma unused(toolbar)
	#pragma unused(flag)

	if ([item_identifier isEqualToString:InkwellNewPostToolbarPreviewIdentifier]) {
		NSToolbarItem* item = [[NSToolbarItem alloc] initWithItemIdentifier:item_identifier];
		item.label = @"Preview";
		item.paletteLabel = @"Preview";
		item.toolTip = @"Preview";

		MBPreviewButton* preview_button = [[MBPreviewButton alloc] initWithFrame:NSZeroRect];
		preview_button.title = @"Preview";
		preview_button.target = self;
		preview_button.action = @selector(preview:);
		preview_button.bezelStyle = NSBezelStyleRounded;
		[preview_button setButtonType:NSButtonTypeToggle];
		[preview_button sizeToFit];
		[preview_button.widthAnchor constraintGreaterThanOrEqualToConstant:70.0].active = YES;

		item.view = preview_button;
		self.previewButton = preview_button;
		return item;
	}

	if ([item_identifier isEqualToString:InkwellNewPostToolbarProgressIdentifier]) {
		NSToolbarItem* item = [[NSToolbarItem alloc] initWithItemIdentifier:item_identifier];
		item.label = @"Progress";
		item.paletteLabel = @"Progress";
		item.hidden = YES;

		NSProgressIndicator* progress_indicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0.0, 0.0, 16.0, 16.0)];
		progress_indicator.style = NSProgressIndicatorStyleSpinning;
		progress_indicator.indeterminate = YES;
		progress_indicator.controlSize = NSControlSizeSmall;
		progress_indicator.displayedWhenStopped = NO;
		progress_indicator.hidden = YES;

		item.view = progress_indicator;
		self.progressIndicator = progress_indicator;
		self.progressToolbarItem = item;
		return item;
	}

	if ([item_identifier isEqualToString:InkwellNewPostToolbarPostIdentifier]) {
		NSToolbarItem* item = [[NSToolbarItem alloc] initWithItemIdentifier:item_identifier];
		NSString* button_title = [self postToolbarButtonTitle];
		item.label = button_title;
		item.paletteLabel = button_title;
		item.toolTip = button_title;

		NSButton* post_button = [NSButton buttonWithTitle:button_title target:self action:@selector(post:)];
		post_button.bezelStyle = NSBezelStyleRounded;
		post_button.keyEquivalent = @"\r";
		post_button.keyEquivalentModifierMask = NSEventModifierFlagCommand;
		[post_button sizeToFit];
		[post_button.widthAnchor constraintGreaterThanOrEqualToConstant:65.0].active = YES;

		item.view = post_button;
		self.postToolbarItem = item;
		self.postButton = post_button;
		[self updatePostButtonTitle];
		return item;
	}

	return nil;
}

- (NSArray<NSToolbarItemIdentifier> *) toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar
{
	return @[ InkwellNewPostToolbarProgressIdentifier ];
}

@end
