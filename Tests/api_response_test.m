#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "MBAppDelegate.h"
#import "MBClient.h"
#import "MBPathUtilities.h"
#import "MBSessionController.h"

// Link the real app delegate without opening windows or loading its other controllers.
#define STUB_CONTROLLER(name) @interface name : NSObject @end @implementation name @end
STUB_CONTROLLER(MBAuthController)
STUB_CONTROLLER(MBAvatarLoader)
STUB_CONTROLLER(MBExportController)
STUB_CONTROLLER(MBImportController)
STUB_CONTROLLER(MBMainController)
STUB_CONTROLLER(MBNewPostController)
STUB_CONTROLLER(MBPodcastController)
STUB_CONTROLLER(MBWelcomeController)

static NSUserDefaults* test_defaults;
static NSUInteger cleared_cache_count;
static NSUInteger test_count;

@interface NSUserDefaults (APITests)
+ (NSUserDefaults *) apiTestDefaults;
@end

@implementation NSUserDefaults (APITests)
+ (NSUserDefaults *) apiTestDefaults
{
	return test_defaults;
}
@end

// Keep all cache and defaults operations away from the user's actual account.
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
	return nil;
}
+ (void) cleanupLegacyFiles
{
}
+ (void) clearUserScopedCacheFiles
{
	cleared_cache_count += 1;
}
@end

@interface APITestTask : NSObject
@property (copy) void (^responseHandler)(void);
- (void) resume;
@end

@implementation APITestTask
- (void) resume
{
	self.responseHandler();
	self.responseHandler = nil;
}
@end

@interface APITestSession : NSObject
@property (copy) NSData* data;
@property (assign) NSInteger statusCode;
@property (strong) NSError* error;
@end

@implementation APITestSession
- (NSURLSessionDataTask *) dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler
{
	NSHTTPURLResponse* response = [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:self.statusCode HTTPVersion:@"HTTP/1.1" headerFields:nil];
	APITestTask* task = [[APITestTask alloc] init];
	task.responseHandler = ^{
		completionHandler(self.data, response, self.error);
	};
	return (NSURLSessionDataTask*) task;
}
@end

@interface MBAppDelegate (APITests)
- (void) verifySavedTokenAndContinue;
- (void) closeWelcomeWindow;
- (void) showMainWindow;
- (void) showWelcomeWindow;
- (void) presentSignInError:(NSString *)message;
@end

@interface APITestAppDelegate : MBAppDelegate
@property (assign) BOOL mainWindowShown;
@property (assign) BOOL welcomeWindowShown;
@property (copy) NSString* signInError;
@end

@implementation APITestAppDelegate
- (void) closeWelcomeWindow
{
	self.welcomeWindowShown = NO;
}
- (void) showMainWindow
{
	self.mainWindowShown = YES;
}
- (void) showWelcomeWindow
{
	self.welcomeWindowShown = YES;
}
- (void) presentSignInError:(NSString *)message
{
	self.signInError = message;
}
@end

static void Check(BOOL condition, NSString* message)
{
	if (!condition) {
		fprintf(stderr, "FAIL: %s\n", message.UTF8String);
		exit(1);
	}
}

