//
//  MBImportController.m
//  Inkwell
//
//  Created by Manton Reece on 6/22/26.
//

#import "MBImportController.h"
#import "MBClient.h"
#import "MBSubscription.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface MBImportParserDelegate : NSObject <NSXMLParserDelegate>

@property (strong) NSMutableArray* feedURLs;
@property (strong) NSMutableSet* knownFeedURLs;

@end

@implementation MBImportParserDelegate

- (instancetype) init
{
	self = [super init];
	if (self) {
		self.feedURLs = [NSMutableArray array];
		self.knownFeedURLs = [NSMutableSet set];
	}
	return self;
}

- (void) parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
	#pragma unused(parser)
	#pragma unused(namespaceURI)
	#pragma unused(qName)

	if ([elementName caseInsensitiveCompare:@"outline"] != NSOrderedSame) {
		return;
	}

	NSString* url_string = [self attributeValueForName:@"xmlUrl" attributes:attributeDict];
	url_string = [url_string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (url_string.length == 0) {
		return;
	}

	NSString* key = [url_string lowercaseString];
	if ([self.knownFeedURLs containsObject:key]) {
		return;
	}

	[self.knownFeedURLs addObject:key];
	[self.feedURLs addObject:url_string];
}

- (NSString *) attributeValueForName:(NSString *)attributeName attributes:(NSDictionary *)attributes
{
	for (NSString* key in attributes) {
		if ([key caseInsensitiveCompare:attributeName] != NSOrderedSame) {
			continue;
		}

		id value = attributes[key];
		if ([value isKindOfClass:[NSString class]]) {
			return (NSString*) value;
		}
	}

	return @"";
}

@end

@interface MBImportController () <NSWindowDelegate>

@property (strong) MBClient* client;
@property (copy) NSString* token;
@property (weak) NSWindow* presentationWindow;
@property (strong) NSTextField* statusLabel;
@property (strong) NSProgressIndicator* progressIndicator;
@property (strong) NSButton* cancelButton;
@property (copy) NSArray* feedURLs;
@property (copy) void (^completionHandler)(BOOL didChangeFeeds);
@property (assign, readwrite) BOOL isImporting;
@property (assign) BOOL shouldCancelImport;
@property (assign) NSInteger currentIndex;
@property (assign) NSInteger importedCount;
@property (assign) NSInteger failedCount;

@end

@implementation MBImportController

- (instancetype) initWithClient:(MBClient *)client token:(NSString *)token
{
	self = [super initWithWindow:nil];
	if (self) {
		self.client = client;
		self.token = token ?: @"";
		self.feedURLs = @[];
	}
	return self;
}

- (void) beginImportFromWindow:(NSWindow *)presentationWindow completion:(void (^)(BOOL didChangeFeeds))completion
{
	if (self.isImporting) {
		return;
	}

	self.presentationWindow = presentationWindow;
	self.completionHandler = completion;

	NSOpenPanel* open_panel = [NSOpenPanel openPanel];
	open_panel.canChooseFiles = YES;
	open_panel.canChooseDirectories = NO;
	open_panel.allowsMultipleSelection = NO;
	NSArray* opml_types = [self opmlAllowedContentTypes];
	if (opml_types.count > 0) {
		open_panel.allowedContentTypes = opml_types;
	}

	__weak typeof(self) weak_self = self;
	void (^panel_completion)(NSModalResponse result) = ^(NSModalResponse result) {
		MBImportController* strong_self = weak_self;
		if (strong_self == nil || result != NSModalResponseOK) {
			return;
		}

		NSURL* file_url = open_panel.URL;
		if (file_url == nil) {
			return;
		}

		NSError* parse_error = nil;
		NSArray* feed_urls = [strong_self feedURLStringsFromOPMLFileAtURL:file_url error:&parse_error];
		if (parse_error != nil) {
			[strong_self presentAlertWithTitle:@"Import Failed" message:parse_error.localizedDescription ?: @"The OPML file could not be read."];
			return;
		}

		if (feed_urls.count == 0) {
			[strong_self presentAlertWithTitle:@"No Feeds Found" message:@"The OPML file did not contain any feed URLs."];
			return;
		}

		[strong_self beginImportingFeedURLs:feed_urls];
	};

	if (presentationWindow != nil) {
		[open_panel beginSheetModalForWindow:presentationWindow completionHandler:panel_completion];
	}
	else {
		[open_panel beginWithCompletionHandler:panel_completion];
	}
}

- (IBAction) cancelImport:(id)sender
{
	#pragma unused(sender)

	if (!self.isImporting) {
		[self.window close];
		return;
	}

	self.shouldCancelImport = YES;
	[self.window close];
}

