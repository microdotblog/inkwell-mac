//
//  MBWelcomeController.m
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import "MBWelcomeController.h"

@implementation MBWelcomeController

- (instancetype) init
{
	NSRect frame = NSMakeRect(0.0, 0.0, 460.0, 320.0);
	NSUInteger style_mask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable;
	NSWindow *window = [[NSWindow alloc] initWithContentRect:frame styleMask:style_mask backing:NSBackingStoreBuffered defer:NO];

	self = [super initWithWindow:window];
	if (self) {
		[self setupWindow];
		[self setupContent];
	}
	return self;
}

- (void) setupWindow
{
	self.window.title = @"Welcome";
	self.window.releasedWhenClosed = NO;
	self.window.movableByWindowBackground = YES;
	[self.window center];
}

- (void) setupContent
{
	NSView *content_view = self.window.contentView;
	if (content_view == nil) {
		return;
	}

	NSButton *sign_in_button = [NSButton buttonWithTitle:@"Sign in with Micro.blog" target:self action:@selector(signInWithMicroblog:)];
	sign_in_button.translatesAutoresizingMaskIntoConstraints = NO;
	sign_in_button.bezelStyle = NSBezelStyleRounded;
	sign_in_button.controlSize = NSControlSizeLarge;

	[content_view addSubview:sign_in_button];
	[NSLayoutConstraint activateConstraints:@[
		[sign_in_button.centerXAnchor constraintEqualToAnchor:content_view.centerXAnchor],
		[sign_in_button.centerYAnchor constraintEqualToAnchor:content_view.centerYAnchor]
	]];
}

- (void) showWindow:(id)sender
{
	[super showWindow:sender];
	[self.window makeKeyAndOrderFront:sender];
	[NSApp activateIgnoringOtherApps:YES];
}

- (void) signInWithMicroblog:(id)sender
{
	if (self.signInHandler != nil) {
		self.signInHandler();
	}
}

@end
