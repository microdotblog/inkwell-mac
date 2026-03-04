//
//  MBAuthController.m
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import "MBAuthController.h"
#import "MBClient.h"
#import <Cocoa/Cocoa.h>

static NSString * const MBAuthControllerErrorDomain = @"MBAuthControllerErrorDomain";

@interface MBAuthController ()

@property (strong) MBClient *client;
@property (copy) NSString *pendingState;
@property (copy) NSString *callbackScheme;
@property (copy) NSString *callbackHost;

@end

@implementation MBAuthController

- (instancetype) initWithClient:(MBClient *)client
{
	self = [super init];
	if (self) {
		self.client = client;

		NSURLComponents *callback_components = [NSURLComponents componentsWithString:client.redirectURI];
		self.callbackScheme = callback_components.scheme.lowercaseString ?: @"";
		self.callbackHost = callback_components.host.lowercaseString ?: @"";
	}
	return self;
}

- (void) beginSignInWithCompletion:(void (^)(NSError * _Nullable error))completion
{
	NSString *oauth_state = NSUUID.UUID.UUIDString;
	self.pendingState = oauth_state;

	NSURL *authorization_url = [self.client authorizationURLWithState:oauth_state];
	if (authorization_url == nil) {
		NSError *error = [self errorWithCode:2001 message:@"Couldn't build sign in URL."];
		[self finishBeginWithError:error completion:completion];
		return;
	}

	BOOL did_open = [[NSWorkspace sharedWorkspace] openURL:authorization_url];
	if (!did_open) {
		NSError *error = [self errorWithCode:2002 message:@"Couldn't open your default browser."];
		[self finishBeginWithError:error completion:completion];
		return;
	}

	[self finishBeginWithError:nil completion:completion];
}

- (BOOL) handleCallbackURL:(NSURL *)url completion:(void (^)(NSString * _Nullable token, NSError * _Nullable error))completion
{
	if (![self isCallbackURL:url]) {
		return NO;
	}

	NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
	NSString *code_value = [self valueForQueryItem:@"code" fromComponents:components];
	NSString *state_value = [self valueForQueryItem:@"state" fromComponents:components];
	if (code_value.length == 0 || state_value.length == 0) {
		NSError *error = [self errorWithCode:2003 message:@"Missing sign in response data."];
		[self finishWithToken:nil error:error completion:completion];
		return YES;
	}

	if (self.pendingState.length == 0 || ![self.pendingState isEqualToString:state_value]) {
		NSError *error = [self errorWithCode:2004 message:@"Sign in state didn't match. Please try again."];
		[self finishWithToken:nil error:error completion:completion];
		return YES;
	}

	[self.client exchangeAuthorizationCode:code_value completion:^(NSString * _Nullable token, NSError * _Nullable error) {
		if (error != nil || token.length == 0) {
			NSError *resolved_error = error ?: [self errorWithCode:2005 message:@"Couldn't request an access token."];
			[self finishWithToken:nil error:resolved_error completion:completion];
			return;
		}

		[self.client verifyToken:token completion:^(BOOL is_valid, NSError * _Nullable verify_error) {
			if (!is_valid || verify_error != nil) {
				NSError *resolved_error = verify_error ?: [self errorWithCode:2006 message:@"Token verification failed."];
				[self finishWithToken:nil error:resolved_error completion:completion];
				return;
			}

			self.pendingState = nil;
			[self finishWithToken:token error:nil completion:completion];
		}];
	}];

	return YES;
}

- (BOOL) isCallbackURL:(NSURL *)url
{
	NSString *scheme_value = url.scheme.lowercaseString;
	NSString *host_value = url.host.lowercaseString;

	if (self.callbackScheme.length == 0 || self.callbackHost.length == 0) {
		return NO;
	}

	return [scheme_value isEqualToString:self.callbackScheme] && [host_value isEqualToString:self.callbackHost];
}

- (NSString * _Nullable) valueForQueryItem:(NSString *)name fromComponents:(NSURLComponents *)components
{
	for (NSURLQueryItem *query_item in components.queryItems) {
		if ([query_item.name isEqualToString:name]) {
			return query_item.value;
		}
	}
	return nil;
}

- (NSError *) errorWithCode:(NSInteger)code message:(NSString *)message
{
	return [NSError errorWithDomain:MBAuthControllerErrorDomain code:code userInfo:@{ NSLocalizedDescriptionKey: message }];
}

- (void) finishBeginWithError:(NSError * _Nullable)error completion:(void (^)(NSError * _Nullable error))completion
{
	if (completion == nil) {
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		completion(error);
	});
}

- (void) finishWithToken:(NSString * _Nullable)token error:(NSError * _Nullable)error completion:(void (^)(NSString * _Nullable token, NSError * _Nullable error))completion
{
	if (completion == nil) {
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		completion(token, error);
	});
}

@end