- (BOOL) windowShouldClose:(NSWindow *)sender
{
	if (sender == self.window && self.isImporting) {
		self.shouldCancelImport = YES;
	}

	return YES;
}

- (NSArray *) opmlAllowedContentTypes
{
	NSMutableArray* content_types = [NSMutableArray array];

	UTType* opml_type = [UTType typeWithFilenameExtension:@"opml"];
	if (opml_type != nil) {
		[content_types addObject:opml_type];
	}

	UTType* xml_type = [UTType typeWithFilenameExtension:@"xml"];
	if (xml_type != nil) {
		[content_types addObject:xml_type];
	}

	return [content_types copy];
}

- (NSArray *) feedURLStringsFromOPMLFileAtURL:(NSURL *)fileURL error:(NSError **)error
{
	NSXMLParser* parser = [[NSXMLParser alloc] initWithContentsOfURL:fileURL];
	if (parser == nil) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:MBClientErrorDomain code:1100 userInfo:@{ NSLocalizedDescriptionKey: @"The OPML file could not be opened." }];
		}
		return @[];
	}

	MBImportParserDelegate* parser_delegate = [[MBImportParserDelegate alloc] init];
	parser.delegate = parser_delegate;
	BOOL did_parse = [parser parse];
	if (!did_parse) {
		if (error != NULL) {
			*error = parser.parserError ?: [NSError errorWithDomain:MBClientErrorDomain code:1101 userInfo:@{ NSLocalizedDescriptionKey: @"The OPML file could not be parsed." }];
		}
		return @[];
	}

	return [parser_delegate.feedURLs copy];
}

- (void) beginImportingFeedURLs:(NSArray *)feedURLs
{
	self.feedURLs = [feedURLs copy] ?: @[];
	self.currentIndex = 0;
	self.importedCount = 0;
	self.failedCount = 0;
	self.isImporting = YES;
	self.shouldCancelImport = NO;

	[self setupWindowIfNeeded];
	self.progressIndicator.minValue = 0.0;
	self.progressIndicator.maxValue = (double) self.feedURLs.count;
	self.progressIndicator.doubleValue = 0.0;
	self.cancelButton.title = @"Cancel";
	self.cancelButton.enabled = YES;
	[self.window center];
	[self.window makeKeyAndOrderFront:nil];

	[self importNextFeed];
}

- (void) importNextFeed
{
	if (!self.isImporting) {
		return;
	}

	if (self.shouldCancelImport) {
		[self finishCanceledImport];
		return;
	}

	if (self.currentIndex >= self.feedURLs.count) {
		[self finishImportAndRefreshFeeds];
		return;
	}

	NSString* feed_url = self.feedURLs[(NSUInteger) self.currentIndex];
	NSString* feed_name = [self displayNameForFeedURLString:feed_url];
	self.statusLabel.stringValue = [NSString stringWithFormat:@"Importing: %@...", feed_name.length > 0 ? feed_name : feed_url];

	[self importFeedURLString:feed_url allowChoiceRetry:YES];
}

- (void) importFeedURLString:(NSString *)feedURL allowChoiceRetry:(BOOL)allowChoiceRetry
{
	__weak typeof(self) weak_self = self;
	[self.client createFeedSubscriptionWithURLString:feedURL token:self.token completion:^(NSInteger status_code, MBSubscription* _Nullable subscription, NSArray* _Nullable choices, NSError* _Nullable error) {
		#pragma unused(subscription)

		MBImportController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		if (!strong_self.shouldCancelImport && error == nil && status_code == 300 && allowChoiceRetry) {
			NSString* choice_url = [strong_self firstFeedURLStringFromSubscriptionChoices:choices ?: @[]];
			if (choice_url.length > 0) {
				[strong_self importFeedURLString:choice_url allowChoiceRetry:NO];
				return;
			}
		}

		[strong_self finishCurrentFeedWithSuccess:(error == nil && status_code != 300)];
	}];
}

