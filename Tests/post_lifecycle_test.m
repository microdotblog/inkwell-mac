#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import "MBAppDelegate.h"
#import "MBAuthController.h"
#import "MBClient.h"
#import "MBHighlight.h"
#import "MBMainController.h"
#import "MBNewPostController.h"
#import "MBPathUtilities.h"
#import "MBPodcastController.h"
#import "MBSessionController.h"
#import "MBAvatarLoader.h"

// Exercise the real composer, window coordinator, app delegate, client, and player
// teardown without opening other panes or touching the user's account or network.
#define STUB_CONTROLLER(name) @interface name : NSObject @end @implementation name @end
STUB_CONTROLLER(MBConversationController)
STUB_CONTROLLER(MBDetailController)
STUB_CONTROLLER(MBExportController)
STUB_CONTROLLER(MBHighlightsController)
STUB_CONTROLLER(MBImportController)
STUB_CONTROLLER(MBNewFeedChoice)
STUB_CONTROLLER(MBNewFeedChoiceCellView)
STUB_CONTROLLER(MBPreferencesController)
STUB_CONTROLLER(MBSidebarController)
STUB_CONTROLLER(MBWelcomeController)

NSNotificationName const MBAvatarLoaderDidLoadImageNotification = @"TestAvatarLoaded";
NSString* const MBAvatarLoaderURLStringUserInfoKey = @"url";
@implementation MBAvatarLoader
+ (void) cleanupCachedImageFiles
{
}
+ (instancetype) sharedLoader
{
	return [[self alloc] init];
}
- (NSImage *) cachedImageForURLString:(NSString *)urlString
{
	return nil;
}
- (void) loadImageForURLString:(NSString *)urlString
{
}
@end

static NSUserDefaults* test_defaults;
static NSUInteger check_count;
static NSUInteger cache_path_count;
static NSModalResponse close_response;

@implementation NSUserDefaults (PostTests)
+ (NSUserDefaults *) postTestDefaults
{
	return test_defaults;
}
@end

@implementation MBPathUtilities
+ (NSURL *) appContainerDirectoryURLForSearchPathDirectory:(NSSearchPathDirectory)directory createIfNeeded:(BOOL)createIfNeeded
{
	return nil;
}
+ (NSURL *) appSubdirectoryURLForSearchPathDirectory:(NSSearchPathDirectory)directory relativePath:(NSString *)relativePath createIfNeeded:(BOOL)createIfNeeded
{
	return nil;
}
+ (NSURL *) appFileURLForSearchPathDirectory:(NSSearchPathDirectory)directory filename:(NSString *)filename createDirectoryIfNeeded:(BOOL)createDirectoryIfNeeded
{
	cache_path_count += 1;
	return nil;
}
+ (void) cleanupLegacyFiles
{
}
+ (void) clearUserScopedCacheFiles
{
}
@end

@interface MBNewPostController (PostTests)
- (IBAction) post:(id)sender;
- (void) updateDocumentEditedState;
- (BOOL) windowShouldClose:(id)sender;
- (NSString *) responseDescriptionForData:(NSData *)data defaultMessage:(NSString *)message;
@end
@interface MBMainController (PostTests)
- (void) postWindowControllerDidClose:(MBNewPostController *)controller;
@end
@interface MBAppDelegate (PostTests)
- (NSApplicationTerminateReply) applicationShouldTerminate:(NSApplication *)application;
@end
@interface MBPodcastController (PostTests)
- (void) persistPlaybackRecordsToDisk;
- (void) playbackSaveTimerDidFire:(NSTimer *)timer;
@end

static void Check(BOOL condition, NSString* message)
{
	check_count += 1;
	if (!condition) {
		fprintf(stderr, "FAIL: %s\n", message.UTF8String);
		exit(1);
	}
}

static void DrainRunLoop(void)
{
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
}

@interface TestWindow : NSWindow
@end
@implementation TestWindow
- (void) makeKeyAndOrderFront:(id)sender
{
	self.alphaValue = 0.0;
	[super makeKeyAndOrderFront:sender];
}
@end

