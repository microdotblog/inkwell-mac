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

@interface MBAppDelegate ()

@property (strong) IBOutlet NSWindow *window;
@property (strong) MBAuthController *authController;
@property (strong) MBMainController *mainController;
@property (strong) MBSessionController *sessionController;
@property (strong) MBWelcomeController *welcomeController;

@end

@implementation MBAppDelegate

- (void) applicationDidFinishLaunching:(NSNotification *)aNotification
{
	MBClient *client = [[MBClient alloc] init];
	self.authController = [[MBAuthController alloc] initWithClient:client];
	self.sessionController = [[MBSessionController alloc] init];

	if ([self.sessionController hasToken]) {
		[self showMainWindow];
		return;
	}

	[self showWelcomeWindow];
}

- (void) application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls
{
	for (NSURL *url in urls) {
		BOOL was_handled = [self.authController handleCallbackURL:url completion:^(NSString * _Nullable token, NSError * _Nullable error) {
			if (error != nil || token.length == 0) {
				NSString *error_message = error.localizedDescription ?: @"Sign in failed.";
				[self presentSignInError:error_message];
				return;
			}

			[self.sessionController saveToken:token];
			[self closeWelcomeWindow];
			[self showMainWindow];
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
		self.mainController = [[MBMainController alloc] initWithWindow:self.window];
	}

	[self.mainController showWindow:nil];
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
	alert.messageText = @"Sign In Failed";
	alert.informativeText = message;
	if (self.welcomeController.window != nil) {
		[alert beginSheetModalForWindow:self.welcomeController.window completionHandler:nil];
	}
	else {
		[alert runModal];
	}
}

@end
