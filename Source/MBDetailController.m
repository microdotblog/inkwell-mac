//
//  MBDetailController.m
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import "MBDetailController.h"
#import "MBClient.h"
#import "MBDetailWebView.h"
#import "MBEntry.h"
#import "MBHighlight.h"
#import "MBLinkHoverBubble.h"
#import "MBPhotoZoomController.h"
#import <WebKit/WebKit.h>

static CGFloat const InkwellDetailTopBarHeight = 52.0;
static CGFloat const InkwellDetailScrollingAdjust = 18.0;
static NSString* const InkwellPostTemplateName = @"PostTemplate";
static NSString* const InkwellRecapTemplateName = @"RecapTemplate";
static NSString* const InkwellPostTemplateType = @"html";
static NSString* const InkwellPostTitleToken = @"[TITLE]";
static NSString* const InkwellPostAuthorToken = @"[AUTHOR]";
static NSString* const InkwellPostContentToken = @"[CONTENT]";
static NSString* const InkwellInitialThemeStyleToken = @"[INITIAL_THEME_STYLE]";
static NSString* const InkwellSelectionChangedScriptMessageName = @"selectionChanged";
static NSString* const InkwellScrollChangedScriptMessageName = @"scrollChanged";
static NSString* const InkwellHighlightHoverScriptMessageName = @"highlightHover";
static NSString* const InkwellLinkHoverScriptMessageName = @"linkHover";
static NSString* const InkwellImageClickedScriptMessageName = @"imageClicked";
static NSString* const InkwellDefaultTextBackgroundHex = @"#ffffff";
static NSString* const InkwellDefaultTextFontName = @"San Francisco";
static NSString* const InkwellDefaultTextSizeName = @"Medium";
static NSString* const InkwellReaderHighlightLightBackgroundHex = @"#FFF9D6";
static NSString* const InkwellReaderHighlightLightTextHex = @"#1d1d1f";
static NSString* const InkwellReaderHighlightDarkBackgroundHex = @"#262613";
static NSString* const InkwellReaderHighlightDarkTextHex = @"#FFF2A6";
static NSString* const InkwellPreferencesDarkBlueBackgroundHex = @"#1c2435";
static NSString* const InkwellPreferencesBlackBackgroundHex = @"#000000";
static CGFloat const InkwellDetailLinkBubbleHorizontalInset = 14.0;
static CGFloat const InkwellDetailLinkBubbleBottomInset = 14.0;
static CGFloat const InkwellDetailLinkBubbleHorizontalPadding = 12.0;
static CGFloat const InkwellDetailLinkBubbleVerticalPadding = 6.0;
static CGFloat const InkwellDetailLinkBubbleMaxWidth = 450.0;

@interface MBDetailTopBarView : NSVisualEffectView
@end

@implementation MBDetailTopBarView

- (BOOL) mouseDownCanMoveWindow
{
	return YES;
}

@end

@interface MBWeakScriptMessageHandler : NSObject <WKScriptMessageHandler>

@property (nonatomic, weak) id<WKScriptMessageHandler> target;

- (instancetype) initWithTarget:(id<WKScriptMessageHandler>)target;

@end

@implementation MBWeakScriptMessageHandler

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

@interface MBDetailController () <WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler>

@property (strong) MBDetailWebView* webView;
@property (strong) MBWeakScriptMessageHandler* selectionScriptMessageHandler;
@property (strong) MBWeakScriptMessageHandler* scrollScriptMessageHandler;
@property (strong) MBWeakScriptMessageHandler* highlightHoverScriptMessageHandler;
@property (strong) MBWeakScriptMessageHandler* linkHoverScriptMessageHandler;
@property (strong) MBWeakScriptMessageHandler* imageClickedScriptMessageHandler;
@property (strong, nullable) MBHighlight* hoveredHighlight;
@property (assign) BOOL isDeletingHighlight;
@property (strong) NSVisualEffectView* topBarView;
@property (strong) MBLinkHoverBubble* hoveredLinkBubbleView;
@property (strong) NSTextField* hoveredLinkTextField;
@property (copy) NSString* hoveredLinkURLString;
@property (assign) BOOL hasTextSelection;
@property (assign) BOOL isTopBarMaterialVisible;
@property (assign) BOOL isShowingReadingRecap;
@property (strong) id keyDownEventMonitor;
@property (assign) NSInteger topBarAnimationID;
@property (assign) NSInteger currentEntryID;
@property (strong, nullable) MBEntry* currentSidebarItem;
@property (assign) NSPoint nextPhotoWindowCascadePoint;
@property (assign) BOOL hasNextPhotoWindowCascadePoint;
@property (strong) NSMutableArray* photoZoomControllers;

- (NSEvent* _Nullable) monitoredKeyDownEvent:(NSEvent*) event;
- (BOOL) detailPaneContainsFirstResponder;
- (BOOL) handleReadingRecapPageUp;
- (BOOL) handleReadingRecapPageDown;
- (void) scrollReadingRecapForward:(BOOL) is_forward;
- (NSString *) bundledJavaScriptNamed:(NSString*) script_name;
- (NSString *) detailRuntimeScript;
- (NSString *) selectionObserverScript;
- (NSString *) scrollObserverScript;
- (NSString *) linkHoverObserverScript;
- (NSString *) imageClickObserverScript;
- (NSString *) javaScriptForRuntimeFunction:(NSString*) function_name payload:(id _Nullable) payload;
- (NSString *) jsonStringForJavaScriptObject:(id _Nullable) object;
- (void) applyReadingRecapColorsForDarkTheme:(BOOL) is_dark_theme;
- (NSString *) htmlStringByApplyingReadingRecapStyles:(NSString*) html darkTheme:(BOOL) is_dark_theme;
- (NSString *) readingRecapTagByApplyingStyles:(NSString*) tag darkTheme:(BOOL) is_dark_theme;
- (NSURL *) baseURLForEntry:(MBEntry* _Nullable) entry;
- (void) updateWebViewUnderPageBackgroundColor;
- (NSColor *) colorFromHexString:(NSString*) color_hex;
- (NSString *) htmlAttributeValue:(NSString*) attribute_name inTag:(NSString*) tag;
- (NSString *) htmlTag:(NSString*) tag bySettingStyleDeclarations:(NSString*) style_declarations;
- (NSString *) initialThemeStyleBlockForPosts;
- (NSString *) initialThemeStyleBlockForReadingRecap;
- (NSString *) readingRecapAvatarFallbackScript;
- (NSString *) normalizedRecapColorString:(NSString*) color_hex;
- (NSString *) recapColorString:(NSString*) color_hex withOpacity:(NSString*) opacity_hex;
- (BOOL) hasStoredTextBackgroundPreference;
- (BOOL) canDeleteHighlight:(MBHighlight*) highlight;
- (BOOL) canDeleteHoveredHighlight;
- (MBHighlight* _Nullable) highlightForHoverIdentifier:(NSString*) highlight_id;
- (void) clearHoveredHighlight;
- (void) updateHoveredHighlightWithScriptMessageBody:(id) body;
- (void) updateHoveredLinkWithScriptMessageBody:(id) body;
- (void) updateHoveredLinkURLString:(NSString*) url_string;
- (NSURL * _Nullable) urlFromScriptMessageValue:(id) value;
- (NSURL * _Nullable) anchorURLFromScriptMessageBody:(id) body;
- (NSURL * _Nullable) currentPostURL;
- (BOOL) URLLooksLikeImage:(NSURL *) url;
- (void) promptToDeleteHoveredHighlight:(id) sender;
- (void) deleteHighlight:(MBHighlight*) highlight;
- (void) presentDeleteError:(NSError*) error;
- (NSURL * _Nullable) imageURLFromScriptMessageBody:(id) body;
- (MBPhotoZoomController* _Nullable) existingPhotoWindowControllerForURL:(NSURL *) image_url;
- (void) removePhotoWindowController:(MBPhotoZoomController*) controller;
- (void) presentPhotoWindowForURL:(NSURL *) image_url;
- (void) presentPhotoWindowForURL:(NSURL *) imageURL relatedPostURL:(NSURL * _Nullable) relatedPostURL;
- (BOOL) shouldUseDarkReaderHighlightBackgroundForBackgroundHex:(NSString*) background_hex;
- (BOOL) systemInterfaceStyleIsDark;
- (BOOL) prefersDarkSystemAppearance;

@end

@implementation MBDetailController

- (instancetype) init
{
	self = [super init];
	if (self) {
		self.token = @"";
		self.photoZoomControllers = [[NSMutableArray alloc] init];
	}
	return self;
}

