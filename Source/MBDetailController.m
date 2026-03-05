//
//  MBDetailController.m
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import "MBDetailController.h"
#import "MBEntry.h"
#import <WebKit/WebKit.h>

static CGFloat const InkwellDetailTopBarHeight = 52.0;
static NSString* const InkwellPostTemplateName = @"PostTemplate";
static NSString* const InkwellRecapTemplateName = @"RecapTemplate";
static NSString* const InkwellPostTemplateType = @"html";
static NSString* const InkwellPostTitleToken = @"[TITLE]";
static NSString* const InkwellPostContentToken = @"[CONTENT]";

@interface MBDetailController () <WKNavigationDelegate>

@property (strong) WKWebView* webView;

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

	WKWebView* web_view = [[WKWebView alloc] initWithFrame:NSZeroRect];
	web_view.translatesAutoresizingMaskIntoConstraints = NO;
	web_view.navigationDelegate = self;
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

- (void) showSidebarItem:(MBEntry * _Nullable)item
{
	if (item == nil) {
		NSString* html = [self htmlForPostTitle:@"" content:@""];
		[self.webView loadHTMLString:html baseURL:[NSBundle mainBundle].resourceURL];
		return;
	}

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
	NSString* processed_html = [self processedReadingRecapHTML:html ?: @""];
	NSString* recap_html = [self htmlForReadingRecapContent:processed_html];
	[self.webView loadHTMLString:recap_html baseURL:[NSBundle mainBundle].resourceURL];
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