static void WaitForCompletion(BOOL (^isFinished)(void))
{
	NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
	while (!isFinished() && deadline.timeIntervalSinceNow > 0) {
		[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
	}
	Check(isFinished(), @"Request completion timed out.");
}

static MBClient* ClientForResponse(NSInteger statusCode, id body, NSError* error)
{
	APITestSession* session = [[APITestSession alloc] init];
	session.statusCode = statusCode;
	session.data = [body isKindOfClass:[NSString class]] ? [body dataUsingEncoding:NSUTF8StringEncoding] : nil;
	session.error = error;
	MBClient* client = [[MBClient alloc] init];
	[[client valueForKey:@"session"] invalidateAndCancel];
	[client setValue:session forKey:@"session"];
	return client;
}

static void TestServerErrors(void)
{
	NSArray* bodies = @[
		@"<html>Service unavailable</html>", @"", @"{invalid",
		@"{\"error\":null}", @"{\"error_description\":null}",
		@"{\"error\":503}", @"{\"error\":{\"message\":\"unavailable\"}}",
		@"{\"error_description\":[],\"error\":\"Unavailable\"}",
		@"{\"error_description\":\"Try later\"}", [NSNull null]
	];
	for (id body in bodies) {
		MBClient* client = ClientForResponse(503, body, nil);
		__block BOOL is_finished = NO;
		[client fetchFeedSubscriptionsWithToken:@"test-token" completion:^(NSArray* subscriptions, NSError* error) {
			Check([NSThread isMainThread], @"Error completion must run on the main thread.");
			Check(subscriptions == nil && error.code == 503, @"503 response must report an error.");
			Check(error.localizedDescription.length > 0, @"503 response must include an error description.");
			if ([body isEqual:@"{\"error_description\":[],\"error\":\"Unavailable\"}"]) {
				Check([error.localizedDescription isEqualToString:@"Unavailable"], @"Use a valid error string after an invalid description.");
			}
			is_finished = YES;
		}];
		WaitForCompletion(^BOOL { return is_finished; });
		Check([[client valueForKey:@"activeRequestCount"] integerValue] == 0, @"503 must finish networking activity.");
		test_count += 1;
	}
}

static void TestSourceResponses(void)
{
	NSArray* invalid_bodies = @[
		@"<html>Service unavailable</html>", @"", @"{invalid", @"null", @"{}",
		@"{\"error\":\"unavailable\"}", @"{\"items\":null}", @"{\"items\":{}}",
		@"[null]", @"[123]", @"[{}]", @"[{\"properties\":[]}]",
		@"{\"items\":[{\"properties\":{\"content\":[\"Valid\"]}},null]}", [NSNull null]
	];
	NSArray* valid_bodies = @[
		@"[]", @"{\"items\":[]}",
		@"{\"items\":[{\"properties\":{\"name\":[\"Title\"],\"content\":[\"Body\"]}}]}",
		@"[{\"properties\":{\"content\":[\"Body\"]}}]",
		@"{\"properties\":{\"content\":[\"Body\"]}}", @"{\"content\":\"Body\"}"
	];
	for (NSNumber* draft_flag in @[ @NO, @YES ]) {
		for (NSArray* bodies in @[ invalid_bodies, valid_bodies ]) {
			BOOL expects_error = bodies == invalid_bodies;
			for (id body in bodies) {
				MBClient* client = ClientForResponse(200, body, nil);
				__block BOOL is_finished = NO;
				void (^completion)(NSArray*, NSError*) = ^(NSArray* entries, NSError* error) {
					Check([NSThread isMainThread], @"Posts completion must run on the main thread.");
					if (expects_error) {
						Check(entries == nil && error.code == 1065, @"Invalid posts/drafts response must fail instead of returning an empty list.");
					}
					else {
						Check(entries != nil && error == nil, @"Valid posts/drafts response must succeed.");
						BOOL expects_empty = [body isEqual:@"[]"] || [body isEqual:@"{\"items\":[]}"];
						Check(entries.count == (expects_empty ? 0 : 1), @"Preserve valid empty and nonempty results.");
						if (!expects_empty) {
							Check([entries[0][@"is_draft"] boolValue] == draft_flag.boolValue, @"Preserve the draft flag.");
							Check([entries[0][@"content"] isEqualToString:@"Body"], @"Preserve source content.");
						}
					}
					is_finished = YES;
				};
				if (draft_flag.boolValue) {
					[client fetchDraftEntriesForDestinationUID:@"example.micro.blog" token:@"test-token" completion:completion];
				}
				else {
					[client fetchPostEntriesForDestinationUID:@"example.micro.blog" token:@"test-token" completion:completion];
				}
				WaitForCompletion(^BOOL { return is_finished; });
				Check([[client valueForKey:@"activeRequestCount"] integerValue] == 0, @"Posts must finish networking activity.");
				test_count += 1;
			}
		}
	}
}

static void TestStartup(NSInteger statusCode, id body, NSError* error, BOOL shouldSignOut)
{
	[test_defaults setObject:@"saved-token" forKey:InkwellTokenDefaultsKey];
	[test_defaults setObject:@"saved-user" forKey:InkwellUsernameDefaultsKey];
	[test_defaults setObject:@"cached-destination" forKey:InkwellCurrentDestinationDefaultsKey];
	NSUInteger initial_clear_count = cleared_cache_count;
	MBClient* client = ClientForResponse(statusCode, body, error);
	MBSessionController* session_controller = [[MBSessionController alloc] init];
	APITestAppDelegate* app_delegate = [[APITestAppDelegate alloc] init];
	[app_delegate setValue:client forKey:@"client"];
	[app_delegate setValue:session_controller forKey:@"sessionController"];
	[app_delegate verifySavedTokenAndContinue];
	WaitForCompletion(^BOOL { return app_delegate.mainWindowShown || app_delegate.welcomeWindowShown; });
	Check(app_delegate.mainWindowShown == !shouldSignOut, @"Open the main window after temporary failures.");
	Check(app_delegate.welcomeWindowShown == shouldSignOut, @"Return to sign-in only after credential/subscription rejection.");
	Check(session_controller.hasToken == !shouldSignOut, @"Preserve the token during temporary failures.");
	Check(cleared_cache_count == initial_clear_count + (shouldSignOut ? 1 : 0), @"Preserve user caches during temporary failures.");
	Check((app_delegate.signInError != nil) == shouldSignOut, @"Show sign-in errors for rejected credentials.");
	if (!shouldSignOut) {
		Check([[test_defaults stringForKey:InkwellCurrentDestinationDefaultsKey] isEqualToString:@"cached-destination"], @"Preserve the selected destination.");
	}
	Check([[client valueForKey:@"activeRequestCount"] integerValue] == 0, @"Verification must finish networking activity.");
	test_count += 1;
}

int main(void)
{
	@autoreleasepool {
		NSString* suite_name = [@"InkwellAPIResponseTests." stringByAppendingString:NSUUID.UUID.UUIDString];
		test_defaults = [[NSUserDefaults alloc] initWithSuiteName:suite_name];
		Method standard_method = class_getClassMethod([NSUserDefaults class], @selector(standardUserDefaults));
		Method test_method = class_getClassMethod([NSUserDefaults class], @selector(apiTestDefaults));
		method_exchangeImplementations(standard_method, test_method);
		@try {
			TestServerErrors();
			TestSourceResponses();
			TestStartup(503, @"<html>Unavailable</html>", nil, NO);
			TestStartup(502, @"{\"error\":null}", nil, NO);
			TestStartup(504, @"{\"error\":504}", nil, NO);
			TestStartup(200, @"{invalid", nil, NO);
			TestStartup(200, @"[]", nil, NO);
			TestStartup(200, @"{\"error\":null}", nil, NO);
			TestStartup(200, [NSNull null], nil, NO);
			TestStartup(0, nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil], NO);
			TestStartup(0, nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil], NO);
			TestStartup(401, @"{\"error\":\"Invalid token\"}", nil, YES);
			TestStartup(403, @"Forbidden", nil, YES);
			TestStartup(200, @"{\"error\":\"App token was not valid.\"}", nil, YES);
			TestStartup(200, @"{\"has_inkwell\":false}", nil, YES);
			TestStartup(200, @"{\"has_inkwell\":true,\"username\":\"verified-user\",\"token\":\"replacement-token\"}", nil, NO);
			Check([[test_defaults stringForKey:InkwellTokenDefaultsKey] isEqualToString:@"replacement-token"], @"Save replacement tokens after successful verification.");
			fprintf(stdout, "%lu API response cases passed.\n", (unsigned long) test_count);
		}
		@finally {
			method_exchangeImplementations(standard_method, test_method);
			[test_defaults removePersistentDomainForName:suite_name];
		}
	}
	return 0;
}
