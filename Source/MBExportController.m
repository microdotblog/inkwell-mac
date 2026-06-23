//
//  MBExportController.m
//  Inkwell
//
//  Created by Manton Reece on 6/22/26.
//

#import "MBExportController.h"
#import "MBClient.h"
#import "MBSubscription.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface MBExportController ()

@property (strong) MBClient* client;
@property (weak) NSWindow* presentationWindow;
@property (assign, readwrite) BOOL isExporting;

@end

@implementation MBExportController

- (instancetype) initWithClient:(MBClient *)client
{
	self = [super init];
	if (self) {
		self.client = client;
	}
	return self;
}

- (void) beginExportFromWindow:(NSWindow *)presentationWindow
{
	if (self.isExporting) {
		return;
	}

	self.presentationWindow = presentationWindow;

	NSArray* subscriptions = [self exportableFeedSubscriptions];
	if (subscriptions.count == 0) {
		[self presentAlertWithTitle:@"No Feeds to Export" message:@"Inkwell does not have any cached feeds to export."];
		return;
	}

	NSSavePanel* save_panel = [NSSavePanel savePanel];
	save_panel.canCreateDirectories = YES;
	save_panel.nameFieldStringValue = @"Inkwell.opml";
	NSArray* opml_types = [self opmlAllowedContentTypes];
	if (opml_types.count > 0) {
		save_panel.allowedContentTypes = opml_types;
	}

	NSString* opml_string = [self opmlStringForSubscriptions:subscriptions];
	self.isExporting = YES;

	__weak typeof(self) weak_self = self;
	void (^panel_completion)(NSModalResponse result) = ^(NSModalResponse result) {
		MBExportController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		strong_self.isExporting = NO;
		if (result != NSModalResponseOK) {
			return;
		}

		NSURL* file_url = save_panel.URL;
		if (file_url == nil) {
			return;
		}

		NSError* write_error = nil;
		BOOL did_write = [opml_string writeToURL:file_url atomically:YES encoding:NSUTF8StringEncoding error:&write_error];
		if (!did_write) {
			[strong_self presentAlertWithTitle:@"Export Failed" message:write_error.localizedDescription ?: @"The OPML file could not be saved."];
		}
	};

	if (presentationWindow != nil) {
		[save_panel beginSheetModalForWindow:presentationWindow completionHandler:panel_completion];
	}
	else {
		[save_panel beginWithCompletionHandler:panel_completion];
	}
}

- (NSArray *) opmlAllowedContentTypes
{
	UTType* opml_type = [UTType typeWithFilenameExtension:@"opml"];
	if (opml_type == nil) {
		return @[];
	}

	return @[ opml_type ];
}

- (NSArray *) exportableFeedSubscriptions
{
	NSArray* subscriptions = [self.client cachedFeedSubscriptions] ?: @[];
	NSMutableArray* exportable_subscriptions = [NSMutableArray array];

	for (id object in subscriptions) {
		if (![object isKindOfClass:[MBSubscription class]]) {
			continue;
		}

		MBSubscription* subscription = (MBSubscription*) object;
		NSString* feed_url = [subscription.feedURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		if (feed_url.length == 0) {
			continue;
		}

		[exportable_subscriptions addObject:subscription];
	}

	return [exportable_subscriptions copy];
}

- (NSString *) opmlStringForSubscriptions:(NSArray *)subscriptions
{
	NSMutableString* opml_string = [NSMutableString string];
	[opml_string appendString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"];
	[opml_string appendString:@"<opml version=\"2.0\">\n"];
	[opml_string appendString:@"\t<head>\n"];
	[opml_string appendString:@"\t\t<title>Inkwell Subscriptions</title>\n"];
	[opml_string appendString:@"\t</head>\n"];
	[opml_string appendString:@"\t<body>\n"];

	for (MBSubscription* subscription in subscriptions) {
		NSString* feed_url = [subscription.feedURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		if (feed_url.length == 0) {
			continue;
		}

		NSString* title = [self opmlTitleForSubscription:subscription];
		NSString* site_url = [subscription.siteURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		NSString* escaped_title = [self escapedOPMLAttributeString:title];
		NSString* escaped_feed_url = [self escapedOPMLAttributeString:feed_url];
		[opml_string appendFormat:@"\t\t<outline text=\"%@\" title=\"%@\" type=\"rss\" xmlUrl=\"%@\"", escaped_title, escaped_title, escaped_feed_url];
		if (site_url.length > 0) {
			[opml_string appendFormat:@" htmlUrl=\"%@\"", [self escapedOPMLAttributeString:site_url]];
		}
		[opml_string appendString:@" />\n"];
	}

	[opml_string appendString:@"\t</body>\n"];
	[opml_string appendString:@"</opml>\n"];
	return [opml_string copy];
}

- (NSString *) opmlTitleForSubscription:(MBSubscription *)subscription
{
	NSString* title = [subscription.title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (title.length > 0) {
		return title;
	}

	NSString* site_host = [self displayNameForFeedURLString:subscription.siteURL ?: @""];
	if (site_host.length > 0) {
		return site_host;
	}

	NSString* feed_host = [self displayNameForFeedURLString:subscription.feedURL ?: @""];
	if (feed_host.length > 0) {
		return feed_host;
	}

	return subscription.feedURL ?: @"Untitled Feed";
}

- (NSString *) escapedOPMLAttributeString:(NSString *)string
{
	NSMutableString* escaped_string = [[string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] mutableCopy] ?: [NSMutableString string];
	[escaped_string replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, escaped_string.length)];
	[escaped_string replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, escaped_string.length)];
	[escaped_string replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, escaped_string.length)];
	[escaped_string replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, escaped_string.length)];
	return [escaped_string copy];
}

- (NSString *) displayNameForFeedURLString:(NSString *)urlString
{
	NSString* trimmed_url_string = [urlString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (trimmed_url_string.length == 0) {
		return @"";
	}

	NSURLComponents* components = [NSURLComponents componentsWithString:trimmed_url_string];
	NSString* host = components.host ?: @"";
	if (host.length == 0) {
		return trimmed_url_string;
	}

	if ([host hasPrefix:@"www."]) {
		host = [host substringFromIndex:4];
	}

	return host;
}

- (void) presentAlertWithTitle:(NSString *)title message:(NSString *)message
{
	NSAlert* alert = [[NSAlert alloc] init];
	alert.alertStyle = NSAlertStyleWarning;
	alert.messageText = title ?: @"OPML Error";
	alert.informativeText = message ?: @"";

	if (self.presentationWindow != nil) {
		[alert beginSheetModalForWindow:self.presentationWindow completionHandler:nil];
	}
	else {
		[alert runModal];
	}
}

@end
