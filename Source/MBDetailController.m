//
//  MBDetailController.m
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import "MBDetailController.h"
#import "MBClient.h"
#import "MBEntry.h"
#import "MBHighlight.h"
#import <WebKit/WebKit.h>

static CGFloat const InkwellDetailTopBarHeight = 52.0;
static NSString* const InkwellPostTemplateName = @"PostTemplate";
static NSString* const InkwellRecapTemplateName = @"RecapTemplate";
static NSString* const InkwellPostTemplateType = @"html";
static NSString* const InkwellPostTitleToken = @"[TITLE]";
static NSString* const InkwellPostContentToken = @"[CONTENT]";
static NSString* const InkwellSelectionChangedScriptMessageName = @"selectionChanged";
static NSString* const InkwellDefaultTextBackgroundHex = @"#ffffff";
static NSString* const InkwellDefaultTextFontName = @"San Francisco";
static NSString* const InkwellDefaultTextSizeName = @"Medium";

@interface MBDetailWebView : WKWebView

@property (copy, nullable) BOOL (^focusSidebarHandler)(void);

@end

@implementation MBDetailWebView

- (void) keyDown:(NSEvent*) event
{
	NSString* characters = event.charactersIgnoringModifiers ?: @"";
	if (characters.length > 0) {
		unichar key_code = [characters characterAtIndex:0];
		NSEventModifierFlags modifier_flags = (event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask);
		BOOL has_disallowed_modifiers = ((modifier_flags & (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl | NSEventModifierFlagShift)) != 0);
		BOOL is_left_arrow_key = (key_code == NSLeftArrowFunctionKey);
		if (!has_disallowed_modifiers && is_left_arrow_key && self.focusSidebarHandler != nil && self.focusSidebarHandler()) {
			return;
		}
	}

	[super keyDown:event];
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

@interface MBDetailController () <WKNavigationDelegate, WKScriptMessageHandler>

@property (strong) MBDetailWebView* webView;
@property (strong) MBWeakScriptMessageHandler* selectionScriptMessageHandler;
@property (assign) BOOL hasTextSelection;
@property (assign) NSInteger currentEntryID;

@end

@implementation MBDetailController

- (void) loadView
{
	NSView *root_view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 780.0, 600.0)];
	root_view.translatesAutoresizingMaskIntoConstraints = NO;

	NSVisualEffectView *top_bar_view = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
	top_bar_view.translatesAutoresizingMaskIntoConstraints = NO;
	top_bar_view.blendingMode = NSVisualEffectBlendingModeWithinWindow;
	top_bar_view.material = NSVisualEffectMaterialHeaderView;
	top_bar_view.state = NSVisualEffectStateActive;

	WKUserContentController* user_content_controller = [[WKUserContentController alloc] init];
	self.selectionScriptMessageHandler = [[MBWeakScriptMessageHandler alloc] initWithTarget:self];
	[user_content_controller addScriptMessageHandler:self.selectionScriptMessageHandler name:InkwellSelectionChangedScriptMessageName];

	WKUserScript* selection_script = [[WKUserScript alloc] initWithSource:[self selectionObserverScript] injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
	[user_content_controller addUserScript:selection_script];

	WKWebViewConfiguration* configuration = [[WKWebViewConfiguration alloc] init];
	configuration.userContentController = user_content_controller;

	MBDetailWebView* web_view = [[MBDetailWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
	web_view.translatesAutoresizingMaskIntoConstraints = NO;
	web_view.navigationDelegate = self;
	__weak typeof(self) weak_self = self;
	web_view.focusSidebarHandler = ^BOOL {
		MBDetailController* strong_self = weak_self;
		if (strong_self == nil || strong_self.focusSidebarHandler == nil) {
			return NO;
		}

		return strong_self.focusSidebarHandler();
	};
	[root_view addSubview:web_view];
	[root_view addSubview:top_bar_view];
	[NSLayoutConstraint activateConstraints:@[
		[top_bar_view.topAnchor constraintEqualToAnchor:root_view.topAnchor],
		[top_bar_view.leadingAnchor constraintEqualToAnchor:root_view.leadingAnchor],
		[top_bar_view.trailingAnchor constraintEqualToAnchor:root_view.trailingAnchor],
		[top_bar_view.heightAnchor constraintEqualToConstant:InkwellDetailTopBarHeight],
		[web_view.topAnchor constraintEqualToAnchor:root_view.topAnchor],
		[web_view.bottomAnchor constraintEqualToAnchor:root_view.bottomAnchor],
		[web_view.leadingAnchor constraintEqualToAnchor:root_view.leadingAnchor],
		[web_view.trailingAnchor constraintEqualToAnchor:root_view.trailingAnchor]
	]];

	self.webView = web_view;
	self.view = root_view;
}

- (void) dealloc
{
	[self.webView.configuration.userContentController removeScriptMessageHandlerForName:InkwellSelectionChangedScriptMessageName];
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

- (void) webView:(WKWebView *)web_view decidePolicyForNavigationAction:(WKNavigationAction *)navigation_action decisionHandler:(void (^)(WKNavigationActionPolicy))decision_handler
{
	#pragma unused(web_view)
	NSURL* request_url = navigation_action.request.URL;
	BOOL is_link_activated = (navigation_action.navigationType == WKNavigationTypeLinkActivated);
	if (!is_link_activated || request_url == nil) {
		decision_handler(WKNavigationActionPolicyAllow);
		return;
	}

	[[NSWorkspace sharedWorkspace] openURL:request_url];
	decision_handler(WKNavigationActionPolicyCancel);
}

- (void) webView:(WKWebView*) web_view didFinishNavigation:(WKNavigation*) navigation
{
	#pragma unused(web_view)
	#pragma unused(navigation)
	[self refreshHighlights];
	[self applyPreferredTextSettings];
}

- (void) showSidebarItem:(MBEntry * _Nullable)item
{
	[self updateSelectionState:NO];

	if (item == nil) {
		self.currentEntryID = 0;
		NSString* html = [self htmlForPostTitle:@"" content:@""];
		[self.webView loadHTMLString:html baseURL:[NSBundle mainBundle].resourceURL];
		return;
	}

	self.currentEntryID = item.entryID;

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

	NSString* html = [self htmlForPostTitle:safe_title content:content_value];
	[self.webView loadHTMLString:html baseURL:[NSBundle mainBundle].resourceURL];
}

- (void) showReadingRecapHTML:(NSString*) html
{
	[self updateSelectionState:NO];
	self.currentEntryID = 0;

	NSString* processed_html = [self processedReadingRecapHTML:html ?: @""];
	NSString* recap_html = [self htmlForReadingRecapContent:processed_html];
	[self.webView loadHTMLString:recap_html baseURL:[NSBundle mainBundle].resourceURL];
}

- (void) userContentController:(WKUserContentController *)user_content_controller didReceiveScriptMessage:(WKScriptMessage *)script_message
{
	#pragma unused(user_content_controller)

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
	NSString* script = @"(window.inkwellHighlights && window.inkwellHighlights.getSelectionPayload) ? window.inkwellHighlights.getSelectionPayload() : null;";
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
	NSString* script = @"if (window.inkwellHighlights && window.inkwellHighlights.clearSelection) { window.inkwellHighlights.clearSelection(); }";
	[self.webView evaluateJavaScript:script completionHandler:nil];
	[self updateSelectionState:NO];
}

- (void) refreshHighlights
{
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

		NSDictionary* dictionary = @{
			@"start_offset": @(start_offset),
			@"end_offset": @(end_offset)
		};
		[range_payload addObject:dictionary];
	}

	NSData* json_data = [NSJSONSerialization dataWithJSONObject:range_payload options:0 error:nil];
	NSString* json_string = @"[]";
	if (json_data.length > 0) {
		NSString* parsed_string = [[NSString alloc] initWithData:json_data encoding:NSUTF8StringEncoding];
		if (parsed_string.length > 0) {
			json_string = parsed_string;
		}
	}

	NSString* script = [NSString stringWithFormat:@"if (window.inkwellHighlights && window.inkwellHighlights.restoreHighlights) { window.inkwellHighlights.restoreHighlights(%@); }", json_string];
	[self.webView evaluateJavaScript:script completionHandler:nil];
}

- (void) applyPreferredTextSettings
{
	if (self.webView == nil) {
		return;
	}

	NSString* background_hex = [self preferredTextBackgroundHex];
	NSString* font_css = [self preferredTextFontCSS];
	CGFloat content_font_size = [self preferredTextPointSize];
	CGFloat title_font_size = content_font_size;
	BOOL is_dark_background = [self isDarkColorHexString:background_hex];
	NSString* text_color = is_dark_background ? @"#f2f3f5" : @"#1d1d1f";
	NSString* link_color = is_dark_background ? @"#9ec5ff" : @"#0b57d0";
	NSString* quote_color = is_dark_background ? @"#b8c0cc" : @"#4d4d4f";
	NSString* quote_border_color = is_dark_background ? @"#4f5b73" : @"#d2d2d7";

	NSString* escaped_background_hex = [self escapedJavaScriptString:background_hex];
	NSString* escaped_font_css = [self escapedJavaScriptString:font_css];
	NSString* escaped_text_color = [self escapedJavaScriptString:text_color];
	NSString* escaped_link_color = [self escapedJavaScriptString:link_color];
	NSString* escaped_quote_color = [self escapedJavaScriptString:quote_color];
	NSString* escaped_quote_border_color = [self escapedJavaScriptString:quote_border_color];

	NSString* script = [NSString stringWithFormat:@"(function(){"
		"var bg='%@';"
		"var font='%@';"
		"var text='%@';"
		"var link='%@';"
		"var quote='%@';"
		"var quoteBorder='%@';"
		"var contentSize=%0.2f;"
		"var titleSize=%0.2f;"
		"var body=document.body;"
		"if(!body){return;}"
		"body.style.backgroundColor=bg;"
		"body.style.color=text;"
		"body.style.fontFamily=font;"
		"body.style.fontSize=contentSize+'px';"
		"var content=document.querySelector('.content');"
		"if(content){content.style.fontFamily=font;content.style.fontSize=contentSize+'px';}"
		"var titleNodes=document.querySelectorAll('.post-title');"
		"for(var t=0;t<titleNodes.length;t++){"
			"titleNodes[t].style.fontFamily=font;"
			"titleNodes[t].style.fontSize=titleSize+'px';"
			"titleNodes[t].style.color=text;"
		"}"
		"var nodes=document.querySelectorAll('.post-content,p,li,td,th,pre,blockquote');"
		"for(var i=0;i<nodes.length;i++){"
			"nodes[i].style.fontFamily=font;"
			"nodes[i].style.fontSize=contentSize+'px';"
			"nodes[i].style.color=text;"
		"}"
		"var links=document.querySelectorAll('a');"
		"for(var j=0;j<links.length;j++){links[j].style.color=link;}"
		"var quotes=document.querySelectorAll('blockquote');"
		"for(var k=0;k<quotes.length;k++){"
			"quotes[k].style.color=quote;"
			"quotes[k].style.borderLeftColor=quoteBorder;"
		"}"
		"})();",
		escaped_background_hex,
		escaped_font_css,
		escaped_text_color,
		escaped_link_color,
		escaped_quote_color,
		escaped_quote_border_color,
		content_font_size,
		title_font_size];

	[self.webView evaluateJavaScript:script completionHandler:nil];
}

- (NSString*) processedReadingRecapHTML:(NSString*) html
{
	// Placeholder for future recap-specific HTML processing (e.g. JS/CSS transforms).
	return html ?: @"";
}

- (NSString *) htmlForPostTitle:(NSString *)title content:(NSString *)content
{
	NSString* template_html = [self postHTMLTemplate];
	NSString* safe_title = title ?: @"";
	NSString* safe_content = content ?: @"";
	NSString* html = [template_html stringByReplacingOccurrencesOfString:InkwellPostTitleToken withString:safe_title];
	return [html stringByReplacingOccurrencesOfString:InkwellPostContentToken withString:safe_content];
}

- (NSString*) htmlForReadingRecapContent:(NSString*) content
{
	NSString* template_html = [self recapHTMLTemplate];
	NSString* safe_content = content ?: @"";
	return [template_html stringByReplacingOccurrencesOfString:InkwellPostContentToken withString:safe_content];
}

- (NSString *) postHTMLTemplate
{
	static NSString* cached_template;
	static dispatch_once_t once_token;
	dispatch_once(&once_token, ^{
		NSString* path = [[NSBundle mainBundle] pathForResource:InkwellPostTemplateName ofType:InkwellPostTemplateType];
		if (path.length > 0) {
			NSError* read_error = nil;
			NSString* template_html = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&read_error];
			if (template_html.length > 0) {
				cached_template = template_html;
			}
		}

		if (cached_template.length == 0) {
			cached_template = @"<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;margin:0;margin-top:40px;padding:40px;color:#1d1d1f;}.content{max-width:600px;margin-left:auto;margin-right:auto;}.post-title{font-size:30px;line-height:1.2;margin:0 0 12px;}.post-title:empty{display:none;}.post-content{font-size:16px;line-height:1.6;}.post-content:empty{display:none;}p{font-size:16px;line-height:1.5;color:#1d1d1f;}img,video{max-width:100%%;height:auto;}pre{white-space:pre-wrap;}blockquote{border-left:3px solid #d2d2d7;margin:1em 0;padding-left:1em;color:#4d4d4f;}</style></head><body><div class='content'><h1 class='post-title'>[TITLE]</h1><article class='post-content'>[CONTENT]</article></div></body></html>";
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
			NSError* read_error = nil;
			NSString* template_html = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&read_error];
			if (template_html.length > 0) {
				cached_template = template_html;
			}
		}

		if (cached_template.length == 0) {
			cached_template = @"<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;margin:0;margin-top:40px;padding:40px;color:#1d1d1f;}.content{max-width:680px;margin-left:auto;margin-right:auto;}img,video{max-width:100%%;height:auto;}pre{white-space:pre-wrap;}</style></head><body><div class='content'>[CONTENT]</div></body></html>";
		}
	});

	return cached_template;
}

