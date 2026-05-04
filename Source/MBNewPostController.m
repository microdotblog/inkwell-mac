//
//  MBNewPostController.m
//  Inkwell
//
//  Created by Codex on 5/3/26.
//

#import "MBNewPostController.h"

#import "MBClient.h"
#import "MBPreviewButton.h"

#import <WebKit/WebKit.h>

static CGFloat const InkwellNewPostWindowWidth = 600.0;
static CGFloat const InkwellNewPostWindowHeight = 400.0;
static CGFloat const InkwellNewPostStatusHeight = 44.0;
static NSToolbarItemIdentifier const InkwellNewPostToolbarPreviewIdentifier = @"InkwellNewPostToolbarPreview";
static NSToolbarItemIdentifier const InkwellNewPostToolbarProgressIdentifier = @"InkwellNewPostToolbarProgress";
static NSToolbarItemIdentifier const InkwellNewPostToolbarPostIdentifier = @"InkwellNewPostToolbarPost";
static NSString* const InkwellNewPostMicropubEndpoint = @"https://micro.blog/micropub";
static NSString* const InkwellNewPostPreviewEndpoint = @"https://micro.blog/pages/preview";
static NSString* const InkwellNewPostErrorDomain = @"InkwellNewPostErrorDomain";
static NSString* const InkwellNewPostContentChangedScriptMessageName = @"newPostContentChanged";

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

@interface MBNewPostController () <NSToolbarDelegate, NSToolbarItemValidation, WKNavigationDelegate, WKScriptMessageHandler>

@property (nonatomic, strong, readwrite) NSTextField* blogHostnameField;
@property (nonatomic, strong) NSTextField* characterCountField;
@property (nonatomic, strong) WKWebView* webView;
@property (nonatomic, strong) NSButton* previewButton;
@property (nonatomic, strong) NSButton* postButton;
@property (nonatomic, strong) NSProgressIndicator* progressIndicator;
@property (nonatomic, strong) NSToolbarItem* progressToolbarItem;
@property (nonatomic, strong) MBNewPostWeakScriptMessageHandler* contentChangedScriptMessageHandler;
@property (nonatomic, copy) NSString* markdownText;
@property (nonatomic, copy) NSString* destinationName;
@property (nonatomic, copy) NSString* destinationUID;
@property (nonatomic, copy) NSArray* destinations;
@property (nonatomic, copy) NSString* token;
@property (nonatomic, assign) BOOL didLoadEditorHTML;
@property (nonatomic, assign) BOOL isPosting;
@property (nonatomic, assign) BOOL isPreviewing;

- (void) loadEditorHTMLIfNeeded;
- (void) applyMarkdownTextToEditor;
- (void) resetPostingState;
- (void) resetPreviewState;
- (void) resetCharacterCount;
- (void) setPosting:(BOOL) is_posting;
- (void) finishPostingWithError:(NSError * _Nullable)error;
- (void) postContent:(NSString *)content;
- (void) postPreviewContent:(NSString *)content completion:(void (^)(NSString* _Nullable html, NSError* _Nullable error))completion;
- (void) showPreviewHTML:(NSString *)html;
- (void) updateCharacterCountWithPayload:(id)payload;
- (void) showDestinationsMenuFromView:(NSView *)view event:(NSEvent *)event;
- (void) selectDestinationFromMenuItem:(NSMenuItem *)menu_item;
- (NSString *) stringValueFromObject:(id)object;
- (NSInteger) integerValueFromObject:(id)object;
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
		self.destinations = @[];
		self.token = @"";
	}
	return self;
}

