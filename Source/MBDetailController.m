//
//  MBDetailController.m
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import "MBDetailController.h"
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

- (void) showSidebarItem:(NSDictionary<NSString *,NSString *> * _Nullable)item
{
	NSString *title = @"Select a source item";
	NSString *subtitle = @"Pick an item from the sidebar.";

	NSString *item_title = item[@"title"];
	NSString *item_subtitle = item[@"subtitle"];
	if (item_title.length > 0) {
		title = item_title;
	}
	if (item_subtitle.length > 0) {
		subtitle = item_subtitle;
	}

	NSString *safe_title = [self escapedHTMLString:title];
	NSString *safe_subtitle = [self escapedHTMLString:subtitle];
	NSString *html = [NSString stringWithFormat:
		@"<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;margin:0;padding:40px;color:#1d1d1f;}h1{font-size:30px;line-height:1.2;margin:0 0 12px;}p{font-size:16px;line-height:1.5;color:#1d1d1f;max-width:760px;}</style></head><body><h1>%@</h1><p>%@</p></body></html>",
		safe_title,
		safe_subtitle];

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