- (NSString*) selectionObserverScript
{
	return @"(function() {"
		"if (window.__inkwellSelectionObserverInstalled) { return; }"
		"window.__inkwellSelectionObserverInstalled = true;"
		"function postSelectionState() {"
			"var selection = window.getSelection();"
			"var hasSelection = false;"
			"if (selection && !selection.isCollapsed && selection.rangeCount > 0 && selection.toString().trim().length > 0) {"
				"var content = document.querySelector('.post-content');"
				"if (content) {"
					"var range = selection.getRangeAt(0);"
					"hasSelection = content.contains(range.commonAncestorContainer);"
				"}"
			"}"
			"window.webkit.messageHandlers.selectionChanged.postMessage(hasSelection);"
		"}"
		"document.addEventListener('selectionchange', postSelectionState);"
		"document.addEventListener('mouseup', postSelectionState);"
		"document.addEventListener('keyup', postSelectionState);"
		"window.addEventListener('load', postSelectionState);"
		"postSelectionState();"
		"})();";
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

- (NSString*) preferredTextBackgroundHex
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	NSString* stored_hex = [defaults stringForKey:InkwellTextBackgroundColorDefaultsKey] ?: @"";
	NSString* normalized_hex = [stored_hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if ([self isValidHexColorString:normalized_hex]) {
		return normalized_hex;
	}

	return InkwellDefaultTextBackgroundHex;
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

- (NSString*) escapedJavaScriptString:(NSString*) string
{
	NSString* escaped_string = [string stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
	escaped_string = [escaped_string stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
	escaped_string = [escaped_string stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
	escaped_string = [escaped_string stringByReplacingOccurrencesOfString:@"\r" withString:@""];
	return escaped_string ?: @"";
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