- (void) dealloc
{
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
	self.markdownText = markdownText ?: @"";
	self.destinationName = destinationName ?: @"";
	self.destinationUID = destinationUID ?: @"";
	self.destinations = destinations ?: @[];
	self.token = token ?: @"";
	self.blogHostnameField.stringValue = self.destinationName;
	[self resetCharacterCount];
	if (self.destinationUID.length > 0) {
		[[NSUserDefaults standardUserDefaults] setObject:self.destinationUID forKey:InkwellCurrentDestinationDefaultsKey];
	}
	[self resetPostingState];
	[self resetPreviewState];
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

	if (self.isPreviewing) {
		self.isPreviewing = NO;
		self.previewButton.state = NSControlStateValueOff;
		[self.webView evaluateJavaScript:@"window.InkwellNewPostEditor && window.InkwellNewPostEditor.togglePreview('');" completionHandler:nil];
		return;
	}

	self.previewButton.enabled = NO;
	__weak typeof(self) weak_self = self;
	[self.webView evaluateJavaScript:@"window.InkwellNewPostEditor ? window.InkwellNewPostEditor.markdown() : ''" completionHandler:^(id _Nullable result, NSError* _Nullable error) {
		MBNewPostController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		if (error != nil) {
			strong_self.previewButton.enabled = YES;
			NSBeep();
			return;
		}

		NSString* content = [result isKindOfClass:[NSString class]] ? (NSString*) result : @"";
		[strong_self postPreviewContent:content completion:^(NSString* _Nullable html, NSError* _Nullable preview_error) {
			strong_self.previewButton.enabled = YES;
			if (preview_error != nil) {
				strong_self.isPreviewing = NO;
				strong_self.previewButton.state = NSControlStateValueOff;
				NSBeep();
				return;
			}

			strong_self.isPreviewing = YES;
			strong_self.previewButton.state = NSControlStateValueOn;
			[strong_self showPreviewHTML:(html ?: @"")];
		}];
	}];
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
	WKUserContentController* user_content_controller = [[WKUserContentController alloc] init];
	self.contentChangedScriptMessageHandler = [[MBNewPostWeakScriptMessageHandler alloc] initWithTarget:self];
	[user_content_controller addScriptMessageHandler:self.contentChangedScriptMessageHandler name:InkwellNewPostContentChangedScriptMessageName];
	configuration.userContentController = user_content_controller;
	WKWebView* web_view = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
	web_view.translatesAutoresizingMaskIntoConstraints = NO;
	web_view.navigationDelegate = self;

	NSView* bottom_view = [[NSView alloc] initWithFrame:NSZeroRect];
	bottom_view.translatesAutoresizingMaskIntoConstraints = NO;

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
	character_count_field.font = [NSFont systemFontOfSize:NSFont.systemFontSize];
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
	hostname_hover_view.hoverChangedHandler = ^(BOOL isHovering) {
		weak_chevron_view.hidden = !isHovering;
	};
	__weak typeof(self) weak_self = self;
	hostname_hover_view.clickHandler = ^(NSView* view, NSEvent* event) {
		[weak_self showDestinationsMenuFromView:view event:event];
	};

	[content_view addSubview:web_view];
	[content_view addSubview:bottom_view];
	[bottom_view addSubview:hostname_hover_view];
	[bottom_view addSubview:character_count_field];
	[hostname_hover_view addSubview:blog_hostname_field];
	[hostname_hover_view addSubview:blog_hostname_chevron_view];

	[NSLayoutConstraint activateConstraints:@[
		[web_view.topAnchor constraintEqualToAnchor:content_view.topAnchor],
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
		[character_count_field.trailingAnchor constraintEqualToAnchor:bottom_view.trailingAnchor constant:-20.0],
		[character_count_field.centerYAnchor constraintEqualToAnchor:bottom_view.centerYAnchor],
		[character_count_field.widthAnchor constraintGreaterThanOrEqualToConstant:62.0],
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
	if (self.postButton != nil) {
		post_window.defaultButtonCell = self.postButton.cell;
	}
	[post_window center];

	self.window = post_window;
	self.webView = web_view;
	self.blogHostnameField = blog_hostname_field;
	self.characterCountField = character_count_field;
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

- (void) resetPreviewState
{
	self.isPreviewing = NO;
	self.previewButton.state = NSControlStateValueOff;
}

- (void) resetCharacterCount
{
	self.characterCountField.stringValue = @"0/300";
	self.characterCountField.textColor = NSColor.secondaryLabelColor;
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
	[self.webView evaluateJavaScript:script completionHandler:nil];
}

- (void) updateCharacterCountWithPayload:(id)payload
{
	if (![payload isKindOfClass:[NSDictionary class]]) {
		return;
	}

	NSDictionary* dictionary = (NSDictionary*) payload;
	NSInteger count = [self integerValueFromObject:dictionary[@"count"]];
	BOOL is_blockquote = [dictionary[@"is_blockquote"] respondsToSelector:@selector(boolValue)] ? [dictionary[@"is_blockquote"] boolValue] : NO;
	NSInteger max_count = is_blockquote ? 600 : 300;

	self.characterCountField.stringValue = [NSString stringWithFormat:@"%ld/%ld", (long) count, (long) max_count];
	self.characterCountField.textColor = (count > max_count) ? NSColor.systemRedColor : NSColor.secondaryLabelColor;
}

- (void) showDestinationsMenuFromView:(NSView *)view event:(NSEvent *)event
{
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
	[self applyMarkdownTextToEditor];
}

- (void) userContentController:(WKUserContentController *)user_content_controller didReceiveScriptMessage:(WKScriptMessage *)script_message
{
	#pragma unused(user_content_controller)

	if ([script_message.name isEqualToString:InkwellNewPostContentChangedScriptMessageName]) {
		[self updateCharacterCountWithPayload:script_message.body];
	}
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
		item.label = @"Post";
		item.paletteLabel = @"Post";
		item.toolTip = @"Post";

		NSButton* post_button = [NSButton buttonWithTitle:@"Post" target:self action:@selector(post:)];
		post_button.bezelStyle = NSBezelStyleRounded;
		post_button.keyEquivalent = @"\r";
		post_button.keyEquivalentModifierMask = NSEventModifierFlagCommand;
		[post_button sizeToFit];
		[post_button.widthAnchor constraintGreaterThanOrEqualToConstant:65.0].active = YES;

		item.view = post_button;
		self.postButton = post_button;
		return item;
	}

	return nil;
}

@end