@interface TestWebView : NSObject
@property (strong) NSMutableArray* completions;
@property (copy) NSString* markdown;
@property (strong) NSError* error;
- (void) completeEvaluation;
@end
@implementation TestWebView
- (instancetype) init
{
	self = [super init];
	if (self) {
		self.completions = [NSMutableArray array];
		self.markdown = @"Body 1";
	}
	return self;
}
- (void) evaluateJavaScript:(NSString *)script completionHandler:(void (^)(id, NSError *))completion
{
	if (completion != nil) {
		[self.completions addObject:[completion copy]];
	}
}
- (void) completeEvaluation
{
	void (^completion)(id, NSError*) = self.completions.firstObject;
	[self.completions removeObjectAtIndex:0];
	completion(self.markdown, self.error);
}
- (WKWebViewConfiguration *) configuration
{
	return nil;
}
@end

@interface TestTask : NSObject
- (void) resume;
@end
@implementation TestTask
- (void) resume
{
}
@end

@interface TestSession : NSObject
@property (strong) NSMutableArray* requests;
@property (strong) NSMutableArray* completions;
@property (assign) BOOL wasCancelled;
- (void) completeRequest:(NSUInteger)index status:(NSInteger)status body:(NSString *)body;
@end
@implementation TestSession
- (instancetype) init
{
	self = [super init];
	if (self) {
		self.requests = [NSMutableArray array];
		self.completions = [NSMutableArray array];
	}
	return self;
}
- (NSURLSessionDataTask *) dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion
{
	[self.requests addObject:request];
	[self.completions addObject:[completion copy]];
	return (NSURLSessionDataTask*) [[TestTask alloc] init];
}
- (void) completeRequest:(NSUInteger)index status:(NSInteger)status body:(NSString *)body
{
	NSURLRequest* request = self.requests[index];
	NSHTTPURLResponse* response = [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:@{ @"Location": @"https://example.com/post" }];
	void (^completion)(NSData*, NSURLResponse*, NSError*) = self.completions[index];
	self.completions[index] = NSNull.null;
	completion([body dataUsingEncoding:NSUTF8StringEncoding], response, nil);
}
- (void) invalidateAndCancel
{
	self.wasCancelled = YES;
}
@end

static TestSession* post_session;
@implementation NSURLSession (PostTests)
+ (NSURLSession *) postTestSharedSession
{
	return (NSURLSession*) post_session;
}
@end
@implementation NSAlert (PostTests)
- (NSModalResponse) postTestRunModal
{
	return close_response;
}
@end

@interface TestAppDelegate : MBAppDelegate
@property (assign) BOOL welcomeShown;
@end
@implementation TestAppDelegate
- (void) showWelcomeWindow
{
	self.welcomeShown = YES;
}
@end

@interface TestApplication : NSObject
@property (assign) BOOL didReply;
@property (assign) BOOL shouldTerminate;
@end
@implementation TestApplication
- (void) replyToApplicationShouldTerminate:(BOOL)shouldTerminate
{
	self.didReply = YES;
	self.shouldTerminate = shouldTerminate;
}
@end

