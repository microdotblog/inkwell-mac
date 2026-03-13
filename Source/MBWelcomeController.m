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
	NSRect frame = NSMakeRect(0.0, 0.0, 500.0, 250.0);
	NSUInteger style_mask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable;
	NSWindow* window = [[NSWindow alloc] initWithContentRect:frame styleMask:style_mask backing:NSBackingStoreBuffered defer:NO];

	self = [super initWithWindow:window];
	if (self) {
		[self setupWindow];
		[self setupContent];
	}
	return self;
}

- (void) setupWindow
{
	self.window.title = @"Welcome to Inkwell";
	self.window.releasedWhenClosed = NO;
	self.window.movableByWindowBackground = YES;
	[[self.window standardWindowButton:NSWindowCloseButton] setEnabled:NO];
	[self.window center];
}

- (void) setupContent
{
	NSView* content_view = self.window.contentView;
	if (content_view == nil) {
		return;
	}

	NSBox* background_box = [[NSBox alloc] initWithFrame:NSZeroRect];
	background_box.translatesAutoresizingMaskIntoConstraints = NO;
	background_box.boxType = NSBoxCustom;
	background_box.borderWidth = 0.0;
	background_box.fillColor = [NSColor colorNamed:@"color_welcome_background"];
	[content_view addSubview:background_box];

	NSImageView* app_icon_view = [[NSImageView alloc] initWithFrame:NSZeroRect];
	app_icon_view.translatesAutoresizingMaskIntoConstraints = NO;
	app_icon_view.image = [NSImage imageNamed:@"icon_inkwell"];
	app_icon_view.imageScaling = NSImageScaleProportionallyUpOrDown;
	[content_view addSubview:app_icon_view];

	NSTextField* description_field = [NSTextField wrappingLabelWithString:@"Inkwell is a feed reader that syncs with Micro.blog.\n\nMake highlights to remember passages later or to blog quotes from them."];
	description_field.translatesAutoresizingMaskIntoConstraints = NO;
	description_field.font = [NSFont systemFontOfSize:15.0];
	description_field.textColor = [NSColor labelColor];
	description_field.maximumNumberOfLines = 0;
	[content_view addSubview:description_field];

	NSImage* micro_icon = [[NSImage imageNamed:@"icon_micro"] copy];
	micro_icon.size = NSMakeSize(16.0, 16.0);

	NSButton* sign_in_button = [NSButton buttonWithTitle:@"Sign in with Micro.blog" target:self action:@selector(signInWithMicroblog:)];
	sign_in_button.translatesAutoresizingMaskIntoConstraints = NO;
	sign_in_button.bezelStyle = NSBezelStyleRounded;
	sign_in_button.controlSize = NSControlSizeLarge;
	sign_in_button.image = micro_icon;
	sign_in_button.imagePosition = NSImageLeading;
	sign_in_button.imageScaling = NSImageScaleProportionallyDown;

	NSBox* separator_box = [[NSBox alloc] initWithFrame:NSZeroRect];
	separator_box.translatesAutoresizingMaskIntoConstraints = NO;
	separator_box.boxType = NSBoxSeparator;
	[content_view addSubview:separator_box];

	[content_view addSubview:sign_in_button];
	[NSLayoutConstraint activateConstraints:@[
		[background_box.topAnchor constraintEqualToAnchor:content_view.topAnchor],
		[background_box.leadingAnchor constraintEqualToAnchor:content_view.leadingAnchor],
		[background_box.trailingAnchor constraintEqualToAnchor:content_view.trailingAnchor],
		[background_box.bottomAnchor constraintEqualToAnchor:content_view.bottomAnchor],
		[app_icon_view.leadingAnchor constraintEqualToAnchor:content_view.leadingAnchor constant:40.0],
		[app_icon_view.topAnchor constraintEqualToAnchor:content_view.topAnchor constant:38.0],
		[app_icon_view.widthAnchor constraintEqualToConstant:96.0],
		[app_icon_view.heightAnchor constraintEqualToConstant:96.0],
		[description_field.leadingAnchor constraintEqualToAnchor:app_icon_view.trailingAnchor constant:28.0],
		[description_field.centerYAnchor constraintEqualToAnchor:app_icon_view.centerYAnchor],
		[description_field.trailingAnchor constraintEqualToAnchor:content_view.trailingAnchor constant:-40.0],
		[separator_box.leadingAnchor constraintEqualToAnchor:content_view.leadingAnchor constant:20.0],
		[separator_box.trailingAnchor constraintEqualToAnchor:content_view.trailingAnchor constant:-20.0],
		[separator_box.bottomAnchor constraintEqualToAnchor:sign_in_button.topAnchor constant:-20.0],
		[sign_in_button.centerXAnchor constraintEqualToAnchor:content_view.centerXAnchor],
		[sign_in_button.bottomAnchor constraintEqualToAnchor:content_view.bottomAnchor constant:-28.0]
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