- (void) loadView
{
	NSView *root_view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 780.0, 600.0)];
	root_view.translatesAutoresizingMaskIntoConstraints = NO;

	MBDetailTopBarView* top_bar_view = [[MBDetailTopBarView alloc] initWithFrame:NSZeroRect];
	top_bar_view.translatesAutoresizingMaskIntoConstraints = NO;
	top_bar_view.blendingMode = NSVisualEffectBlendingModeWithinWindow;
	top_bar_view.material = NSVisualEffectMaterialHeaderView;
	top_bar_view.state = NSVisualEffectStateActive;
	top_bar_view.alphaValue = 0.0;

	WKUserContentController* user_content_controller = [[WKUserContentController alloc] init];
	self.selectionScriptMessageHandler = [[MBWeakScriptMessageHandler alloc] initWithTarget:self];
	self.scrollScriptMessageHandler = [[MBWeakScriptMessageHandler alloc] initWithTarget:self];
	self.highlightHoverScriptMessageHandler = [[MBWeakScriptMessageHandler alloc] initWithTarget:self];
	self.linkHoverScriptMessageHandler = [[MBWeakScriptMessageHandler alloc] initWithTarget:self];
	self.imageClickedScriptMessageHandler = [[MBWeakScriptMessageHandler alloc] initWithTarget:self];
	[user_content_controller addScriptMessageHandler:self.selectionScriptMessageHandler name:InkwellSelectionChangedScriptMessageName];
	[user_content_controller addScriptMessageHandler:self.scrollScriptMessageHandler name:InkwellScrollChangedScriptMessageName];
	[user_content_controller addScriptMessageHandler:self.highlightHoverScriptMessageHandler name:InkwellHighlightHoverScriptMessageName];
	[user_content_controller addScriptMessageHandler:self.linkHoverScriptMessageHandler name:InkwellLinkHoverScriptMessageName];
	[user_content_controller addScriptMessageHandler:self.imageClickedScriptMessageHandler name:InkwellImageClickedScriptMessageName];

	WKUserScript* detail_runtime_script = [[WKUserScript alloc] initWithSource:[self detailRuntimeScript] injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
	[user_content_controller addUserScript:detail_runtime_script];
	WKUserScript* selection_script = [[WKUserScript alloc] initWithSource:[self selectionObserverScript] injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
	[user_content_controller addUserScript:selection_script];
	WKUserScript* reading_recap_avatar_script = [[WKUserScript alloc] initWithSource:[self readingRecapAvatarFallbackScript] injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
	[user_content_controller addUserScript:reading_recap_avatar_script];
	WKUserScript* scroll_script = [[WKUserScript alloc] initWithSource:[self scrollObserverScript] injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
	[user_content_controller addUserScript:scroll_script];
	WKUserScript* link_hover_script = [[WKUserScript alloc] initWithSource:[self linkHoverObserverScript] injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
	[user_content_controller addUserScript:link_hover_script];
	WKUserScript* image_click_script = [[WKUserScript alloc] initWithSource:[self imageClickObserverScript] injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
	[user_content_controller addUserScript:image_click_script];

	WKWebViewConfiguration* configuration = [[WKWebViewConfiguration alloc] init];
	configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
	configuration.userContentController = user_content_controller;

	MBDetailWebView* web_view = [[MBDetailWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
	web_view.translatesAutoresizingMaskIntoConstraints = NO;
	web_view.navigationDelegate = self;
	web_view.UIDelegate = self;
	__weak typeof(self) weak_self = self;
	web_view.focusSidebarHandler = ^BOOL {
		MBDetailController* strong_self = weak_self;
		if (strong_self == nil || strong_self.focusSidebarHandler == nil) {
			return NO;
		}

		return strong_self.focusSidebarHandler();
	};
	web_view.scrollPageUpHandler = ^BOOL {
		MBDetailController* strong_self = weak_self;
		if (strong_self == nil) {
			return NO;
		}

		return [strong_self handleReadingRecapPageUp];
	};
	web_view.scrollPageDownHandler = ^BOOL {
		MBDetailController* strong_self = weak_self;
		if (strong_self == nil) {
			return NO;
		}

		return [strong_self handleReadingRecapPageDown];
	};
	web_view.shouldShowHighlightMenuItemHandler = ^BOOL {
		MBDetailController* strong_self = weak_self;
		if (strong_self == nil) {
			return NO;
		}

		return (strong_self.hasTextSelection && strong_self.currentEntryID > 0);
	};
	web_view.shouldShowDeleteHighlightMenuItemHandler = ^BOOL {
		MBDetailController* strong_self = weak_self;
		if (strong_self == nil) {
			return NO;
		}

		return [strong_self canDeleteHoveredHighlight];
	};
	web_view.deleteHoveredHighlightHandler = ^{
		MBDetailController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		[strong_self promptToDeleteHoveredHighlight:nil];
	};

	self.keyDownEventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent * _Nullable(NSEvent *event) {
		MBDetailController* strong_self = weak_self;
		if (strong_self == nil) {
			return event;
		}

		return [strong_self monitoredKeyDownEvent:event];
	}];

	MBLinkHoverBubble* hovered_link_bubble_view = [[MBLinkHoverBubble alloc] initWithFrame:NSZeroRect];
	hovered_link_bubble_view.hidden = YES;

	NSTextField* hovered_link_text_field = [NSTextField labelWithString:@""];
	hovered_link_text_field.translatesAutoresizingMaskIntoConstraints = NO;
	hovered_link_text_field.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium];
	hovered_link_text_field.textColor = [NSColor secondaryLabelColor];
	hovered_link_text_field.lineBreakMode = NSLineBreakByTruncatingMiddle;
	hovered_link_text_field.maximumNumberOfLines = 1;
	hovered_link_text_field.usesSingleLineMode = YES;
	[hovered_link_text_field setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
	[hovered_link_text_field setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
	[hovered_link_bubble_view addSubview:hovered_link_text_field];

	[root_view addSubview:web_view];
	[root_view addSubview:top_bar_view];
	[root_view addSubview:hovered_link_bubble_view];
	[NSLayoutConstraint activateConstraints:@[
		[top_bar_view.topAnchor constraintEqualToAnchor:root_view.topAnchor],
		[top_bar_view.leadingAnchor constraintEqualToAnchor:root_view.leadingAnchor],
		[top_bar_view.trailingAnchor constraintEqualToAnchor:root_view.trailingAnchor],
		[top_bar_view.heightAnchor constraintEqualToConstant:InkwellDetailTopBarHeight],
		[web_view.topAnchor constraintEqualToAnchor:root_view.topAnchor],
		[web_view.bottomAnchor constraintEqualToAnchor:root_view.bottomAnchor],
		[web_view.leadingAnchor constraintEqualToAnchor:root_view.leadingAnchor],
		[web_view.trailingAnchor constraintEqualToAnchor:root_view.trailingAnchor],
		[hovered_link_bubble_view.leadingAnchor constraintEqualToAnchor:root_view.leadingAnchor constant:InkwellDetailLinkBubbleHorizontalInset],
		[hovered_link_bubble_view.bottomAnchor constraintEqualToAnchor:root_view.safeAreaLayoutGuide.bottomAnchor constant:-InkwellDetailLinkBubbleBottomInset],
		[hovered_link_bubble_view.trailingAnchor constraintLessThanOrEqualToAnchor:root_view.trailingAnchor constant:-InkwellDetailLinkBubbleHorizontalInset],
		[hovered_link_bubble_view.widthAnchor constraintLessThanOrEqualToConstant:InkwellDetailLinkBubbleMaxWidth],
		[hovered_link_text_field.topAnchor constraintEqualToAnchor:hovered_link_bubble_view.topAnchor constant:InkwellDetailLinkBubbleVerticalPadding],
		[hovered_link_text_field.bottomAnchor constraintEqualToAnchor:hovered_link_bubble_view.bottomAnchor constant:-InkwellDetailLinkBubbleVerticalPadding],
		[hovered_link_text_field.leadingAnchor constraintEqualToAnchor:hovered_link_bubble_view.leadingAnchor constant:InkwellDetailLinkBubbleHorizontalPadding],
		[hovered_link_text_field.trailingAnchor constraintEqualToAnchor:hovered_link_bubble_view.trailingAnchor constant:-InkwellDetailLinkBubbleHorizontalPadding]
	]];

	self.webView = web_view;
	[self updateWebViewUnderPageBackgroundColor];
	self.topBarView = top_bar_view;
	self.hoveredLinkBubbleView = hovered_link_bubble_view;
	self.hoveredLinkTextField = hovered_link_text_field;
	self.view = root_view;
}

- (void) dealloc
{
	if (self.keyDownEventMonitor != nil) {
		[NSEvent removeMonitor:self.keyDownEventMonitor];
		self.keyDownEventMonitor = nil;
	}

	[self.webView.configuration.userContentController removeScriptMessageHandlerForName:InkwellSelectionChangedScriptMessageName];
	[self.webView.configuration.userContentController removeScriptMessageHandlerForName:InkwellScrollChangedScriptMessageName];
	[self.webView.configuration.userContentController removeScriptMessageHandlerForName:InkwellHighlightHoverScriptMessageName];
	[self.webView.configuration.userContentController removeScriptMessageHandlerForName:InkwellLinkHoverScriptMessageName];
	[self.webView.configuration.userContentController removeScriptMessageHandlerForName:InkwellImageClickedScriptMessageName];

	for (MBPhotoZoomController* controller in [self.photoZoomControllers copy]) {
		controller.windowWillCloseHandler = nil;
		[controller close];
	}
}

- (BOOL) hasSelection
{
	return self.hasTextSelection;
}

- (BOOL) focusDetailPane
{
	if (self.webView == nil) {
		return NO;
	}

	NSWindow* window = self.view.window ?: self.webView.window;
	if (window == nil) {
		return NO;
	}

	return [window makeFirstResponder:self.webView];
}

- (NSInteger) displayedEntryID
{
	return self.currentEntryID;
}

- (void) printCurrentContentForWindow:(NSWindow*) window
{
	if (self.webView == nil || window == nil) {
		return;
	}

	NSPrintInfo* print_info = [NSPrintInfo.sharedPrintInfo copy];
	NSPrintOperation* print_operation = [self.webView printOperationWithPrintInfo:print_info];
	print_operation.showsPrintPanel = YES;
	print_operation.showsProgressPanel = YES;
	[print_operation runOperationModalForWindow:window delegate:nil didRunSelector:NULL contextInfo:NULL];
}

- (void) webView:(WKWebView *)web_view decidePolicyForNavigationAction:(WKNavigationAction *)navigation_action decisionHandler:(void (^)(WKNavigationActionPolicy))decision_handler
{
	#pragma unused(web_view)
	NSURL* request_url = navigation_action.request.URL;
	BOOL is_link_activated = (navigation_action.navigationType == WKNavigationTypeLinkActivated);
	BOOL is_main_frame_navigation = navigation_action.targetFrame.isMainFrame;
	if (!is_link_activated || request_url == nil || !is_main_frame_navigation) {
		decision_handler(WKNavigationActionPolicyAllow);
		return;
	}

	[[NSWorkspace sharedWorkspace] openURL:request_url];
	decision_handler(WKNavigationActionPolicyCancel);
}

- (WKWebView*) webView:(WKWebView*) web_view createWebViewWithConfiguration:(WKWebViewConfiguration*) configuration forNavigationAction:(WKNavigationAction*) navigation_action windowFeatures:(WKWindowFeatures*) window_features
{
	#pragma unused(web_view)
	#pragma unused(configuration)
	#pragma unused(window_features)

	NSURL* request_url = navigation_action.request.URL;
	if (request_url != nil) {
		[[NSWorkspace sharedWorkspace] openURL:request_url];
	}

	return nil;
}

- (void) webView:(WKWebView*) web_view didFinishNavigation:(WKNavigation*) navigation
{
	#pragma unused(web_view)
	#pragma unused(navigation)
	[self refreshHighlights];
	[self applyPreferredTextSettings];
	[self updateTopBarMaterialForScrolledDown:NO];
}

- (void) showSidebarItem:(MBEntry * _Nullable)item
{
	[self updateSelectionState:NO];
	[self updateTopBarMaterialForScrolledDown:NO];
	[self clearHoveredHighlight];
	[self updateHoveredLinkURLString:@""];
	[self updateWebViewUnderPageBackgroundColor];
	self.isShowingReadingRecap = NO;

	if (item == nil) {
		self.currentEntryID = 0;
		self.currentSidebarItem = nil;
		NSString* html = [self htmlForPostTitle:@"" author:@"" siteTitle:@"" content:@""];
		[self.webView loadHTMLString:html baseURL:[self baseURLForEntry:nil]];
		return;
	}

	self.currentEntryID = item.entryID;
	self.currentSidebarItem = item;

	NSString* safe_title = [self escapedHTMLString:item.title ?: @""];
	NSString* entry_html = item.text ?: @"";
	NSString* content_value = @"";
	if (entry_html.length > 0) {
		content_value = entry_html;
	}
	else {
		NSString* fallback_text = item.summary;
		if (fallback_text.length == 0) {
			fallback_text = item.source;
		}
		if (fallback_text.length == 0) {
			fallback_text = @"No content.";
		}

		content_value = [self escapedHTMLString:fallback_text];
	}

	NSString* html = [self htmlForPostTitle:safe_title author:item.author siteTitle:item.subscriptionTitle content:content_value];
	[self.webView loadHTMLString:html baseURL:[self baseURLForEntry:item]];
}

- (void) showReadingRecapHTML:(NSString*) html
{
	[self updateSelectionState:NO];
	[self updateTopBarMaterialForScrolledDown:NO];
	[self clearHoveredHighlight];
	[self updateHoveredLinkURLString:@""];
	[self updateWebViewUnderPageBackgroundColor];
	self.isShowingReadingRecap = YES;
	self.currentEntryID = 0;
	self.currentSidebarItem = nil;

	NSString* processed_html = [self processedReadingRecapHTML:html ?: @""];
	NSString* recap_html = [self htmlForReadingRecapContent:processed_html];
	[self.webView loadHTMLString:recap_html baseURL:[self baseURLForEntry:nil]];
	[self focusDetailPane];
}

- (NSEvent* _Nullable) monitoredKeyDownEvent:(NSEvent*) event
{
	if (!self.isShowingReadingRecap || ![self detailPaneContainsFirstResponder]) {
		return event;
	}

	NSEventModifierFlags modifier_flags = (event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask);
	BOOL has_disallowed_modifiers = ((modifier_flags & (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl | NSEventModifierFlagShift)) != 0);
	if (has_disallowed_modifiers) {
		return event;
	}

	NSString* characters = event.charactersIgnoringModifiers ?: @"";
	if (characters.length == 0) {
		return event;
	}

	unichar key_code = [characters characterAtIndex:0];
	if (key_code == NSUpArrowFunctionKey) {
		[self scrollReadingRecapForward:NO];
		return nil;
	}
	if (key_code == NSDownArrowFunctionKey) {
		[self scrollReadingRecapForward:YES];
		return nil;
	}

	return event;
}

- (BOOL) detailPaneContainsFirstResponder
{
	NSWindow* window = self.view.window ?: self.webView.window;
	if (window == nil) {
		return NO;
	}

	NSResponder* first_responder = window.firstResponder;
	if (first_responder == self.webView) {
		return YES;
	}
	if (![first_responder isKindOfClass:[NSView class]]) {
		return NO;
	}

	NSView* first_responder_view = (NSView *) first_responder;
	NSView* current_view = first_responder_view;
	while (current_view != nil) {
		if (current_view == self.webView) {
			return YES;
		}

		current_view = current_view.superview;
	}

	return NO;
}

- (BOOL) handleReadingRecapPageUp
{
	if (!self.isShowingReadingRecap || self.webView == nil) {
		return NO;
	}

	[self scrollReadingRecapForward:NO];
	return YES;
}

- (BOOL) handleReadingRecapPageDown
{
	if (!self.isShowingReadingRecap || self.webView == nil) {
		return NO;
	}

	[self scrollReadingRecapForward:YES];
	return YES;
}

- (void) scrollReadingRecapForward:(BOOL) is_forward
{
	if (self.webView == nil) {
		return;
	}

	NSDictionary* payload = @{
		@"is_forward": @(is_forward),
		@"scroll_inset": @(InkwellDetailTopBarHeight + InkwellDetailScrollingAdjust)
	};
	NSString* script = [self javaScriptForRuntimeFunction:@"scrollReadingRecap" payload:payload];
	[self.webView evaluateJavaScript:script completionHandler:nil];
}

- (void) userContentController:(WKUserContentController *)user_content_controller didReceiveScriptMessage:(WKScriptMessage *)script_message
{
	#pragma unused(user_content_controller)

	if ([script_message.name isEqualToString:InkwellScrollChangedScriptMessageName]) {
		BOOL is_scrolled_down = NO;
		if ([script_message.body respondsToSelector:@selector(boolValue)]) {
			is_scrolled_down = [(id) script_message.body boolValue];
		}

		[self updateTopBarMaterialForScrolledDown:is_scrolled_down];
		return;
	}

	if ([script_message.name isEqualToString:InkwellHighlightHoverScriptMessageName]) {
		[self updateHoveredHighlightWithScriptMessageBody:script_message.body];
		return;
	}

	if ([script_message.name isEqualToString:InkwellLinkHoverScriptMessageName]) {
		[self updateHoveredLinkWithScriptMessageBody:script_message.body];
		return;
	}

	if ([script_message.name isEqualToString:InkwellImageClickedScriptMessageName]) {
		NSURL* image_url = [self imageURLFromScriptMessageBody:script_message.body];
		if (image_url != nil) {
			NSURL* anchor_url = [self anchorURLFromScriptMessageBody:script_message.body];
			NSURL* related_post_url = nil;
			if (anchor_url != nil && ![self URLLooksLikeImage:anchor_url]) {
				related_post_url = anchor_url;
			}
			if (related_post_url == nil) {
				related_post_url = [self currentPostURL];
			}

			[self presentPhotoWindowForURL:image_url relatedPostURL:related_post_url];
		}
		return;
	}

	if (![script_message.name isEqualToString:InkwellSelectionChangedScriptMessageName]) {
		return;
	}

	BOOL has_selection = NO;
	if ([script_message.body respondsToSelector:@selector(boolValue)]) {
		has_selection = [(id) script_message.body boolValue];
	}

	[self updateSelectionState:has_selection];
}

- (void) requestSelectionHighlightPayloadWithCompletion:(void (^)(NSDictionary* _Nullable payload)) completion
{
	NSString* script = [self javaScriptForRuntimeFunction:@"getSelectionPayload" payload:nil];
	[self.webView evaluateJavaScript:script completionHandler:^(id _Nullable result, NSError * _Nullable error) {
		#pragma unused(error)
		NSDictionary* payload = nil;
		if ([result isKindOfClass:[NSDictionary class]]) {
			payload = (NSDictionary*) result;
		}

		if (completion != nil) {
			completion(payload);
		}
	}];
}

- (void) clearSelection
{
	NSString* script = [self javaScriptForRuntimeFunction:@"clearSelection" payload:nil];
	[self.webView evaluateJavaScript:script completionHandler:nil];
	[self updateSelectionState:NO];
}

- (void) refreshHighlights
{
	[self clearHoveredHighlight];

	NSArray* highlights = @[];
	if (self.currentEntryID > 0 && self.highlightsProvider != nil) {
		NSArray* provided_highlights = self.highlightsProvider(self.currentEntryID);
		if ([provided_highlights isKindOfClass:[NSArray class]]) {
			highlights = provided_highlights;
		}
	}

	NSMutableArray* range_payload = [NSMutableArray array];
	for (id object in highlights) {
		if (![object isKindOfClass:[MBHighlight class]]) {
			continue;
		}

		MBHighlight* highlight = (MBHighlight*) object;
		if (highlight.entryID != self.currentEntryID) {
			continue;
		}

		NSInteger start_offset = MAX(0, highlight.selectionStart);
		NSInteger end_offset = MAX(start_offset + 1, highlight.selectionEnd);
		if (end_offset <= start_offset) {
			continue;
		}

		NSMutableDictionary* dictionary = [@{
			@"start_offset": @(start_offset),
			@"end_offset": @(end_offset),
			@"id": highlight.localID ?: @""
		} mutableCopy];
		if (highlight.highlightID.length > 0) {
			dictionary[@"highlight_id"] = highlight.highlightID;
		}
		[range_payload addObject:dictionary];
	}

	NSString* script = [self javaScriptForRuntimeFunction:@"restoreHighlights" payload:range_payload];
	[self.webView evaluateJavaScript:script completionHandler:nil];
}

- (BOOL) canDeleteHighlight:(MBHighlight*) highlight
{
	if (self.isDeletingHighlight || self.client == nil || self.token.length == 0) {
		return NO;
	}
	if (![highlight isKindOfClass:[MBHighlight class]] || highlight.entryID <= 0) {
		return NO;
	}

	NSString* highlight_id = [highlight.highlightID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	return (highlight_id.length > 0);
}

- (BOOL) canDeleteHoveredHighlight
{
	return [self canDeleteHighlight:self.hoveredHighlight];
}

- (MBHighlight* _Nullable) highlightForHoverIdentifier:(NSString*) highlight_id
{
	NSString* trimmed_highlight_id = [highlight_id stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (trimmed_highlight_id.length == 0 || self.currentEntryID <= 0 || self.highlightsProvider == nil) {
		return nil;
	}

	NSArray* highlights = self.highlightsProvider(self.currentEntryID);
	if (![highlights isKindOfClass:[NSArray class]]) {
		return nil;
	}

	for (id object in highlights) {
		if (![object isKindOfClass:[MBHighlight class]]) {
			continue;
		}

		MBHighlight* highlight = (MBHighlight*) object;
		if (highlight.entryID != self.currentEntryID) {
			continue;
		}

		NSString* remote_highlight_id = [highlight.highlightID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		NSString* local_highlight_id = [highlight.localID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		if ([remote_highlight_id isEqualToString:trimmed_highlight_id] || [local_highlight_id isEqualToString:trimmed_highlight_id]) {
			return highlight;
		}
	}

	return nil;
}

- (void) clearHoveredHighlight
{
	self.hoveredHighlight = nil;
}

- (void) updateHoveredLinkWithScriptMessageBody:(id) body
{
	NSString* url_string = @"";
	if ([body isKindOfClass:[NSString class]]) {
		url_string = [(NSString*) body stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	}
	else if ([body respondsToSelector:@selector(description)]) {
		url_string = [[body description] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	}

	[self updateHoveredLinkURLString:url_string];
}

- (void) updateHoveredLinkURLString:(NSString*) url_string
{
	NSString* trimmed_url_string = [url_string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if ([self.hoveredLinkURLString isEqualToString:trimmed_url_string]) {
		return;
	}

	self.hoveredLinkURLString = trimmed_url_string;
	self.hoveredLinkTextField.stringValue = trimmed_url_string;
	self.hoveredLinkBubbleView.hidden = (trimmed_url_string.length == 0);
}

- (void) updateHoveredHighlightWithScriptMessageBody:(id) body
{
	if (![body isKindOfClass:[NSDictionary class]]) {
		[self clearHoveredHighlight];
		return;
	}

	NSDictionary* payload = (NSDictionary*) body;
	NSString* event_name = [[payload[@"event"] description] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	NSString* highlight_id = [[payload[@"highlight_id"] description] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (event_name.length == 0 || highlight_id.length == 0) {
		[self clearHoveredHighlight];
		return;
	}

	if ([event_name isEqualToString:@"mouseover"]) {
		self.hoveredHighlight = [self highlightForHoverIdentifier:highlight_id];
		return;
	}

	if ([event_name isEqualToString:@"mouseout"]) {
		NSString* hovered_highlight_id = [self.hoveredHighlight.highlightID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		NSString* hovered_local_id = [self.hoveredHighlight.localID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		if ([hovered_highlight_id isEqualToString:highlight_id] || [hovered_local_id isEqualToString:highlight_id]) {
			[self clearHoveredHighlight];
		}
	}
}

- (IBAction) promptToDeleteHoveredHighlight:(id) sender
{
	#pragma unused(sender)
	MBHighlight* highlight = self.hoveredHighlight;
	NSWindow* window = self.view.window ?: self.webView.window;
	if (![self canDeleteHighlight:highlight] || window == nil) {
		return;
	}

	NSAlert* alert = [[NSAlert alloc] init];
	alert.alertStyle = NSAlertStyleWarning;
	alert.messageText = @"Delete Highlight?";
	alert.informativeText = @"This will delete the selected highlight from your account.";
	[alert addButtonWithTitle:@"Delete"];
	[alert addButtonWithTitle:@"Cancel"];

	__weak typeof(self) weak_self = self;
	[alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse return_code) {
		if (return_code != NSAlertFirstButtonReturn) {
			return;
		}

		MBDetailController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		[strong_self deleteHighlight:highlight];
	}];
}

- (void) deleteHighlight:(MBHighlight*) highlight
{
	if (![self canDeleteHighlight:highlight]) {
		return;
	}

	self.isDeletingHighlight = YES;
	[self clearHoveredHighlight];

	__weak typeof(self) weak_self = self;
	[self.client deleteHighlight:highlight token:self.token completion:^(NSError* _Nullable error) {
		MBDetailController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		strong_self.isDeletingHighlight = NO;
		if (error != nil) {
			[strong_self presentDeleteError:error];
			return;
		}

		[strong_self refreshHighlights];
		if (strong_self.highlightDeletedHandler != nil) {
			strong_self.highlightDeletedHandler(highlight);
		}
	}];
}

- (void) presentDeleteError:(NSError*) error
{
	NSWindow* window = self.view.window ?: self.webView.window;
	if (error == nil || window == nil) {
		return;
	}

	NSAlert* alert = [[NSAlert alloc] init];
	alert.alertStyle = NSAlertStyleWarning;
	alert.messageText = @"Delete Failed";
	alert.informativeText = error.localizedDescription ?: @"The highlight could not be deleted.";
	[alert beginSheetModalForWindow:window completionHandler:nil];
}

- (NSURL * _Nullable) imageURLFromScriptMessageBody:(id) body
{
	if (![body isKindOfClass:[NSDictionary class]]) {
		return nil;
	}

	NSDictionary* payload = (NSDictionary*) body;
	NSString* image_url_string = [[payload[@"image_url"] description] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (image_url_string.length == 0) {
		image_url_string = [[payload[@"image_src"] description] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	}
	if (image_url_string.length == 0) {
		return nil;
	}

	NSURL* image_url = [NSURL URLWithString:image_url_string];
	if (image_url == nil || image_url.scheme.length == 0) {
		return nil;
	}

	return image_url;
}

- (NSURL * _Nullable) urlFromScriptMessageValue:(id) value
{
	if (value == nil) {
		return nil;
	}

	NSString* url_string = [[value description] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (url_string.length == 0) {
		return nil;
	}

	NSURL* url = [NSURL URLWithString:url_string];
	if (url == nil || url.scheme.length == 0) {
		return nil;
	}

	return url;
}

- (NSURL * _Nullable) anchorURLFromScriptMessageBody:(id) body
{
	if (![body isKindOfClass:[NSDictionary class]]) {
		return nil;
	}

	NSDictionary* payload = (NSDictionary*) body;
	return [self urlFromScriptMessageValue:payload[@"anchor_href"]];
}

- (NSURL * _Nullable) currentPostURL
{
	return [self urlFromScriptMessageValue:self.currentSidebarItem.url];
}

- (BOOL) URLLooksLikeImage:(NSURL *) url
{
	NSString* path_extension = [[url.pathExtension ?: @"" lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (path_extension.length == 0) {
		return NO;
	}

	static NSSet* image_extensions;
	static dispatch_once_t once_token;
	dispatch_once(&once_token, ^{
		image_extensions = [NSSet setWithArray:@[ @"apng", @"avif", @"bmp", @"gif", @"heic", @"heif", @"jpeg", @"jpg", @"png", @"svg", @"tif", @"tiff", @"webp" ]];
	});

	return [image_extensions containsObject:path_extension];
}

- (MBPhotoZoomController* _Nullable) existingPhotoWindowControllerForURL:(NSURL *) image_url
{
	if (image_url == nil) {
		return nil;
	}

	image_url = [MBPhotoZoomController normalizedImageURL:image_url];
	for (MBPhotoZoomController* controller in self.photoZoomControllers) {
		if ([controller.imageURL isEqual:image_url]) {
			return controller;
		}
	}

	return nil;
}

- (void) removePhotoWindowController:(MBPhotoZoomController*) controller
{
	if (controller == nil) {
		return;
	}

	[self.photoZoomControllers removeObject:controller];
	if (self.photoZoomControllers.count == 0) {
		self.hasNextPhotoWindowCascadePoint = NO;
	}
}

- (void) presentPhotoWindowForURL:(NSURL *) image_url
{
	[self presentPhotoWindowForURL:image_url relatedPostURL:nil];
}

- (void) presentPhotoWindowForURL:(NSURL *) imageURL relatedPostURL:(NSURL * _Nullable) relatedPostURL
{
	if (imageURL == nil) {
		return;
	}

	MBPhotoZoomController* existing_controller = [self existingPhotoWindowControllerForURL:imageURL];
	if (existing_controller != nil) {
		[existing_controller updateRelatedPostURL:relatedPostURL];
		[existing_controller showWindow:nil];
		[existing_controller.window makeKeyAndOrderFront:nil];
		[NSApp activateIgnoringOtherApps:YES];
		return;
	}

	MBPhotoZoomController* controller = [[MBPhotoZoomController alloc] init];
	if (self.hasNextPhotoWindowCascadePoint) {
		self.nextPhotoWindowCascadePoint = [controller cascadeWindowFromTopLeftPoint:self.nextPhotoWindowCascadePoint];
	}

	__weak typeof(self) weak_self = self;
	controller.windowWillCloseHandler = ^(MBPhotoZoomController* closing_controller) {
		MBDetailController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		[strong_self removePhotoWindowController:closing_controller];
	};
	[self.photoZoomControllers addObject:controller];
	[controller showWindowForImageURL:imageURL relatedPostURL:relatedPostURL];
	if (!self.hasNextPhotoWindowCascadePoint) {
		self.nextPhotoWindowCascadePoint = [controller nextWindowCascadeTopLeftPoint];
		self.hasNextPhotoWindowCascadePoint = YES;
	}
}

- (void) applyPreferredTextSettings
{
	if (self.webView == nil) {
		return;
	}

	NSString* background_hex = [self preferredTextBackgroundHex];
	[self updateWebViewUnderPageBackgroundColor];
	NSString* font_css = [self preferredTextFontCSS];
	CGFloat content_font_size = [self preferredTextPointSize];
	CGFloat title_font_size = content_font_size;
	BOOL is_dark_background = [self isDarkColorHexString:background_hex];
	BOOL should_use_dark_reader_highlight = [self shouldUseDarkReaderHighlightBackgroundForBackgroundHex:background_hex];
	NSString* text_color = is_dark_background ? @"#f2f3f5" : @"#1d1d1f";
	NSString* link_color = is_dark_background ? @"#9ec5ff" : @"#0b57d0";
	NSString* quote_color = is_dark_background ? @"#b8c0cc" : @"#4d4d4f";
	NSString* quote_border_color = is_dark_background ? @"#4f5b73" : @"#d2d2d7";
	NSString* reader_highlight_background = should_use_dark_reader_highlight ? InkwellReaderHighlightDarkBackgroundHex : InkwellReaderHighlightLightBackgroundHex;
	NSString* reader_highlight_text = should_use_dark_reader_highlight ? InkwellReaderHighlightDarkTextHex : InkwellReaderHighlightLightTextHex;

	NSDictionary* payload = @{
		@"background_hex": background_hex ?: @"",
		@"font_css": font_css ?: @"",
		@"text_color": text_color ?: @"",
		@"link_color": link_color ?: @"",
		@"quote_color": quote_color ?: @"",
		@"quote_border_color": quote_border_color ?: @"",
		@"reader_highlight_background": reader_highlight_background ?: @"",
		@"reader_highlight_text": reader_highlight_text ?: @"",
		@"content_font_size": @(content_font_size),
		@"title_font_size": @(title_font_size)
	};
	NSString* script = [self javaScriptForRuntimeFunction:@"applyPreferredTextSettings" payload:payload];

	__weak typeof(self) weak_self = self;
	[self.webView evaluateJavaScript:script completionHandler:^(id _Nullable result, NSError * _Nullable error) {
		#pragma unused(result)
		#pragma unused(error)
		MBDetailController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		[strong_self applyReadingRecapColorsForDarkTheme:is_dark_background];
	}];
}

- (NSString*) processedReadingRecapHTML:(NSString*) html
{
	NSString* safe_html = html ?: @"";
	if (safe_html.length == 0) {
		return @"";
	}

	BOOL is_dark_theme = [self isDarkColorHexString:[self preferredTextBackgroundHex]];
	return [self htmlStringByApplyingReadingRecapStyles:safe_html darkTheme:is_dark_theme];
}

- (void) applyReadingRecapColorsForDarkTheme:(BOOL) is_dark_theme
{
	if (self.webView == nil) {
		return;
	}

	NSString* script = [self javaScriptForRuntimeFunction:@"applyReadingRecapColors" payload:@{ @"is_dark_theme": @(is_dark_theme) }];
	[self.webView evaluateJavaScript:script completionHandler:nil];
}

- (NSString*) htmlStringByApplyingReadingRecapStyles:(NSString*) html darkTheme:(BOOL) is_dark_theme
{
	NSError* regex_error = nil;
	NSRegularExpression* recap_regex = [NSRegularExpression regularExpressionWithPattern:@"<div\\b[^>]*\\bclass\\s*=\\s*(['\"])[^'\"]*\\breading-recap\\b[^'\"]*\\1[^>]*>" options:NSRegularExpressionCaseInsensitive error:&regex_error];
	if (recap_regex == nil || regex_error != nil) {
		return html ?: @"";
	}

	NSArray* matches = [recap_regex matchesInString:html options:0 range:NSMakeRange(0, html.length)];
	if (matches.count == 0) {
		return html ?: @"";
	}

	NSMutableString* updated_html = [html mutableCopy];
	for (NSTextCheckingResult* match in [matches reverseObjectEnumerator]) {
		if (match.range.location == NSNotFound || match.range.length == 0) {
			continue;
		}

		NSString* tag = [html substringWithRange:match.range];
		NSString* updated_tag = [self readingRecapTagByApplyingStyles:tag darkTheme:is_dark_theme];
		if (updated_tag.length == 0 || [updated_tag isEqualToString:tag]) {
			continue;
		}

		[updated_html replaceCharactersInRange:match.range withString:updated_tag];
	}

	return updated_html;
}

- (NSString*) readingRecapTagByApplyingStyles:(NSString*) tag darkTheme:(BOOL) is_dark_theme
{
	NSString* light_color = [self normalizedRecapColorString:[self htmlAttributeValue:@"data-color-light" inTag:tag]];
	NSString* dark_color = [self normalizedRecapColorString:[self htmlAttributeValue:@"data-color-dark" inTag:tag]];
	if (dark_color.length == 0) {
		dark_color = [self normalizedRecapColorString:[self htmlAttributeValue:@"data-color-right" inTag:tag]];
	}

	NSString* recap_base_color = is_dark_theme
		? (dark_color.length > 0 ? dark_color : light_color)
		: (light_color.length > 0 ? light_color : dark_color);
	if (recap_base_color.length == 0) {
		return tag ?: @"";
	}

	NSString* recap_background = [self recapColorString:recap_base_color withOpacity:@"80"];
	NSString* recap_topics_background = [self recapColorString:recap_base_color withOpacity:@"e6"];
	NSString* recap_blockquote_background = [self recapColorString:recap_base_color withOpacity:@"99"];
	NSString* recap_blockquote_border = [self recapColorString:recap_base_color withOpacity:@"ff"];

	NSMutableArray* style_parts = [NSMutableArray array];
	if (recap_background.length > 0) {
		[style_parts addObject:[NSString stringWithFormat:@"background-color: %@", recap_background]];
	}
	if (recap_topics_background.length > 0) {
		[style_parts addObject:[NSString stringWithFormat:@"--recap-topics-background: %@", recap_topics_background]];
	}
	if (recap_blockquote_background.length > 0) {
		[style_parts addObject:[NSString stringWithFormat:@"--recap-blockquote-background: %@", recap_blockquote_background]];
	}
	if (recap_blockquote_border.length > 0) {
		[style_parts addObject:[NSString stringWithFormat:@"--recap-blockquote-border: %@", recap_blockquote_border]];
	}
	if (style_parts.count == 0) {
		return tag ?: @"";
	}

	NSString* style_declarations = [[style_parts componentsJoinedByString:@"; "] stringByAppendingString:@";"];
	return [self htmlTag:tag bySettingStyleDeclarations:style_declarations];
}

- (NSString*) htmlAttributeValue:(NSString*) attribute_name inTag:(NSString*) tag
{
	if (attribute_name.length == 0 || tag.length == 0) {
		return @"";
	}

	NSString* escaped_attribute_name = [NSRegularExpression escapedPatternForString:attribute_name];
	NSString* pattern = [NSString stringWithFormat:@"\\b%@\\s*=\\s*(['\"])(.*?)\\1", escaped_attribute_name];
	NSError* regex_error = nil;
	NSRegularExpression* attribute_regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators error:&regex_error];
	if (attribute_regex == nil || regex_error != nil) {
		return @"";
	}

	NSTextCheckingResult* match = [attribute_regex firstMatchInString:tag options:0 range:NSMakeRange(0, tag.length)];
	if (match == nil || match.numberOfRanges < 3 || [match rangeAtIndex:2].location == NSNotFound) {
		return @"";
	}

	return [tag substringWithRange:[match rangeAtIndex:2]];
}

- (NSURL*) baseURLForEntry:(MBEntry* _Nullable) entry
{
	NSString* feed_host = [entry.feedHost stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (feed_host.length == 0) {
		NSURL* post_url = [NSURL URLWithString:(entry.url ?: @"")];
		feed_host = [post_url.host stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	}

	if (feed_host.length == 0) {
		return [NSURL URLWithString:@"https://example.com/"];
	}

	NSURLComponents* components = [[NSURLComponents alloc] init];
	components.scheme = @"https";
	components.host = feed_host;
	components.path = @"/";
	return components.URL ?: [NSURL URLWithString:@"https://example.com/"];
}

- (void) updateWebViewUnderPageBackgroundColor
{
	if (self.webView == nil) {
		return;
	}

	self.webView.underPageBackgroundColor = [self colorFromHexString:[self preferredTextBackgroundHex]];
}

- (NSColor*) colorFromHexString:(NSString*) color_hex
{
	NSString* normalized_hex = [[color_hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
	if ([normalized_hex hasPrefix:@"#"]) {
		normalized_hex = [normalized_hex substringFromIndex:1];
	}
	if (normalized_hex.length != 6) {
		return NSColor.whiteColor;
	}

	unsigned int hex_value = 0;
	NSScanner* scanner = [NSScanner scannerWithString:normalized_hex];
	if (![scanner scanHexInt:&hex_value]) {
		return NSColor.whiteColor;
	}

	CGFloat red = ((hex_value >> 16) & 0xFF) / 255.0;
	CGFloat green = ((hex_value >> 8) & 0xFF) / 255.0;
	CGFloat blue = (hex_value & 0xFF) / 255.0;
	return [NSColor colorWithRed:red green:green blue:blue alpha:1.0];
}

- (NSString*) initialThemeStyleBlockForPosts
{
	NSString* background_hex = [self preferredTextBackgroundHex];
	NSString* font_css = [self preferredTextFontCSS];
	CGFloat content_font_size = [self preferredTextPointSize];
	CGFloat title_font_size = content_font_size;
	BOOL is_dark_background = [self isDarkColorHexString:background_hex];
	BOOL should_use_dark_reader_highlight = [self shouldUseDarkReaderHighlightBackgroundForBackgroundHex:background_hex];
	NSString* text_color = is_dark_background ? @"#f2f3f5" : @"#1d1d1f";
	NSString* link_color = is_dark_background ? @"#9ec5ff" : @"#0b57d0";
	NSString* quote_color = is_dark_background ? @"#b8c0cc" : @"#4d4d4f";
	NSString* quote_border_color = is_dark_background ? @"#4f5b73" : @"#d2d2d7";
	NSString* reader_highlight_background = should_use_dark_reader_highlight ? InkwellReaderHighlightDarkBackgroundHex : InkwellReaderHighlightLightBackgroundHex;
	NSString* reader_highlight_text = should_use_dark_reader_highlight ? InkwellReaderHighlightDarkTextHex : InkwellReaderHighlightLightTextHex;

	return [NSString stringWithFormat:
		@"\n\t\t:root {\n\t\t\t--reader-highlight-background: %@;\n\t\t\t--reader-highlight-text: %@;\n\t\t}\n"
		"\t\thtml, body {\n\t\t\tbackground-color: %@;\n\t\t\tcolor: %@;\n\t\t}\n"
		"\t\tbody, .content {\n\t\t\tfont-family: %@;\n\t\t\tfont-size: %.2fpx;\n\t\t}\n"
		"\t\t.post-title {\n\t\t\tfont-family: %@;\n\t\t\tfont-size: %.2fpx;\n\t\t\tcolor: %@;\n\t\t}\n"
		"\t\t.post-content, p, li, td, th, pre {\n\t\t\tfont-family: %@;\n\t\t\tfont-size: %.2fpx;\n\t\t\tcolor: %@;\n\t\t}\n"
		"\t\tblockquote {\n\t\t\tcolor: %@;\n\t\t\tborder-left-color: %@;\n\t\t}\n"
		"\t\ta {\n\t\t\tcolor: %@;\n\t\t}\n",
		reader_highlight_background,
		reader_highlight_text,
		background_hex,
		text_color,
		font_css,
		content_font_size,
		font_css,
		title_font_size,
		text_color,
		font_css,
		content_font_size,
		text_color,
		quote_color,
		quote_border_color,
		link_color
	];
}

- (NSString*) initialThemeStyleBlockForReadingRecap
{
	NSString* background_hex = [self preferredTextBackgroundHex];
	NSString* font_css = [self preferredTextFontCSS];
	CGFloat content_font_size = [self preferredTextPointSize];
	BOOL is_dark_background = [self isDarkColorHexString:background_hex];
	NSString* text_color = is_dark_background ? @"#f2f3f5" : @"#1d1d1f";
	NSString* link_color = is_dark_background ? @"#9ec5ff" : @"#0b57d0";

	return [NSString stringWithFormat:
		@"\n\t\thtml, body {\n\t\t\tbackground-color: %@;\n\t\t\tcolor: %@;\n\t\t}\n"
		"\t\tbody, .content, .reading-recap {\n\t\t\tfont-family: %@;\n\t\t\tfont-size: %.2fpx;\n\t\t\tcolor: %@;\n\t\t}\n"
		"\t\t.reading-recap a {\n\t\t\tcolor: %@;\n\t\t}\n",
		background_hex,
		text_color,
		font_css,
		content_font_size,
		text_color,
		link_color
	];
}

- (NSString*) htmlTag:(NSString*) tag bySettingStyleDeclarations:(NSString*) style_declarations
{
	if (tag.length == 0 || style_declarations.length == 0) {
		return tag ?: @"";
	}

	NSString* existing_style = [self htmlAttributeValue:@"style" inTag:tag];
	NSMutableString* combined_style = [NSMutableString string];
	if (existing_style.length > 0) {
		[combined_style appendString:existing_style];
		NSString* trimmed_style = [existing_style stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (trimmed_style.length > 0 && ![trimmed_style hasSuffix:@";"]) {
			[combined_style appendString:@";"];
		}
		if (combined_style.length > 0 && ![[combined_style substringFromIndex:combined_style.length - 1] isEqualToString:@" "]) {
			[combined_style appendString:@" "];
		}
	}
	[combined_style appendString:style_declarations];

	NSString* escaped_style = [self escapedHTMLString:combined_style];
	NSString* replacement_attribute = [NSString stringWithFormat:@"style=\"%@\"", escaped_style];

	NSError* regex_error = nil;
	NSRegularExpression* style_regex = [NSRegularExpression regularExpressionWithPattern:@"\\bstyle\\s*=\\s*(['\"])(.*?)\\1" options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators error:&regex_error];
	if (style_regex != nil && regex_error == nil) {
		NSTextCheckingResult* match = [style_regex firstMatchInString:tag options:0 range:NSMakeRange(0, tag.length)];
		if (match != nil && match.range.location != NSNotFound) {
			NSMutableString* updated_tag = [tag mutableCopy];
			[updated_tag replaceCharactersInRange:match.range withString:replacement_attribute];
			return updated_tag;
		}
	}

	NSRange closing_bracket_range = [tag rangeOfString:@">" options:NSBackwardsSearch];
	if (closing_bracket_range.location == NSNotFound) {
		return tag ?: @"";
	}

	NSMutableString* updated_tag = [tag mutableCopy];
	NSString* inserted_attribute = [NSString stringWithFormat:@" %@", replacement_attribute];
	[updated_tag insertString:inserted_attribute atIndex:closing_bracket_range.location];
	return updated_tag;
}

- (NSString*) normalizedRecapColorString:(NSString*) color_hex
{
	NSString* normalized_color = [[color_hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
	if (normalized_color.length == 0 || ![normalized_color hasPrefix:@"#"]) {
		return @"";
	}

	NSString* hex_string = [normalized_color substringFromIndex:1];
	if (hex_string.length != 3 && hex_string.length != 4 && hex_string.length != 6 && hex_string.length != 8) {
		return @"";
	}

	NSCharacterSet* hex_character_set = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"];
	if ([[hex_string stringByTrimmingCharactersInSet:hex_character_set] length] > 0) {
		return @"";
	}

	if (hex_string.length == 3 || hex_string.length == 4) {
		NSMutableString* expanded_hex = [NSMutableString string];
		for (NSUInteger i = 0; i < hex_string.length; i++) {
			unichar character = [hex_string characterAtIndex:i];
			[expanded_hex appendFormat:@"%C%C", character, character];
		}
		hex_string = expanded_hex;
	}

	return [NSString stringWithFormat:@"#%@", hex_string];
}

- (NSString*) recapColorString:(NSString*) color_hex withOpacity:(NSString*) opacity_hex
{
	NSString* normalized_color = [self normalizedRecapColorString:color_hex];
	if (normalized_color.length == 0) {
		return @"";
	}

	NSString* base_color = normalized_color.length == 9
		? [normalized_color substringToIndex:7]
		: normalized_color;
	NSString* normalized_opacity = [[opacity_hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
	NSCharacterSet* hex_character_set = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"];
	if (normalized_opacity.length != 2 || [[normalized_opacity stringByTrimmingCharactersInSet:hex_character_set] length] > 0) {
		normalized_opacity = @"80";
	}

	return [base_color stringByAppendingString:normalized_opacity];
}

- (NSString*) htmlForPostTitle:(NSString*) title author:(NSString*) author siteTitle:(NSString*) site_title content:(NSString*) content
{
	NSString* template_html = [self postHTMLTemplate];
	NSString* themed_template_html = [template_html stringByReplacingOccurrencesOfString:InkwellInitialThemeStyleToken withString:[self initialThemeStyleBlockForPosts]];
	NSString* safe_title = title ?: @"";
	NSString* raw_author = author ?: @"";
	NSString* safe_content = content ?: @"";
	NSString* html = [themed_template_html stringByReplacingOccurrencesOfString:InkwellPostTitleToken withString:safe_title];
	NSString* trimmed_author = [raw_author stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	NSString* trimmed_site_title = [site_title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	NSString* safe_author = [self escapedHTMLString:trimmed_author];
	BOOL should_hide_author = (trimmed_author.length == 0);
	if (!should_hide_author && trimmed_site_title.length > 0) {
		should_hide_author = ([trimmed_author localizedCaseInsensitiveCompare:trimmed_site_title] == NSOrderedSame);
	}

	html = [html stringByReplacingOccurrencesOfString:InkwellPostAuthorToken withString:(should_hide_author ? @"" : safe_author)];
	return [html stringByReplacingOccurrencesOfString:InkwellPostContentToken withString:safe_content];
}

- (NSString*) htmlForReadingRecapContent:(NSString*) content
{
	NSString* template_html = [self recapHTMLTemplate];
	NSString* themed_template_html = [template_html stringByReplacingOccurrencesOfString:InkwellInitialThemeStyleToken withString:[self initialThemeStyleBlockForReadingRecap]];
	NSString* safe_content = content ?: @"";
	return [themed_template_html stringByReplacingOccurrencesOfString:InkwellPostContentToken withString:safe_content];
}

- (NSString *) postHTMLTemplate
{
	static NSString* cached_template;
	static dispatch_once_t once_token;
	dispatch_once(&once_token, ^{
		NSString* path = [[NSBundle mainBundle] pathForResource:InkwellPostTemplateName ofType:InkwellPostTemplateType];
		if (path.length > 0) {
			cached_template = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
		}
	});

	return cached_template;
}

- (NSString*) recapHTMLTemplate
{
	static NSString* cached_template;
	static dispatch_once_t once_token;
	dispatch_once(&once_token, ^{
		NSString* path = [[NSBundle mainBundle] pathForResource:InkwellRecapTemplateName ofType:InkwellPostTemplateType];
		if (path.length > 0) {
			cached_template = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
		}
	});

	return cached_template;
}

- (NSString *) bundledJavaScriptNamed:(NSString*) script_name
{
	static NSMutableDictionary* cached_scripts;
	static dispatch_once_t once_token;
	dispatch_once(&once_token, ^{
		cached_scripts = [NSMutableDictionary dictionary];
	});

	if (script_name.length == 0) {
		return @"";
	}

	@synchronized (cached_scripts) {
		NSString* cached_script = cached_scripts[script_name];
		if (cached_script != nil) {
			return cached_script;
		}

		NSString* path = [[NSBundle mainBundle] pathForResource:script_name ofType:@"js"];
		NSString* script_source = @"";
		if (path.length > 0) {
			script_source = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
		}
		cached_scripts[script_name] = script_source;
		return script_source;
	}
}

- (NSString *) detailRuntimeScript
{
	return [self bundledJavaScriptNamed:@"detail_runtime"];
}

- (NSString*) selectionObserverScript
{
	return [self bundledJavaScriptNamed:@"detail_selection_observer"];
}

- (NSString*) readingRecapAvatarFallbackScript
{
	return [self bundledJavaScriptNamed:@"detail_recap_avatar_fallback"];
}

- (NSString*) scrollObserverScript
{
	return [self bundledJavaScriptNamed:@"detail_scroll_observer"];
}

- (NSString*) linkHoverObserverScript
{
	return [self bundledJavaScriptNamed:@"detail_link_hover_observer"];
}

- (NSString*) imageClickObserverScript
{
	return [self bundledJavaScriptNamed:@"detail_image_click_observer"];
}

- (NSString *) javaScriptForRuntimeFunction:(NSString*) function_name payload:(id _Nullable) payload
{
	NSString* payload_json = [self jsonStringForJavaScriptObject:payload];
	return [NSString stringWithFormat:@"window.inkwellDetail ? window.inkwellDetail.%@(%@) : null;", function_name, payload_json];
}

- (NSString *) jsonStringForJavaScriptObject:(id _Nullable) object
{
	if (object == nil) {
		return @"null";
	}

	NSData* json_data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
	if (json_data.length == 0) {
		return @"null";
	}

	NSString* json_string = [[NSString alloc] initWithData:json_data encoding:NSUTF8StringEncoding];
	return json_string.length > 0 ? json_string : @"null";
}

- (void) updateSelectionState:(BOOL) has_selection
{
	if (self.hasTextSelection == has_selection) {
		return;
	}

	self.hasTextSelection = has_selection;
	if (self.selectionChangedHandler != nil) {
		self.selectionChangedHandler(has_selection);
	}
}

- (void) updateTopBarMaterialForScrolledDown:(BOOL) is_scrolled_down
{
	if (self.topBarView == nil) {
		return;
	}
	
	if (self.isTopBarMaterialVisible == is_scrolled_down) {
		return;
	}

	self.isTopBarMaterialVisible = is_scrolled_down;
	self.topBarAnimationID += 1;
	NSInteger animation_id = self.topBarAnimationID;
	CGFloat target_alpha = is_scrolled_down ? 1.0 : 0.0;

	[NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
		context.duration = 0.3;
		self.topBarView.animator.alphaValue = target_alpha;
	} completionHandler:^{
		if (animation_id != self.topBarAnimationID) {
			return;
		}

		self.topBarView.alphaValue = self.isTopBarMaterialVisible ? 1.0 : 0.0;
	}];
}

- (NSString*) preferredTextBackgroundHex
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	if ([defaults objectForKey:InkwellTextBackgroundColorDefaultsKey] == nil) {
		return [self prefersDarkSystemAppearance] ? @"#000000" : InkwellDefaultTextBackgroundHex;
	}

	NSString* stored_hex = [defaults stringForKey:InkwellTextBackgroundColorDefaultsKey] ?: @"";
	NSString* normalized_hex = [stored_hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if ([self isValidHexColorString:normalized_hex]) {
		return normalized_hex;
	}

	return InkwellDefaultTextBackgroundHex;
}

- (BOOL) hasStoredTextBackgroundPreference
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	return ([defaults objectForKey:InkwellTextBackgroundColorDefaultsKey] != nil);
}

- (BOOL) shouldUseDarkReaderHighlightBackgroundForBackgroundHex:(NSString*) background_hex
{
	NSString* normalized_hex = [[background_hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString] ?: @"";
	if (normalized_hex.length == 0) {
		return NO;
	}

	if (![self hasStoredTextBackgroundPreference]) {
		return [self isDarkColorHexString:normalized_hex];
	}

	return ([normalized_hex isEqualToString:InkwellPreferencesDarkBlueBackgroundHex] ||
		[normalized_hex isEqualToString:InkwellPreferencesBlackBackgroundHex]);
}

- (BOOL) prefersDarkSystemAppearance
{
	NSAppearance* appearance = nil;
	if (self.isViewLoaded) {
		appearance = self.view.effectiveAppearance;
	}
	if (appearance == nil) {
		appearance = self.webView.effectiveAppearance ?: NSApp.effectiveAppearance;
	}
	if (appearance != nil) {
		NSAppearanceName matched_appearance = [appearance bestMatchFromAppearancesWithNames:@[
			NSAppearanceNameAqua,
			NSAppearanceNameDarkAqua
		]];
		if ([matched_appearance isEqualToString:NSAppearanceNameDarkAqua]) {
			return YES;
		}
		if ([matched_appearance isEqualToString:NSAppearanceNameAqua]) {
			return NO;
		}
	}

	return [self systemInterfaceStyleIsDark];
}

- (BOOL) systemInterfaceStyleIsDark
{
	NSString* interface_style = [[NSUserDefaults standardUserDefaults] stringForKey:@"AppleInterfaceStyle"] ?: @"";
	NSString* normalized_style = [interface_style stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	return ([normalized_style caseInsensitiveCompare:@"Dark"] == NSOrderedSame);
}

- (NSString*) preferredTextFontCSS
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	NSString* font_name = [defaults stringForKey:InkwellTextFontNameDefaultsKey] ?: @"";
	NSString* normalized_font_name = [font_name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (normalized_font_name.length == 0) {
		normalized_font_name = InkwellDefaultTextFontName;
	}

	if ([normalized_font_name isEqualToString:@"Avenir Next"]) {
		return @"'Avenir Next', 'Avenir', sans-serif";
	}
	if ([normalized_font_name isEqualToString:@"Times New Roman"]) {
		return @"'Times New Roman', 'Times', serif";
	}

	return @"-apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif";
}

- (CGFloat) preferredTextPointSize
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	NSString* size_name = [defaults stringForKey:InkwellTextSizeNameDefaultsKey] ?: @"";
	NSString* normalized_size_name = [size_name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (normalized_size_name.length == 0) {
		normalized_size_name = InkwellDefaultTextSizeName;
	}

	if ([normalized_size_name isEqualToString:@"Tiny"]) {
		return 13.0;
	}
	if ([normalized_size_name isEqualToString:@"Small"]) {
		return 15.0;
	}
	if ([normalized_size_name isEqualToString:@"Large"]) {
		return 19.0;
	}
	if ([normalized_size_name isEqualToString:@"Huge"]) {
		return 22.0;
	}

	return 17.0;
}

- (BOOL) isValidHexColorString:(NSString*) color_hex
{
	NSString* normalized_hex = [[color_hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
	if ([normalized_hex hasPrefix:@"#"]) {
		normalized_hex = [normalized_hex substringFromIndex:1];
	}
	if (normalized_hex.length != 6) {
		return NO;
	}

	NSScanner* scanner = [NSScanner scannerWithString:normalized_hex];
	unsigned int rgb_value = 0;
	return [scanner scanHexInt:&rgb_value];
}

- (BOOL) isDarkColorHexString:(NSString*) color_hex
{
	NSString* normalized_hex = [[color_hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
	if ([normalized_hex hasPrefix:@"#"]) {
		normalized_hex = [normalized_hex substringFromIndex:1];
	}
	if (normalized_hex.length != 6) {
		return NO;
	}

	unsigned int rgb_value = 0;
	NSScanner* scanner = [NSScanner scannerWithString:normalized_hex];
	BOOL did_scan = [scanner scanHexInt:&rgb_value];
	if (!did_scan) {
		return NO;
	}

	CGFloat red = ((rgb_value >> 16) & 0xFF) / 255.0;
	CGFloat green = ((rgb_value >> 8) & 0xFF) / 255.0;
	CGFloat blue = (rgb_value & 0xFF) / 255.0;
	CGFloat luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue);
	return (luminance < 0.45);
}

- (NSString *) escapedHTMLString:(NSString *)string
{
	if (string.length == 0) {
		return @"";
	}

	NSMutableString *escaped = [string mutableCopy];
	[escaped replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, escaped.length)];
	[escaped replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, escaped.length)];
	[escaped replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, escaped.length)];
	[escaped replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, escaped.length)];
	[escaped replaceOccurrencesOfString:@"'" withString:@"&#39;" options:0 range:NSMakeRange(0, escaped.length)];
	return escaped;
}

@end
