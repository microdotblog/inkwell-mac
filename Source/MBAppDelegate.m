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
#import "MBNewPostController.h"
#import "MBPodcastController.h"
#import "MBSessionController.h"
#import "MBWelcomeController.h"

static NSString* const InkwellUnavailableMessage = @"Inkwell requires a Micro.blog subscription.";
static NSString* const InkwellHelpURLString = @"https://help.micro.blog/t/about-inkwell/4302";
static NSString* const InkwellShowTitleFieldDefaultsKey = @"ShowTitleField";

@interface MBAppDelegate ()

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

- (void) applicationWillTerminate:(NSNotification *)notification
{
	#pragma unused(notification)
	[MBPodcastController cleanupCachedAudioFiles];
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
		NSString* token_value = [self.sessionController token] ?: @"";
		self.mainController = [[MBMainController alloc] initWithWindow:nil client:self.client token:token_value];
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

- (IBAction) showHelp:(id) sender
{
	#pragma unused(sender)

	NSURL* help_url = [NSURL URLWithString:InkwellHelpURLString];
	if (help_url == nil) {
		return;
	}

	[[NSWorkspace sharedWorkspace] openURL:help_url];
}

- (IBAction) preview:(id) sender
{
	NSWindowController* window_controller = NSApp.keyWindow.windowController;
	if (![window_controller isKindOfClass:[MBNewPostController class]]) {
		return;
	}

	[(MBNewPostController*) window_controller preview:sender];
}

- (IBAction) toggleTitleField:(id) sender
{
	NSWindowController* window_controller = NSApp.keyWindow.windowController;
	if (![window_controller isKindOfClass:[MBNewPostController class]]) {
		return;
	}

	[(MBNewPostController*) window_controller toggleTitleField:sender];
}

- (BOOL) validateMenuItem:(NSMenuItem*) menu_item
{
	if (menu_item.action == @selector(preview:)) {
		NSWindowController* window_controller = NSApp.keyWindow.windowController;
		BOOL is_new_post_window_frontmost = [window_controller isKindOfClass:[MBNewPostController class]];
		menu_item.state = (is_new_post_window_frontmost && [(MBNewPostController*) window_controller isPreviewEnabled]) ? NSControlStateValueOn : NSControlStateValueOff;
		return is_new_post_window_frontmost;
	}

	if (menu_item.action == @selector(toggleTitleField:)) {
		NSWindowController* window_controller = NSApp.keyWindow.windowController;
		BOOL is_new_post_window_frontmost = [window_controller isKindOfClass:[MBNewPostController class]];
		menu_item.state = [[NSUserDefaults standardUserDefaults] boolForKey:InkwellShowTitleFieldDefaultsKey] ? NSControlStateValueOn : NSControlStateValueOff;
		return is_new_post_window_frontmost;
	}

	return YES;
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
