//
//  MBAppDelegate.m
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import "MBAppDelegate.h"
#import "MBAvatarLoader.h"
#import "MBAuthController.h"
#import "MBClient.h"
#import "MBMainController.h"
#import "MBNewPostController.h"
#import "MBExportController.h"
#import "MBImportController.h"
#import "MBPodcastController.h"
#import "MBSessionController.h"
#import "MBWelcomeController.h"
#import "NSMenuItem+RSCore.h"

static NSString* const InkwellUnavailableMessage = @"Inkwell requires a Micro.blog subscription.";
static NSString* const InkwellHelpURLString = @"https://help.micro.blog/t/about-inkwell/4302";
static NSString* const InkwellShowTitleFieldDefaultsKey = @"ShowTitleField";

@interface MBAppDelegate ()

@property (strong) MBAuthController *authController;
@property (strong) MBClient *client;
@property (strong) MBMainController *mainController;
@property (strong) MBExportController *exportController;
@property (strong) MBImportController *importController;
@property (strong) MBSessionController *sessionController;
@property (strong) MBWelcomeController *welcomeController;
@property (assign) BOOL isPreparingToClose;
@property (assign) BOOL isTerminating;

- (void) resetSession;

@end

@implementation MBAppDelegate

- (void) applicationDidFinishLaunching:(NSNotification *)aNotification
{
	if (![[NSUserDefaults standardUserDefaults] boolForKey:@"ShowMenuIcons"]) {
		[NSMenuItem rs_disableIcons];
	}

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

	MBAuthController* auth_controller = self.authController;
	for (NSURL *url in urls) {
		BOOL was_handled = [auth_controller handleCallbackURL:url completion:^(NSString * _Nullable token, NSError * _Nullable error) {
			if (self.authController != auth_controller) {
				return;
			}
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
	[MBAvatarLoader cleanupCachedImageFiles];
	[MBPodcastController cleanupCachedAudioFiles];
}

- (NSApplicationTerminateReply) applicationShouldTerminate:(NSApplication *)application
{
	if (self.isPreparingToClose) {
		return self.isTerminating ? NSTerminateLater : NSTerminateCancel;
	}
	if (![self.mainController hasOpenPostWindows]) {
		return NSTerminateNow;
	}
	self.isPreparingToClose = YES;
	self.isTerminating = YES;
	[self.mainController closePostWindowsWithCompletion:^(BOOL did_close) {
		// AppKit must receive the reply after this method returns NSTerminateLater.
		dispatch_async(dispatch_get_main_queue(), ^{
			self.isPreparingToClose = NO;
			self.isTerminating = NO;
			[application replyToApplicationShouldTerminate:did_close];
		});
	}];
	return NSTerminateLater;
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

		BOOL is_sign_in_error = [verify_error.domain isEqualToString:MBClientErrorDomain] && (verify_error.code == 401 || verify_error.code == 403 || verify_error.code == 1025);
		if (!is_sign_in_error) {
			[strong_self closeWelcomeWindow];
			[strong_self showMainWindow];
			return;
		}

		[strong_self resetSession];
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

- (void) setupMainControllerIfNeeded
{
	if (self.mainController == nil) {
		NSString* token_value = [self.sessionController token] ?: @"";
		self.mainController = [[MBMainController alloc] initWithWindow:nil client:self.client token:token_value];
	}
}

- (void) showMainWindow
{
	[self setupMainControllerIfNeeded];
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

- (IBAction) openPostWindow:(id) sender
{
	[self setupMainControllerIfNeeded];
	[self.mainController openPostWindow:sender];
}

- (IBAction) saveDraft:(id) sender
{
	NSWindowController* window_controller = NSApp.keyWindow.windowController;
	if (![window_controller isKindOfClass:[MBNewPostController class]]) {
		return;
	}

	[(MBNewPostController*) window_controller saveDraft:sender];
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

	if (menu_item.action == @selector(saveDraft:)) {
		NSWindowController* window_controller = NSApp.keyWindow.windowController;
		BOOL is_new_post_window_frontmost = [window_controller isKindOfClass:[MBNewPostController class]];
		return (is_new_post_window_frontmost && [(MBNewPostController*) window_controller canSaveDraft]);
	}

	if (menu_item.action == @selector(toggleTitleField:)) {
		NSWindowController* window_controller = NSApp.keyWindow.windowController;
		BOOL is_new_post_window_frontmost = [window_controller isKindOfClass:[MBNewPostController class]];
		if (!is_new_post_window_frontmost) {
			menu_item.state = NSControlStateValueOff;
			return NO;
		}

		MBNewPostController* post_controller = (MBNewPostController*) window_controller;
		if (![post_controller canToggleTitleField]) {
			menu_item.state = NSControlStateValueOn;
			return NO;
		}

		menu_item.state = [[NSUserDefaults standardUserDefaults] boolForKey:InkwellShowTitleFieldDefaultsKey] ? NSControlStateValueOn : NSControlStateValueOff;
		return YES;
	}

	if (menu_item.action == @selector(importOPML:) || menu_item.action == @selector(exportOPML:)) {
		BOOL is_opml_busy = (self.importController.isImporting || self.exportController.isExporting);
		return ([self.sessionController hasToken] && !is_opml_busy);
	}

	return YES;
}

- (IBAction) importOPML:(id) sender
{
	#pragma unused(sender)

	if (![self.sessionController hasToken]) {
		NSBeep();
		return;
	}

	NSString* token_value = [self.sessionController token] ?: @"";
	self.importController = [[MBImportController alloc] initWithClient:self.client token:token_value];
	__weak typeof(self) weak_self = self;
	[self.importController beginImportFromWindow:[self presentationWindow] completion:^(BOOL didChangeFeeds) {
		MBAppDelegate* strong_self = weak_self;
		if (strong_self == nil || !didChangeFeeds) {
			return;
		}

		[strong_self.mainController refreshData];
	}];
}

- (IBAction) exportOPML:(id) sender
{
	#pragma unused(sender)

	if (![self.sessionController hasToken]) {
		NSBeep();
		return;
	}

	self.exportController = [[MBExportController alloc] initWithClient:self.client];
	[self.exportController beginExportFromWindow:[self presentationWindow]];
}

- (NSWindow *) presentationWindow
{
	if (self.mainController.window != nil && self.mainController.window.isVisible) {
		return self.mainController.window;
	}

	if (NSApp.keyWindow != nil) {
		return NSApp.keyWindow;
	}

	return NSApp.mainWindow;
}

- (IBAction) signOut:(id)sender
{
	#pragma unused(sender)

	if (self.isPreparingToClose) {
		return;
	}
	if (self.mainController == nil) {
		[self resetSession];
		[self showWelcomeWindow];
		return;
	}
	self.isPreparingToClose = YES;
	[self.mainController closePostWindowsWithCompletion:^(BOOL did_close) {
		self.isPreparingToClose = NO;
		if (did_close) {
			[self resetSession];
			[self showWelcomeWindow];
		}
	}];
}

- (void) resetSession
{
	[self.client invalidate];
	[self.mainController invalidate];
	self.mainController = nil;
	[self.importController cancelImport:self];
	self.importController = nil;
	self.exportController = nil;
	[self.sessionController clearToken];
	self.client = [[MBClient alloc] init];
	self.authController = [[MBAuthController alloc] initWithClient:self.client];
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
