//
//  MBPodcastController.m
//  Inkwell
//
//  Created by Codex on 3/18/26.
//

#import "MBPodcastController.h"
#import "MBEntry.h"

@interface MBPodcastController ()

@property (nonatomic, strong) NSButton* playButton;
@property (nonatomic, assign, readwrite) BOOL isPlaying;

- (void) updatePlaybackButtonImage;
- (IBAction) togglePlayback:(id) sender;

@end

@implementation MBPodcastController

- (void) loadView
{
	NSView* container_view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 260.0, 96.0)];
	container_view.translatesAutoresizingMaskIntoConstraints = NO;
	container_view.wantsLayer = YES;
	container_view.layer.backgroundColor = [NSColor systemOrangeColor].CGColor;

	NSButton* play_button = [NSButton buttonWithTitle:@"" target:self action:@selector(togglePlayback:)];
	play_button.translatesAutoresizingMaskIntoConstraints = NO;
	play_button.bezelStyle = NSBezelStyleTexturedRounded;
	play_button.imagePosition = NSImageOnly;

	[container_view addSubview:play_button];
	[NSLayoutConstraint activateConstraints:@[
		[play_button.centerXAnchor constraintEqualToAnchor:container_view.centerXAnchor],
		[play_button.centerYAnchor constraintEqualToAnchor:container_view.centerYAnchor]
	]];

	self.playButton = play_button;
	self.view = container_view;
	[self updatePlaybackButtonImage];
}

- (void) setEntry:(MBEntry* _Nullable) entry
{
	_entry = entry;
}

- (void) updatePlaybackButtonImage
{
	NSString* symbol_name = self.isPlaying ? @"stop.fill" : @"play.fill";
	NSString* accessibility_description = self.isPlaying ? @"Stop" : @"Play";
	self.playButton.image = [NSImage imageWithSystemSymbolName:symbol_name accessibilityDescription:accessibility_description];
}

- (IBAction) togglePlayback:(id) sender
{
	#pragma unused(sender)
	self.isPlaying = !self.isPlaying;
	[self updatePlaybackButtonImage];

	if (self.playbackStateChangedHandler != nil) {
		self.playbackStateChangedHandler(self.isPlaying);
	}
}

@end