static MBNewPostController* Composer(MBMainController* main_controller)
{
	MBNewPostController* controller = [[MBNewPostController alloc] init];
	TestWindow* window = [[TestWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 400) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
	window.releasedWhenClosed = NO;
	window.delegate = (id) controller;
	controller.window = window;
	[controller setValue:[[TestWebView alloc] init] forKey:@"webView"];
	NSTextField* title_field = [[NSTextField alloc] init];
	title_field.stringValue = @"Title 1";
	[controller setValue:title_field forKey:@"titleField"];
	[controller setValue:@"test-token" forKey:@"token"];
	[controller setValue:@"Body 1" forKey:@"currentMarkdownText"];
	[controller updateDocumentEditedState];
	if (main_controller != nil) {
		NSMutableArray* controllers = [main_controller valueForKey:@"postControllers"];
		if (controllers == nil) {
			controllers = [NSMutableArray array];
			[main_controller setValue:controllers forKey:@"postControllers"];
		}
		[controllers addObject:controller];
		__weak MBMainController* weak_main = main_controller;
		controller.didCloseHandler = ^(MBNewPostController* closing_controller) {
			[weak_main postWindowControllerDidClose:closing_controller];
		};
	}
	return controller;
}

static MBClient* Client(TestSession* session)
{
	MBClient* client = [[MBClient alloc] init];
	[[client valueForKey:@"session"] invalidateAndCancel];
	[client setValue:session forKey:@"session"];
	return client;
}

static TestAppDelegate* AppDelegate(MBMainController* main_controller, MBClient* client)
{
	TestAppDelegate* delegate = [[TestAppDelegate alloc] init];
	[delegate setValue:main_controller forKey:@"mainController"];
	[delegate setValue:client forKey:@"client"];
	[delegate setValue:[[MBSessionController alloc] init] forKey:@"sessionController"];
	return delegate;
}

static void TestErrorResponses(void)
{
	MBNewPostController* controller = Composer(nil);
	for (NSString* body in @[@"{\"error\":null}", @"{\"error\":503}", @"{\"error\":[]}", @"{\"error_description\":{}}", @"<html>Unavailable</html>", @"{invalid", @""]) {
		NSString* description = [controller responseDescriptionForData:[body dataUsingEncoding:NSUTF8StringEncoding] defaultMessage:@"Failed"];
		Check([description isKindOfClass:NSString.class] && description.length > 0, @"Malformed errors must yield a safe description.");
	}
	NSString* description = [controller responseDescriptionForData:[@"{\"error_description\":\"Try again\"}" dataUsingEncoding:NSUTF8StringEncoding] defaultMessage:@"Failed"];
	Check([description isEqual:@"Try again"], @"Preserve the server's string error message.");
}

static void TestEditsDuringSave(BOOL publish)
{
	post_session = [[TestSession alloc] init];
	MBNewPostController* controller = Composer(nil);
	__block BOOL did_close = NO;
	controller.didCloseHandler = ^(MBNewPostController* closing_controller) { did_close = YES; };
	if (publish) {
		[controller post:controller];
	}
	else {
		[controller saveDraft:controller];
	}
	[(TestWebView*) [controller valueForKey:@"webView"] completeEvaluation];
	NSString* request_body = [[NSString alloc] initWithData:[post_session.requests[0] HTTPBody] encoding:NSUTF8StringEncoding];
	Check([request_body containsString:@"Body%201"] && [request_body containsString:@"Title%201"], @"Send the body and title captured for the operation.");
	[controller setValue:@"Body 2" forKey:@"currentMarkdownText"];
	[(NSTextField*) [controller valueForKey:@"titleField"] setStringValue:@"Title 2"];
	[controller updateDocumentEditedState];
	[post_session completeRequest:0 status:201 body:@""];
	DrainRunLoop();
	Check(!did_close, @"Successful posting must not close over newer edits.");
	Check(controller.window.documentEdited, @"Newer edits must remain unsaved after success.");
	Check([[controller valueForKey:@"initialMarkdownText"] isEqual:@"Body 1"], @"Only the submitted body becomes the saved baseline.");
	Check([[controller valueForKey:@"initialTitleText"] isEqual:@"Title 1"], @"Only the submitted title becomes the saved baseline.");
	Check([[controller valueForKey:@"currentMarkdownText"] isEqual:@"Body 2"], @"Keep the user's current body.");
	Check([[controller valueForKey:@"editingPostURLString"] isEqual:@"https://example.com/post"], @"Further saves must update the created post.");
	close_response = NSAlertFirstButtonReturn;
	__block BOOL close_finished = NO;
	[controller requestCloseWithCompletion:^(BOOL didClose) { close_finished = didClose; }];
	[(TestWebView*) [controller valueForKey:@"webView"] setMarkdown:@"Body 2"];
	[(TestWebView*) [controller valueForKey:@"webView"] completeEvaluation];
	NSDictionary* update = [NSJSONSerialization JSONObjectWithData:[post_session.requests[1] HTTPBody] options:0 error:nil];
	Check([update[@"replace"][@"content"][0] isEqual:@"Body 2"], @"A subsequent close saves the newer content.");
	Check(publish ? update[@"replace"][@"post-status"] == nil : [update[@"replace"][@"post-status"][0] isEqual:@"draft"], @"Close Save preserves publication status.");
	[post_session completeRequest:1 status:200 body:@""];
	DrainRunLoop();
	Check(close_finished && did_close, @"Close after saving all current edits.");
}

static void TestPublishedClose(BOOL isDraft)
{
	post_session = [[TestSession alloc] init];
	MBNewPostController* controller = Composer(nil);
	[controller setValue:@"https://example.com/existing" forKey:@"editingPostURLString"];
	[controller setValue:@(isDraft) forKey:@"editingPostIsDraft"];
	close_response = NSAlertFirstButtonReturn;
	__block BOOL did_close = NO;
	[controller requestCloseWithCompletion:^(BOOL didClose) { did_close = didClose; }];
	Check(!did_close, @"Close must wait for saving.");
	[(TestWebView*) [controller valueForKey:@"webView"] completeEvaluation];
	NSDictionary* payload = [NSJSONSerialization JSONObjectWithData:[post_session.requests[0] HTTPBody] options:0 error:nil];
	Check([payload[@"action"] isEqual:@"update"] && [payload[@"url"] isEqual:@"https://example.com/existing"], @"Close Save updates the existing post.");
	Check(isDraft ? [payload[@"replace"][@"post-status"][0] isEqual:@"draft"] : payload[@"replace"][@"post-status"] == nil, @"Close Save cannot unpublish a published post.");
	[post_session completeRequest:0 status:200 body:@""];
	DrainRunLoop();
	Check(did_close, @"Successful saving closes the window.");
}

static void TestQuit(NSModalResponse response, BOOL failSave)
{
	post_session = [[TestSession alloc] init];
	MBMainController* main_controller = [[MBMainController alloc] initWithWindow:nil];
	MBNewPostController* controller = Composer(main_controller);
	TestAppDelegate* delegate = AppDelegate(main_controller, nil);
	TestApplication* application = [[TestApplication alloc] init];
	close_response = response;
	NSApplicationTerminateReply reply = [delegate applicationShouldTerminate:(NSApplication*) application];
	Check(reply == NSTerminateLater && !application.didReply, @"Quit must defer until window decisions and saves finish.");
	if (response == NSAlertFirstButtonReturn) {
		[(TestWebView*) [controller valueForKey:@"webView"] completeEvaluation];
		DrainRunLoop();
		Check(!application.didReply, @"Quit must wait for the HTTP result.");
		[post_session completeRequest:0 status:failSave ? 503 : 201 body:failSave ? @"{\"error\":null}" : @""];
	}
	DrainRunLoop();
	BOOL should_quit = response != NSAlertThirdButtonReturn && !failSave;
	Check(application.didReply && application.shouldTerminate == should_quit, @"Quit honours Save, Don't Save, Cancel, and failed saves.");
	Check([main_controller hasOpenPostWindows] != should_quit, @"Cancellation or failure retains the composer.");
	if (!should_quit) {
		Check(controller.window.documentEdited, @"Cancelled Quit retains unsaved content.");
	}
}

static void TestMultipleWindowsAndPendingSave(void)
{
	post_session = [[TestSession alloc] init];
	MBMainController* main_controller = [[MBMainController alloc] initWithWindow:nil];
	MBNewPostController* first = Composer(main_controller);
	MBNewPostController* second = Composer(main_controller);
	[second saveDraft:second];
	close_response = NSAlertSecondButtonReturn;
	__block BOOL did_close = NO;
	[main_controller closePostWindowsWithCompletion:^(BOOL didClose) { did_close = didClose; }];
	Check(!did_close && [main_controller hasOpenPostWindows], @"Closing several windows waits for an existing save.");
	Check([first valueForKey:@"didCloseHandler"] == nil, @"The first window has already closed.");
	Check(![second windowShouldClose:second.window], @"An unedited or edited window cannot close during a request.");
	[(TestWebView*) [second valueForKey:@"webView"] completeEvaluation];
	[post_session completeRequest:0 status:201 body:@""];
	DrainRunLoop();
	Check(did_close && ![main_controller hasOpenPostWindows], @"Continue closing all windows when the pending save finishes.");
}

static void TestSignOutDuringSave(BOOL failSave, BOOL editDuringSave)
{
	post_session = [[TestSession alloc] init];
	TestSession* session = [[TestSession alloc] init];
	MBClient* client = Client(session);
	MBMainController* main_controller = [[MBMainController alloc] initWithWindow:nil client:client token:@"A-token"];
	MBNewPostController* controller = Composer(main_controller);
	TestAppDelegate* delegate = AppDelegate(main_controller, client);
	[test_defaults setObject:@"A-token" forKey:InkwellTokenDefaultsKey];
	close_response = NSAlertFirstButtonReturn;
	[delegate signOut:delegate];
	Check(!session.wasCancelled && !delegate.welcomeShown && [test_defaults stringForKey:InkwellTokenDefaultsKey] != nil, @"Sign-out waits for Save before retiring the account.");
	[(TestWebView*) [controller valueForKey:@"webView"] completeEvaluation];
	if (editDuringSave) {
		[controller setValue:@"New unsent body" forKey:@"currentMarkdownText"];
		[controller updateDocumentEditedState];
	}
	[post_session completeRequest:0 status:failSave ? 503 : 201 body:failSave ? @"{\"error\":null}" : @""];
	DrainRunLoop();
	BOOL should_sign_out = !failSave && !editDuringSave;
	Check(session.wasCancelled == should_sign_out && delegate.welcomeShown == should_sign_out, @"Failed saving or newer edits cancel sign-out.");
	Check(([test_defaults stringForKey:InkwellTokenDefaultsKey] == nil) == should_sign_out, @"Keep the token when sign-out cannot finish.");
	if (!should_sign_out) {
		Check(controller.window.documentEdited && [main_controller hasOpenPostWindows], @"Keep unsaved content available after cancelled sign-out.");
	}
}

static void TestEditorFailureAndEmptyQuit(void)
{
	post_session = [[TestSession alloc] init];
	MBMainController* main_controller = [[MBMainController alloc] initWithWindow:nil];
	MBNewPostController* controller = Composer(main_controller);
	TestAppDelegate* delegate = AppDelegate(main_controller, nil);
	TestApplication* application = [[TestApplication alloc] init];
	close_response = NSAlertFirstButtonReturn;
	Check([delegate applicationShouldTerminate:(NSApplication*) application] == NSTerminateLater, @"Save during Quit waits for editor content.");
	[(TestWebView*) [controller valueForKey:@"webView"] setError:[NSError errorWithDomain:@"TestEditor" code:1 userInfo:nil]];
	[(TestWebView*) [controller valueForKey:@"webView"] completeEvaluation];
	DrainRunLoop();
	Check(application.didReply && !application.shouldTerminate && controller.window.documentEdited, @"Editor failures cancel Quit without losing content.");
	Check(post_session.requests.count == 0, @"Editor failures cannot send an empty replacement.");
	delegate = AppDelegate(nil, nil);
	Check([delegate applicationShouldTerminate:(NSApplication*) application] == NSTerminateNow, @"Quit without composers does not need deferred termination.");
}

static void TestSignOut(BOOL cancel)
{
	TestSession* session = [[TestSession alloc] init];
	MBClient* client = Client(session);
	[client saveLocalHighlightForEntryID:42 postTitle:@"Private A" postURL:@"https://example.com/private" selectionText:@"Account A highlight" selectionStart:0 selectionEnd:19];
	[client setValue:[NSSet setWithObject:@42] forKey:@"cachedUnreadEntryIDs"];
	MBMainController* main_controller = [[MBMainController alloc] initWithWindow:nil client:client token:@"A-token"];
	Composer(main_controller);
	TestAppDelegate* delegate = AppDelegate(main_controller, client);
	[test_defaults setObject:@"A-token" forKey:InkwellTokenDefaultsKey];
	close_response = cancel ? NSAlertThirdButtonReturn : NSAlertSecondButtonReturn;
	[delegate signOut:delegate];
	Check(session.wasCancelled != cancel, @"Cancel keeps the account; completed sign-out cancels requests.");
	Check(([test_defaults stringForKey:InkwellTokenDefaultsKey] != nil) == cancel, @"Sign-out must not clear the token before window approval.");
	if (cancel) {
		Check([delegate valueForKey:@"client"] == client && [client cachedAllHighlights].count == 1, @"Cancelled sign-out keeps the original client and data.");
	}
	else {
		MBClient* new_client = [delegate valueForKey:@"client"];
		Check(new_client != client && [new_client cachedAllHighlights].count == 0, @"The next account receives a fresh client with no old highlights.");
		Check([client cachedAllHighlights].count == 0 && [[client valueForKey:@"cachedUnreadEntryIDs"] count] == 0, @"Retired clients forget cached account state.");
		Check(delegate.welcomeShown && [delegate valueForKey:@"mainController"] == nil, @"Completed sign-out returns to the welcome window.");
		MBHighlight* highlight = [client saveLocalHighlightForEntryID:43 postTitle:@"Stale" postURL:@"" selectionText:@"stale" selectionStart:0 selectionEnd:5];
		Check(highlight == nil && [client cachedAllHighlights].count == 0, @"Retired clients cannot save more old-account highlights.");
	}
}

static void TestLateAccountResponses(BOOL alreadyQueued)
{
	TestSession* session = [[TestSession alloc] init];
	MBClient* client = Client(session);
	__block BOOL delivered = NO;
	[client verifyToken:@"A-token" completion:^(BOOL valid, NSError* error) { delivered = YES; }];
	if (alreadyQueued) {
		[session completeRequest:0 status:200 body:@"{\"username\":\"A-user\",\"token\":\"A-replacement\"}"];
	}
	TestAppDelegate* delegate = AppDelegate(nil, client);
	[delegate signOut:delegate];
	[test_defaults setObject:@"B-token" forKey:InkwellTokenDefaultsKey];
	[test_defaults setObject:@"B-user" forKey:InkwellUsernameDefaultsKey];
	if (!alreadyQueued) {
		[session completeRequest:0 status:200 body:@"{\"username\":\"A-user\",\"token\":\"A-replacement\"}"];
	}
	DrainRunLoop();
	Check(!delivered, @"Ignore old responses even if delivery was already queued.");
	Check([[test_defaults stringForKey:InkwellTokenDefaultsKey] isEqual:@"B-token"] && [[test_defaults stringForKey:InkwellUsernameDefaultsKey] isEqual:@"B-user"], @"Old verification must not overwrite the new account.");
	NSUInteger request_count = session.requests.count;
	[client verifyToken:@"A-token" completion:^(BOOL valid, NSError* error) { delivered = YES; }];
	Check(session.requests.count == request_count, @"Retired clients cannot start requests.");
}

static void TestBackgroundResponseAfterSignOut(void)
{
	TestSession* session = [[TestSession alloc] init];
	MBClient* client = Client(session);
	__block BOOL delivered = NO;
	[client fetchMicropubDestinationsInBackgroundWithToken:@"A-token" completion:^(NSArray* destinations, NSError* error) { delivered = YES; }];
	[client invalidate];
	NSUInteger initial_cache_path_count = cache_path_count;
	[session completeRequest:0 status:200 body:@"{\"destination\":[{\"uid\":\"A-blog\",\"name\":\"A blog\"}]}"];
	DrainRunLoop();
	Check(!delivered && cache_path_count == initial_cache_path_count, @"Background responses cannot recreate caches after sign-out.");
}

static void TestLateAuthorizationCompletion(void)
{
	TestSession* session = [[TestSession alloc] init];
	MBClient* client = Client(session);
	MBAuthController* auth_controller = [[MBAuthController alloc] initWithClient:client];
	[auth_controller setValue:@"state" forKey:@"pendingState"];
	TestAppDelegate* delegate = AppDelegate(nil, client);
	[delegate setValue:auth_controller forKey:@"authController"];
	[delegate application:NSApp openURLs:@[ [NSURL URLWithString:@"inkwell://signin?code=code&state=state"] ]];
	[session completeRequest:0 status:200 body:@"{\"access_token\":\"A-token\"}"];
	DrainRunLoop();
	Check(session.requests.count == 2, @"Authorization proceeds to token verification.");
	[session completeRequest:1 status:200 body:@"{\"username\":\"A-user\",\"has_inkwell\":true}"];
	TestSession* new_session = [[TestSession alloc] init];
	dispatch_async(dispatch_get_main_queue(), ^{
		[delegate signOut:delegate];
		MBClient* new_client = [delegate valueForKey:@"client"];
		[[new_client valueForKey:@"session"] invalidateAndCancel];
		[new_client setValue:new_session forKey:@"session"];
		[test_defaults setObject:@"B-token" forKey:InkwellTokenDefaultsKey];
	});
	DrainRunLoop();
	Check([[test_defaults stringForKey:InkwellTokenDefaultsKey] isEqual:@"B-token"], @"Already queued authorization results cannot restore the old account.");
	Check(new_session.requests.count == 0, @"Old authorization must not start verification on the new client.");
}

static void TestPodcastTeardown(void)
{
	MBPodcastController* controller = [[MBPodcastController alloc] init];
	[controller setValue:[NSMutableArray arrayWithObject:@{ @"entry_id": @42 }] forKey:@"playbackRecords"];
	NSTimer* timer = [NSTimer scheduledTimerWithTimeInterval:60.0 target:controller selector:@selector(playbackSaveTimerDidFire:) userInfo:nil repeats:YES];
	[controller setValue:timer forKey:@"playbackSaveTimer"];
	[controller setValue:@YES forKey:@"isPlaying"];
	[controller invalidate];
	Check(!timer.isValid && [controller valueForKey:@"playbackSaveTimer"] == nil, @"Sign-out stops the player history timer.");
	Check(![[controller valueForKey:@"isPlaying"] boolValue], @"Sign-out stops playback.");
	NSUInteger initial_cache_path_count = cache_path_count;
	[controller persistPlaybackRecordsToDisk];
	Check([[controller valueForKey:@"playbackRecords"] count] == 0, @"Player teardown clears account history.");
	controller = nil;
	Check(cache_path_count == initial_cache_path_count, @"Player teardown and deallocation cannot restore cleared history files.");
}

int main(void)
{
	@autoreleasepool {
		[NSApplication sharedApplication];
		NSString* suite_name = [@"InkwellPostLifecycleTests." stringByAppendingString:NSUUID.UUID.UUIDString];
		test_defaults = [[NSUserDefaults alloc] initWithSuiteName:suite_name];
		Method defaults_method = class_getClassMethod(NSUserDefaults.class, @selector(standardUserDefaults));
		Method test_defaults_method = class_getClassMethod(NSUserDefaults.class, @selector(postTestDefaults));
		Method session_method = class_getClassMethod(NSURLSession.class, @selector(sharedSession));
		Method test_session_method = class_getClassMethod(NSURLSession.class, @selector(postTestSharedSession));
		Method alert_method = class_getInstanceMethod(NSAlert.class, @selector(runModal));
		Method test_alert_method = class_getInstanceMethod(NSAlert.class, @selector(postTestRunModal));
		method_exchangeImplementations(defaults_method, test_defaults_method);
		method_exchangeImplementations(session_method, test_session_method);
		method_exchangeImplementations(alert_method, test_alert_method);
		@try {
			TestErrorResponses();
			TestEditsDuringSave(NO);
			TestEditsDuringSave(YES);
			TestPublishedClose(NO);
			TestPublishedClose(YES);
			TestQuit(NSAlertFirstButtonReturn, NO);
			TestQuit(NSAlertFirstButtonReturn, YES);
			TestQuit(NSAlertSecondButtonReturn, NO);
			TestQuit(NSAlertThirdButtonReturn, NO);
			TestMultipleWindowsAndPendingSave();
			TestEditorFailureAndEmptyQuit();
			TestSignOutDuringSave(NO, NO);
			TestSignOutDuringSave(YES, NO);
			TestSignOutDuringSave(NO, YES);
			TestSignOut(YES);
			TestSignOut(NO);
			TestLateAccountResponses(NO);
			TestLateAccountResponses(YES);
			TestBackgroundResponseAfterSignOut();
			TestLateAuthorizationCompletion();
			TestPodcastTeardown();
			fprintf(stdout, "%lu post and account lifecycle checks passed.\n", (unsigned long) check_count);
		}
		@finally {
			method_exchangeImplementations(defaults_method, test_defaults_method);
			method_exchangeImplementations(session_method, test_session_method);
			method_exchangeImplementations(alert_method, test_alert_method);
			[test_defaults removePersistentDomainForName:suite_name];
		}
	}
	return 0;
}
