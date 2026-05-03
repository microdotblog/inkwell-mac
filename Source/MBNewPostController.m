//
//  MBNewPostController.m
//  Inkwell
//
//  Created by Codex on 5/3/26.
//

#import "MBNewPostController.h"

#import <WebKit/WebKit.h>

static CGFloat const InkwellNewPostWindowWidth = 600.0;
static CGFloat const InkwellNewPostWindowHeight = 400.0;
static CGFloat const InkwellNewPostStatusHeight = 44.0;
static NSToolbarItemIdentifier const InkwellNewPostToolbarPreviewIdentifier = @"InkwellNewPostToolbarPreview";
static NSToolbarItemIdentifier const InkwellNewPostToolbarProgressIdentifier = @"InkwellNewPostToolbarProgress";
static NSToolbarItemIdentifier const InkwellNewPostToolbarPostIdentifier = @"InkwellNewPostToolbarPost";
static NSString* const InkwellNewPostMicropubEndpoint = @"https://micro.blog/micropub";
static NSString* const InkwellNewPostErrorDomain = @"InkwellNewPostErrorDomain";

@interface MBNewPostController () <NSToolbarDelegate, NSToolbarItemValidation, WKNavigationDelegate>

@property (nonatomic, strong, readwrite) NSTextField* blogHostnameField;
@property (nonatomic, strong) WKWebView* webView;
@property (nonatomic, strong) NSButton* previewButton;
@property (nonatomic, strong) NSButton* postButton;
@property (nonatomic, strong) NSProgressIndicator* progressIndicator;
@property (nonatomic, strong) NSToolbarItem* progressToolbarItem;
@property (nonatomic, copy) NSString* markdownText;
@property (nonatomic, copy) NSString* destinationName;
@property (nonatomic, copy) NSString* destinationUID;
@property (nonatomic, copy) NSString* token;
@property (nonatomic, assign) BOOL didLoadEditorHTML;
@property (nonatomic, assign) BOOL isPosting;

- (void) loadEditorHTMLIfNeeded;
- (void) applyMarkdownTextToEditor;
- (void) resetPostingState;
- (void) setPosting:(BOOL) is_posting;
- (void) finishPostingWithError:(NSError * _Nullable)error;
- (void) postContent:(NSString *)content;
- (NSString *) urlEncodedString:(NSString *)string;
- (NSString *) responseDescriptionForData:(NSData *)data defaultMessage:(NSString *)default_message;

@end

@implementation MBNewPostController

- (instancetype) init
{
	self = [super initWithWindow:nil];
	if (self) {
		self.markdownText = @"";
		self.destinationName = @"";
		self.destinationUID = @"";
		self.token = @"";
	}
	return self;
}

- (void) showWithMarkdownText:(NSString *)markdownText
{
	[self showWithMarkdownText:markdownText destinationName:@"" destinationUID:@"" token:@""];
}

- (void) showWithMarkdownText:(NSString *)markdownText destinationName:(NSString *)destinationName destinationUID:(NSString *)destinationUID token:(NSString *)token
{
	[self setupWindowIfNeeded];
	self.markdownText = markdownText ?: @"";
	self.destinationName = destinationName ?: @"";
	self.destinationUID = destinationUID ?: @"";
	self.token = token ?: @"";
	self.blogHostnameField.stringValue = self.destinationName;
	[self resetPostingState];
	[self loadEditorHTMLIfNeeded];
	[self showWindow:nil];
	[self.window makeKeyAndOrderFront:nil];
	[self.window makeFirstResponder:self.webView];
	[self applyMarkdownTextToEditor];
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
		[strong_self postContent:content];
	}];
}

- (IBAction) preview:(id) sender
{
	#pragma unused(sender)
}

