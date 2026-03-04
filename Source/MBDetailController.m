//
//  MBDetailController.m
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import "MBDetailController.h"
#import "MBEntry.h"
#import <WebKit/WebKit.h>

@interface MBDetailController ()

@property (strong) WKWebView *webView;

@end

@implementation MBDetailController

- (void) loadView
{
	NSView *root_view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 780.0, 600.0)];
	root_view.translatesAutoresizingMaskIntoConstraints = NO;

	NSView *container_view = [[NSView alloc] initWithFrame:NSZeroRect];
	container_view.translatesAutoresizingMaskIntoConstraints = NO;
	[root_view addSubview:container_view];

	[NSLayoutConstraint activateConstraints:@[
		[container_view.topAnchor constraintEqualToAnchor:root_view.topAnchor],
		[container_view.bottomAnchor constraintEqualToAnchor:root_view.bottomAnchor],
		[container_view.leadingAnchor constraintEqualToAnchor:root_view.leadingAnchor],
		[container_view.trailingAnchor constraintEqualToAnchor:root_view.trailingAnchor]
	]];

	WKWebView *web_view = [[WKWebView alloc] initWithFrame:NSZeroRect];
	web_view.translatesAutoresizingMaskIntoConstraints = NO;
	[container_view addSubview:web_view];
	[NSLayoutConstraint activateConstraints:@[
		[web_view.topAnchor constraintEqualToAnchor:container_view.topAnchor],
		[web_view.bottomAnchor constraintEqualToAnchor:container_view.bottomAnchor],
		[web_view.leadingAnchor constraintEqualToAnchor:container_view.leadingAnchor],
		[web_view.trailingAnchor constraintEqualToAnchor:container_view.trailingAnchor]
	]];

	self.webView = web_view;
	self.view = root_view;
}

- (void) showSidebarItem:(MBEntry * _Nullable)item
{
	if (item == nil) {
		NSString *placeholder_html = @"<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;margin:0;padding:40px;color:#1d1d1f;}h1{font-size:30px;line-height:1.2;margin:0 0 12px;}p{font-size:16px;line-height:1.5;color:#1d1d1f;max-width:760px;}</style></head><body><h1>Select a source item</h1><p>Pick an item from the sidebar.</p></body></html>";
		[self.webView loadHTMLString:placeholder_html baseURL:nil];
		return;
	}

	NSString *safe_title = [self escapedHTMLString:item.title ?: @""];
	NSString *entry_html = item.text ?: @"";
	if (entry_html.length > 0) {
		NSString *title_html = @"";
		if (safe_title.length > 0) {
			title_html = [NSString stringWithFormat:@"<h1>%@</h1>", safe_title];
		}

		NSString *html = [NSString stringWithFormat:
			@"<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;margin:0;padding:40px;color:#1d1d1f;}h1{font-size:30px;line-height:1.2;margin:0 0 12px;}article{font-size:16px;line-height:1.6;max-width:760px;}img,video{max-width:100%%;height:auto;}pre{white-space:pre-wrap;}blockquote{border-left:3px solid #d2d2d7;margin:1em 0;padding-left:1em;color:#4d4d4f;}</style></head><body>%@<article>%@</article></body></html>",
			title_html,
			entry_html];

		[self.webView loadHTMLString:html baseURL:nil];
		return;
	}

	NSString *fallback_text = item.summary;
	if (fallback_text.length == 0) {
		fallback_text = item.source;
	}
	if (fallback_text.length == 0) {
		fallback_text = @"No content.";
	}

	NSString *safe_fallback = [self escapedHTMLString:fallback_text];
	NSString *html = [NSString stringWithFormat:
		@"<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;margin:0;padding:40px;color:#1d1d1f;}h1{font-size:30px;line-height:1.2;margin:0 0 12px;}p{font-size:16px;line-height:1.5;color:#1d1d1f;max-width:760px;}</style></head><body><h1>%@</h1><p>%@</p></body></html>",
		safe_title,
		safe_fallback];

	[self.webView loadHTMLString:html baseURL:nil];
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