- (NSString *) firstFeedURLStringFromSubscriptionChoices:(NSArray *)choices
{
	for (id object in choices) {
		if (![object isKindOfClass:[NSDictionary class]]) {
			continue;
		}

		id feed_url = ((NSDictionary*) object)[@"feed_url"];
		if (![feed_url isKindOfClass:[NSString class]]) {
			continue;
		}

		NSString* trimmed_url = [(NSString*) feed_url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		if (trimmed_url.length > 0) {
			return trimmed_url;
		}
	}

	return @"";
}

- (void) finishCurrentFeedWithSuccess:(BOOL)didSucceed
{
	if (didSucceed) {
		self.importedCount += 1;
	}
	else {
		self.failedCount += 1;
	}

	self.currentIndex += 1;
	self.progressIndicator.doubleValue = (double) self.currentIndex;
	[self importNextFeed];
}

- (void) finishCanceledImport
{
	BOOL did_change_feeds = (self.importedCount > 0);
	self.isImporting = NO;
	self.shouldCancelImport = NO;
	if (!did_change_feeds) {
		return;
	}

	[self.client invalidateFeedIconsCache];

	__weak typeof(self) weak_self = self;
	[self.client fetchFeedSubscriptionsWithToken:self.token completion:^(NSArray* _Nullable subscriptions, NSError* _Nullable error) {
		#pragma unused(subscriptions)
		#pragma unused(error)

		MBImportController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		if (strong_self.completionHandler != nil) {
			strong_self.completionHandler(YES);
		}
	}];
}

- (void) finishImportAndRefreshFeeds
{
	self.statusLabel.stringValue = @"Refreshing feeds...";
	self.cancelButton.enabled = NO;
	[self.client invalidateFeedIconsCache];

	__weak typeof(self) weak_self = self;
	[self.client fetchFeedSubscriptionsWithToken:self.token completion:^(NSArray* _Nullable subscriptions, NSError* _Nullable error) {
		#pragma unused(subscriptions)
		#pragma unused(error)

		MBImportController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		[strong_self finishImportWindow];
		if (strong_self.completionHandler != nil) {
			strong_self.completionHandler(strong_self.importedCount > 0);
		}
	}];
}

- (void) finishImportWindow
{
	self.isImporting = NO;
	self.shouldCancelImport = NO;
	self.cancelButton.title = @"Done";
	self.cancelButton.enabled = YES;

	if (self.failedCount > 0) {
		self.statusLabel.stringValue = [NSString stringWithFormat:@"Imported %ld feeds. %ld failed.", (long) self.importedCount, (long) self.failedCount];
	}
	else if (self.importedCount == 1) {
		self.statusLabel.stringValue = @"Imported 1 feed.";
	}
	else {
		self.statusLabel.stringValue = [NSString stringWithFormat:@"Imported %ld feeds.", (long) self.importedCount];
	}
}

- (void) setupWindowIfNeeded
{
	if (self.window != nil) {
		return;
	}

	NSRect content_rect = NSMakeRect(0.0, 0.0, 420.0, 100.0);
	NSWindow* import_window = [[NSWindow alloc] initWithContentRect:content_rect styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable) backing:NSBackingStoreBuffered defer:NO];
	import_window.releasedWhenClosed = NO;
	import_window.title = @"Import OPML";
	import_window.delegate = self;

	NSView* content_view = [[NSView alloc] initWithFrame:content_rect];
	content_view.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField* status_label = [NSTextField labelWithString:@"Importing..."];
	status_label.translatesAutoresizingMaskIntoConstraints = NO;
	status_label.lineBreakMode = NSLineBreakByTruncatingMiddle;
	status_label.maximumNumberOfLines = 1;

	NSProgressIndicator* progress_indicator = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
	progress_indicator.translatesAutoresizingMaskIntoConstraints = NO;
	progress_indicator.indeterminate = NO;
	progress_indicator.style = NSProgressIndicatorStyleBar;

	NSButton* cancel_button = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelImport:)];
	cancel_button.translatesAutoresizingMaskIntoConstraints = NO;
	cancel_button.bezelStyle = NSBezelStyleRounded;
	cancel_button.keyEquivalent = @"\x1B";
	cancel_button.keyEquivalentModifierMask = 0;

	[content_view addSubview:status_label];
	[content_view addSubview:progress_indicator];
	[content_view addSubview:cancel_button];

	[NSLayoutConstraint activateConstraints:@[
		[status_label.topAnchor constraintEqualToAnchor:content_view.topAnchor constant:22.0],
		[status_label.leadingAnchor constraintEqualToAnchor:content_view.leadingAnchor constant:20.0],
		[status_label.trailingAnchor constraintEqualToAnchor:content_view.trailingAnchor constant:-20.0],
		[progress_indicator.leadingAnchor constraintEqualToAnchor:content_view.leadingAnchor constant:20.0],
		[progress_indicator.trailingAnchor constraintEqualToAnchor:cancel_button.leadingAnchor constant:-20.0],
		[progress_indicator.centerYAnchor constraintEqualToAnchor:cancel_button.centerYAnchor],
		[cancel_button.trailingAnchor constraintEqualToAnchor:content_view.trailingAnchor constant:-20.0],
		[cancel_button.bottomAnchor constraintEqualToAnchor:content_view.bottomAnchor constant:-20.0]
	]];

	self.window = import_window;
	self.statusLabel = status_label;
	self.progressIndicator = progress_indicator;
	self.cancelButton = cancel_button;
	import_window.contentView = content_view;
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