- (void) setupWindowIfNeeded
{
	if (self.window != nil) {
		return;
	}

	NSRect content_rect = NSMakeRect(0.0, 0.0, InkwellNewPostWindowWidth, InkwellNewPostWindowHeight);
	NSWindow* post_window = [[NSWindow alloc] initWithContentRect:content_rect styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable) backing:NSBackingStoreBuffered defer:NO];
	post_window.releasedWhenClosed = NO;
	post_window.title = @"New Post";
	post_window.titleVisibility = NSWindowTitleHidden;
	post_window.backgroundColor = NSColor.windowBackgroundColor;
	post_window.minSize = NSMakeSize(420.0, 280.0);
	post_window.toolbarStyle = NSWindowToolbarStyleUnified;

	NSToolbar* toolbar = [[NSToolbar alloc] initWithIdentifier:@"InkwellNewPostToolbar"];
	toolbar.delegate = self;
	toolbar.allowsUserCustomization = NO;
	toolbar.autosavesConfiguration = NO;
	toolbar.displayMode = NSToolbarDisplayModeIconOnly;
	post_window.toolbar = toolbar;

	NSView* content_view = [[NSView alloc] initWithFrame:content_rect];
	content_view.translatesAutoresizingMaskIntoConstraints = NO;

	WKWebViewConfiguration* configuration = [[WKWebViewConfiguration alloc] init];
	WKWebView* web_view = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
	web_view.translatesAutoresizingMaskIntoConstraints = NO;
	web_view.navigationDelegate = self;

	NSView* bottom_view = [[NSView alloc] initWithFrame:NSZeroRect];
	bottom_view.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField* blog_hostname_field = [NSTextField labelWithString:@""];
	blog_hostname_field.translatesAutoresizingMaskIntoConstraints = NO;
	blog_hostname_field.textColor = NSColor.secondaryLabelColor;
	blog_hostname_field.font = [NSFont systemFontOfSize:NSFont.systemFontSize];
	blog_hostname_field.alignment = NSTextAlignmentCenter;

	[content_view addSubview:web_view];
	[content_view addSubview:bottom_view];
	[bottom_view addSubview:blog_hostname_field];

	[NSLayoutConstraint activateConstraints:@[
		[web_view.topAnchor constraintEqualToAnchor:content_view.topAnchor],
		[web_view.leadingAnchor constraintEqualToAnchor:content_view.leadingAnchor],
		[web_view.trailingAnchor constraintEqualToAnchor:content_view.trailingAnchor],
		[web_view.bottomAnchor constraintEqualToAnchor:bottom_view.topAnchor],
		[bottom_view.leadingAnchor constraintEqualToAnchor:content_view.leadingAnchor],
		[bottom_view.trailingAnchor constraintEqualToAnchor:content_view.trailingAnchor],
		[bottom_view.bottomAnchor constraintEqualToAnchor:content_view.bottomAnchor],
		[bottom_view.heightAnchor constraintEqualToConstant:InkwellNewPostStatusHeight],
		[blog_hostname_field.leadingAnchor constraintGreaterThanOrEqualToAnchor:bottom_view.leadingAnchor constant:20.0],
		[blog_hostname_field.trailingAnchor constraintLessThanOrEqualToAnchor:bottom_view.trailingAnchor constant:-20.0],
		[blog_hostname_field.centerXAnchor constraintEqualToAnchor:bottom_view.centerXAnchor],
		[blog_hostname_field.centerYAnchor constraintEqualToAnchor:bottom_view.centerYAnchor]
	]];

	post_window.contentView = content_view;
	if (self.postButton != nil) {
		post_window.defaultButtonCell = self.postButton.cell;
	}
	[post_window center];

	self.window = post_window;
	self.webView = web_view;
	self.blogHostnameField = blog_hostname_field;
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
	[self.webView loadFileURL:editor_url allowingReadAccessToURL:directory_url];
}

- (void) applyMarkdownTextToEditor
{
	if (!self.didLoadEditorHTML) {
		return;
	}

	NSString* text = self.markdownText ?: @"";
	NSDictionary* payload = @{ @"text": text };
	NSError* error = nil;
	NSData* json_data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&error];
	if (json_data == nil || error != nil) {
		return;
	}

	NSString* json_string = [[NSString alloc] initWithData:json_data encoding:NSUTF8StringEncoding];
	if (json_string.length == 0) {
		return;
	}

	NSString* script = [NSString stringWithFormat:@"window.InkwellNewPostEditor && window.InkwellNewPostEditor.setText(%@.text);", json_string];
	[self.webView evaluateJavaScript:script completionHandler:nil];
}

- (void) resetPostingState
{
	self.isPosting = NO;
	self.postButton.enabled = YES;
	[self.progressIndicator stopAnimation:nil];
	self.progressIndicator.hidden = YES;
	self.progressToolbarItem.hidden = YES;
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
		[self close];
		return;
	}

	[self setPosting:NO];
	NSBeep();
}

- (void) postContent:(NSString *)content
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

	NSMutableArray* body_parts = [NSMutableArray array];
	[body_parts addObject:[NSString stringWithFormat:@"content=%@", [self urlEncodedString:(content ?: @"")]]];
	[body_parts addObject:[NSString stringWithFormat:@"mp-destination=%@", [self urlEncodedString:(self.destinationUID ?: @"")]]];
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
	[self applyMarkdownTextToEditor];
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
		InkwellNewPostToolbarPreviewIdentifier,
		InkwellNewPostToolbarProgressIdentifier,
		InkwellNewPostToolbarPostIdentifier
	];
}

- (NSArray<NSToolbarItemIdentifier> *) toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
	#pragma unused(toolbar)

	return @[
		NSToolbarFlexibleSpaceItemIdentifier,
		InkwellNewPostToolbarPreviewIdentifier,
		InkwellNewPostToolbarProgressIdentifier,
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
		item.hidden = YES;

		NSButton* preview_button = [NSButton buttonWithTitle:@"Preview" target:self action:@selector(preview:)];
		preview_button.bezelStyle = NSBezelStyleRounded;
		[preview_button sizeToFit];

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
		item.label = @"Post";
		item.paletteLabel = @"Post";
		item.toolTip = @"Post";

		NSButton* post_button = [NSButton buttonWithTitle:@"Post" target:self action:@selector(post:)];
		post_button.bezelStyle = NSBezelStyleRounded;
		post_button.keyEquivalent = @"\r";
		post_button.keyEquivalentModifierMask = NSEventModifierFlagCommand;
		[post_button sizeToFit];
		[post_button.widthAnchor constraintGreaterThanOrEqualToConstant:60.0].active = YES;

		item.view = post_button;
		self.postButton = post_button;
		return item;
	}

	return nil;
}

@end
