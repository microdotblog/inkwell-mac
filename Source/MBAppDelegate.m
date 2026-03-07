//
//  MBAppDelegate.m
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import "MBAppDelegate.h"
#import "MBAuthController.h"
#import "MBClient.h"
#import "MBMainController.h"
#import "MBSessionController.h"
#import "MBWelcomeController.h"

static NSString* const InkwellUnavailableMessage = @"Inkwell is not enabled for your account yet.";

@interface MBAppDelegate ()

@property (strong) IBOutlet NSWindow *window;
@property (strong) MBAuthController *authController;
@property (strong) MBClient *client;
@property (strong) MBMainController *mainController;
@property (strong) MBSessionController *sessionController;
@property (strong) MBWelcomeController *welcomeController;

@end

@implementation MBAppDelegate

- (void) applicationDidFinishLaunching:(NSNotification *)aNotification
{
	self.client = [[MBClient alloc] init];
	self.authController = [[MBAuthController alloc] initWithClient:self.client];
	self.sessionController = [[MBSessionController alloc] init];

	if ([self.sessionController hasToken]) {
		[self verifySavedTokenAndContinue];
		return;
	}

	[self showWelcomeWindow];
}

- (void) application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls
{
	#pragma unused(application)

	for (NSURL *url in urls) {
		BOOL was_handled = [self.authController handleCallbackURL:url completion:^(NSString * _Nullable token, NSError * _Nullable error) {
			if (error != nil || token.length == 0) {
				NSString *error_message = error.localizedDescription ?: @"Sign in failed.";
				[self presentSignInError:error_message];
				return;
			}

			[self.sessionController saveToken:token];
			[self verifySavedTokenAndContinue];
		}];

		if (was_handled) {
			break;
		}
	}
}

- (void) applicationWillTerminate:(NSNotification *)aNotification
{
	// Insert code here to tear down your application
}

- (BOOL) applicationSupportsSecureRestorableState:(NSApplication *)app
{
	return YES;
}

- (void) verifySavedTokenAndContinue
{
	NSString* token_value = [self.sessionController token] ?: @"";
	__weak typeof(self) weak_self = self;
	[self.client verifyToken:token_value completion:^(BOOL is_valid, NSError * _Nullable verify_error) {
		MBAppDelegate* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		if (is_valid && verify_error == nil) {
			[strong_self closeWelcomeWindow];
			[strong_self showMainWindow];
			return;
		}

		[strong_self.sessionController clearToken];
		[strong_self showWelcomeWindow];
		NSString* error_message = verify_error.localizedDescription ?: @"Sign in failed.";
		[strong_self presentSignInError:error_message];
	}];
}

- (void) showWelcomeWindow
{
	[self.window orderOut:nil];

	if (self.welcomeController == nil) {
		self.welcomeController = [[MBWelcomeController alloc] init];

		__weak typeof(self) weak_self = self;
		self.welcomeController.signInHandler = ^{
			[weak_self beginSignIn];
		};
	}

	[self.welcomeController showWindow:nil];
}

- (void) closeWelcomeWindow
{
	[self.welcomeController close];
	self.welcomeController = nil;
}

- (void) showMainWindow
{
	if (self.mainController == nil) {
		NSString *token_value = [self.sessionController token] ?: @"";
		self.mainController = [[MBMainController alloc] initWithWindow:self.window client:self.client token:token_value];
	}

	[self.mainController showWindow:nil];
}

- (IBAction) showMainWindowAction:(id) sender
{
	#pragma unused(sender)
	[self showMainWindow];
}

- (IBAction) showPreferences:(id) sender
{
	#pragma unused(sender)
	[self.mainController showPreferences:self];
}

- (IBAction) signOut:(id) sender
{
	#pragma unused(sender)

	[self.sessionController clearToken];
	[self.mainController close];
	self.mainController = nil;
	[self showWelcomeWindow];
}

- (void) beginSignIn
{
	[self.authController beginSignInWithCompletion:^(NSError * _Nullable error) {
		if (error != nil) {
			[self presentSignInError:error.localizedDescription];
		}
	}];
}

- (void) presentSignInError:(NSString *)message
{
	NSAlert *alert = [[NSAlert alloc] init];
	alert.alertStyle = NSAlertStyleWarning;
	if ([message isEqualToString:InkwellUnavailableMessage]) {
		alert.messageText = InkwellUnavailableMessage;
		alert.informativeText = @"";
	}
	else {
		alert.messageText = @"Sign In Failed";
		alert.informativeText = message;
	}
	if (self.welcomeController.window != nil) {
		[alert beginSheetModalForWindow:self.welcomeController.window completionHandler:nil];
	}
	else {
		[alert runModal];
	}
}

@end
