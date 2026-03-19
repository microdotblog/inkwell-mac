//
//  MBPodcastController.m
//  Inkwell
//
//  Created by Codex on 3/18/26.
//

#import "MBPodcastController.h"
#import <AVFoundation/AVFoundation.h>
#import "MBAvatarLoader.h"
#import "MBEntry.h"

@interface MBPodcastSliderCell : NSSliderCell

@end

@interface MBPodcastSlider : NSSlider

@property (nonatomic, copy, nullable) void (^trackingStateChangedHandler)(BOOL is_tracking);

@end

@implementation MBPodcastSliderCell

- (CGFloat) knobThickness
{
	return 4.0;
}

- (void) drawBarInside:(NSRect) rect flipped:(BOOL) flipped
{
	#pragma unused(flipped)
	NSRect bar_rect = NSInsetRect(rect, 0.0, (NSHeight(rect) - 4.0) / 2.0);
	bar_rect.size.height = 4.0;

	NSBezierPath* background_path = [NSBezierPath bezierPathWithRoundedRect:bar_rect xRadius:2.0 yRadius:2.0];
	[[NSColor colorWithWhite:0.35 alpha:0.18] setFill];
	[background_path fill];

	CGFloat progress_fraction = 0.0;
	if (self.maxValue > self.minValue) {
		progress_fraction = (CGFloat) ((self.doubleValue - self.minValue) / (self.maxValue - self.minValue));
	}
	progress_fraction = MIN(1.0, MAX(0.0, progress_fraction));

	NSRect progress_rect = bar_rect;
	progress_rect.size.width = floor(progress_rect.size.width * progress_fraction);
	if (progress_rect.size.width <= 0.0) {
		return;
	}

	NSBezierPath* progress_path = [NSBezierPath bezierPathWithRoundedRect:progress_rect xRadius:2.0 yRadius:2.0];
	[[NSColor colorWithWhite:0.22 alpha:1.0] setFill];
	[progress_path fill];
}

- (void) drawKnob:(NSRect) knob_rect
{
	#pragma unused(knob_rect)
}

@end

@implementation MBPodcastSlider

- (void) mouseDown:(NSEvent*) event
{
	if (self.trackingStateChangedHandler != nil) {
		self.trackingStateChangedHandler(YES);
	}

	[super mouseDown:event];

	if (self.trackingStateChangedHandler != nil) {
		self.trackingStateChangedHandler(NO);
	}
}

@end

@interface MBPodcastController ()

@property (nonatomic, strong) NSView* artworkBackgroundView;
@property (nonatomic, strong) NSImageView* artworkImageView;
@property (nonatomic, strong) NSButton* backButton;
@property (nonatomic, strong) NSButton* playButton;
@property (nonatomic, strong) NSButton* forwardButton;
@property (nonatomic, strong) MBPodcastSlider* progressSlider;
@property (nonatomic, strong) MBAvatarLoader* avatarLoader;
@property (nonatomic, strong, nullable) AVPlayer* player;
@property (nonatomic, copy) NSString* currentEnclosureURLString;
@property (nonatomic, strong, nullable) id timeObserverToken;
@property (nonatomic, assign) BOOL isScrubbing;
@property (nonatomic, assign, readwrite) BOOL isPlaying;

- (NSButton*) transportButtonWithSymbolName:(NSString*) symbol_name accessibilityDescription:(NSString*) accessibility_description action:(SEL) action;
- (void) configurePlayerForCurrentEntry;
- (void) removeTimeObserverIfNeeded;
- (void) seekPlayerToSliderPositionPreservingScrubState:(BOOL) preserve_scrub_state;
- (void) setPlayingState:(BOOL) is_playing notify:(BOOL) should_notify;
- (void) updateProgressSliderForCurrentTime;
- (void) updateArtworkImage;
- (void) updatePlaybackButtonImage;
- (void) avatarImageDidLoad:(NSNotification*) notification;
- (void) playbackDidFinish:(NSNotification*) notification;
- (IBAction) skipBackward:(id) sender;
- (IBAction) togglePlayback:(id) sender;
- (IBAction) skipForward:(id) sender;
- (IBAction) scrubPlaybackPosition:(id) sender;

@end

@implementation MBPodcastController

- (instancetype) init
{
	self = [super initWithNibName:nil bundle:nil];
	if (self) {
		self.artworkURLString = @"";
		self.currentEnclosureURLString = @"";
		self.avatarLoader = [MBAvatarLoader sharedLoader];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(avatarImageDidLoad:) name:MBAvatarLoaderDidLoadImageNotification object:self.avatarLoader];
	}
	return self;
}

- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:MBAvatarLoaderDidLoadImageNotification object:self.avatarLoader];
	[self removeTimeObserverIfNeeded];
}

- (void) loadView
{
	NSView* container_view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 260.0, 118.0)];
	container_view.translatesAutoresizingMaskIntoConstraints = NO;
	container_view.wantsLayer = YES;
	NSColor* background_color = [NSColor colorNamed:@"color_podcast_background"] ?: [NSColor colorWithWhite:0.92 alpha:0.78];
	container_view.layer.backgroundColor = background_color.CGColor;

	NSView* artwork_background_view = [[NSView alloc] initWithFrame:NSZeroRect];
	artwork_background_view.translatesAutoresizingMaskIntoConstraints = NO;
	artwork_background_view.wantsLayer = YES;
	artwork_background_view.layer.cornerRadius = 5.0;
	artwork_background_view.layer.masksToBounds = YES;
	artwork_background_view.layer.backgroundColor = [NSColor colorWithWhite:0.72 alpha:1.0].CGColor;

	NSImageView* artwork_image_view = [[NSImageView alloc] initWithFrame:NSZeroRect];
	artwork_image_view.translatesAutoresizingMaskIntoConstraints = NO;
	artwork_image_view.imageScaling = NSImageScaleAxesIndependently;
	artwork_image_view.wantsLayer = YES;
	artwork_image_view.layer.cornerRadius = 5.0;
	artwork_image_view.layer.masksToBounds = YES;

	NSButton* back_button = [self transportButtonWithSymbolName:@"30.arrow.trianglehead.counterclockwise" accessibilityDescription:@"Skip Back 30 Seconds" action:@selector(skipBackward:)];
	NSButton* play_button = [self transportButtonWithSymbolName:@"play.fill" accessibilityDescription:@"Play" action:@selector(togglePlayback:)];
	NSButton* forward_button = [self transportButtonWithSymbolName:@"30.arrow.trianglehead.clockwise" accessibilityDescription:@"Skip Forward 30 Seconds" action:@selector(skipForward:)];

	NSStackView* controls_stack_view = [[NSStackView alloc] initWithFrame:NSZeroRect];
	controls_stack_view.translatesAutoresizingMaskIntoConstraints = NO;
	controls_stack_view.orientation = NSUserInterfaceLayoutOrientationHorizontal;
	controls_stack_view.alignment = NSLayoutAttributeCenterY;
	controls_stack_view.spacing = 22.0;
	[controls_stack_view addArrangedSubview:back_button];
	[controls_stack_view addArrangedSubview:play_button];
	[controls_stack_view addArrangedSubview:forward_button];

	MBPodcastSlider* progress_slider = [[MBPodcastSlider alloc] initWithFrame:NSZeroRect];
	progress_slider.translatesAutoresizingMaskIntoConstraints = NO;
	progress_slider.minValue = 0.0;
	progress_slider.maxValue = 1.0;
	progress_slider.doubleValue = 0.0;
	progress_slider.target = self;
	progress_slider.action = @selector(scrubPlaybackPosition:);
	progress_slider.continuous = YES;
	progress_slider.sliderType = NSSliderTypeLinear;
	progress_slider.cell = [[MBPodcastSliderCell alloc] init];
	__weak typeof(self) weak_self = self;
	progress_slider.trackingStateChangedHandler = ^(BOOL is_tracking) {
		MBPodcastController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		strong_self.isScrubbing = is_tracking;
		[strong_self seekPlayerToSliderPositionPreservingScrubState:is_tracking];
		if (!is_tracking) {
			[strong_self updateProgressSliderForCurrentTime];
		}
	};

	[artwork_background_view addSubview:artwork_image_view];
	[NSLayoutConstraint activateConstraints:@[
		[artwork_image_view.leadingAnchor constraintEqualToAnchor:artwork_background_view.leadingAnchor],
		[artwork_image_view.trailingAnchor constraintEqualToAnchor:artwork_background_view.trailingAnchor],
		[artwork_image_view.topAnchor constraintEqualToAnchor:artwork_background_view.topAnchor],
		[artwork_image_view.bottomAnchor constraintEqualToAnchor:artwork_background_view.bottomAnchor]
	]];

	NSView* controls_container_view = [[NSView alloc] initWithFrame:NSZeroRect];
	controls_container_view.translatesAutoresizingMaskIntoConstraints = NO;

	[controls_container_view addSubview:controls_stack_view];
	[controls_container_view addSubview:progress_slider];
	[NSLayoutConstraint activateConstraints:@[
		[controls_stack_view.centerXAnchor constraintEqualToAnchor:controls_container_view.centerXAnchor],
		[controls_stack_view.topAnchor constraintEqualToAnchor:controls_container_view.topAnchor constant:22.0],
		[progress_slider.topAnchor constraintEqualToAnchor:controls_stack_view.bottomAnchor constant:18.0],
		[progress_slider.leadingAnchor constraintEqualToAnchor:controls_container_view.leadingAnchor],
		[progress_slider.trailingAnchor constraintEqualToAnchor:controls_container_view.trailingAnchor],
		[progress_slider.bottomAnchor constraintEqualToAnchor:controls_container_view.bottomAnchor constant:-18.0]
	]];

	[container_view addSubview:artwork_background_view];
	[container_view addSubview:controls_container_view];
	[NSLayoutConstraint activateConstraints:@[
		[back_button.widthAnchor constraintEqualToConstant:28.0],
		[back_button.heightAnchor constraintEqualToConstant:28.0],
		[play_button.widthAnchor constraintEqualToConstant:28.0],
		[play_button.heightAnchor constraintEqualToConstant:28.0],
		[forward_button.widthAnchor constraintEqualToConstant:28.0],
		[forward_button.heightAnchor constraintEqualToConstant:28.0],
		[artwork_background_view.leadingAnchor constraintEqualToAnchor:container_view.leadingAnchor constant:18.0],
		[artwork_background_view.topAnchor constraintEqualToAnchor:container_view.topAnchor constant:22.0],
		[artwork_background_view.widthAnchor constraintEqualToConstant:40.0],
		[artwork_background_view.heightAnchor constraintEqualToConstant:40.0],
		[controls_container_view.leadingAnchor constraintEqualToAnchor:container_view.leadingAnchor constant:18.0],
		[controls_container_view.trailingAnchor constraintEqualToAnchor:container_view.trailingAnchor constant:-18.0],
		[controls_container_view.topAnchor constraintEqualToAnchor:container_view.topAnchor],
		[controls_container_view.bottomAnchor constraintEqualToAnchor:container_view.bottomAnchor]
	]];

	self.artworkBackgroundView = artwork_background_view;
	self.artworkImageView = artwork_image_view;
	self.backButton = back_button;
	self.playButton = play_button;
	self.forwardButton = forward_button;
	self.progressSlider = progress_slider;
	self.view = container_view;
	[self updateArtworkImage];
	[self updatePlaybackButtonImage];
}

- (void) setEntry:(MBEntry* _Nullable) entry
{
	if (_entry.entryID != entry.entryID) {
		self.progressSlider.doubleValue = 0.0;
	}

	_entry = entry;
	[self configurePlayerForCurrentEntry];
}

- (void) setArtworkURLString:(NSString*) artwork_url_string
{
	_artworkURLString = [artwork_url_string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	[self updateArtworkImage];
}

- (NSButton*) transportButtonWithSymbolName:(NSString*) symbol_name accessibilityDescription:(NSString*) accessibility_description action:(SEL) action
{
	NSButton* button = [NSButton buttonWithTitle:@"" target:self action:action];
	button.translatesAutoresizingMaskIntoConstraints = NO;
	button.bordered = NO;
	button.imagePosition = NSImageOnly;
	button.imageScaling = NSImageScaleProportionallyUpOrDown;
	button.contentTintColor = [NSColor colorWithWhite:0.16 alpha:1.0];
	button.image = [NSImage imageWithSystemSymbolName:symbol_name accessibilityDescription:accessibility_description];
	return button;
}

- (void) configurePlayerForCurrentEntry
{
	NSString* enclosure_url = [self.entry.enclosureURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if ([enclosure_url isEqualToString:self.currentEnclosureURLString]) {
		return;
	}

	[[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.player.currentItem];
	[self.player pause];
	[self removeTimeObserverIfNeeded];
	self.player = nil;
	self.currentEnclosureURLString = enclosure_url;
	[self setPlayingState:NO notify:NO];
	self.progressSlider.doubleValue = 0.0;

	if (enclosure_url.length == 0) {
		return;
	}

	NSURL* podcast_url = [NSURL URLWithString:enclosure_url];
	if (podcast_url == nil) {
		return;
	}

	AVPlayerItem* player_item = [AVPlayerItem playerItemWithURL:podcast_url];
	AVPlayer* player = [AVPlayer playerWithPlayerItem:player_item];
	player.automaticallyWaitsToMinimizeStalling = YES;
	self.player = player;

	__weak typeof(self) weak_self = self;
	self.timeObserverToken = [self.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.25, NSEC_PER_SEC) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
		#pragma unused(time)
		MBPodcastController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		[strong_self updateProgressSliderForCurrentTime];
	}];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playbackDidFinish:) name:AVPlayerItemDidPlayToEndTimeNotification object:player_item];
}

- (void) removeTimeObserverIfNeeded
{
	if (self.player != nil && self.timeObserverToken != nil) {
		[self.player removeTimeObserver:self.timeObserverToken];
	}

	self.timeObserverToken = nil;
}

- (void) seekPlayerToSliderPositionPreservingScrubState:(BOOL) preserve_scrub_state
{
	if (self.player == nil) {
		return;
	}

	Float64 duration_seconds = CMTimeGetSeconds(self.player.currentItem.duration);
	if (!isfinite(duration_seconds) || duration_seconds <= 0.0) {
		return;
	}

	Float64 slider_fraction = MIN(1.0, MAX(0.0, self.progressSlider.doubleValue));
	Float64 target_seconds = slider_fraction * duration_seconds;
	CMTime target_time = CMTimeMakeWithSeconds(target_seconds, NSEC_PER_SEC);
	self.progressSlider.doubleValue = slider_fraction;

	__weak typeof(self) weak_self = self;
	[self.player seekToTime:target_time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
		if (!finished) {
			return;
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			MBPodcastController* strong_self = weak_self;
			if (strong_self == nil) {
				return;
			}

			if (!preserve_scrub_state || !strong_self.isScrubbing) {
				[strong_self updateProgressSliderForCurrentTime];
			}
		});
	}];
}

- (void) setPlayingState:(BOOL) is_playing notify:(BOOL) should_notify
{
	self.isPlaying = is_playing;
	[self updatePlaybackButtonImage];

	if (should_notify && self.playbackStateChangedHandler != nil) {
		self.playbackStateChangedHandler(self.isPlaying);
	}
}

- (void) updateProgressSliderForCurrentTime
{
	if (self.isScrubbing) {
		return;
	}

	AVPlayerItem* player_item = self.player.currentItem;
	if (player_item == nil) {
		self.progressSlider.doubleValue = 0.0;
		return;
	}

	Float64 duration_seconds = CMTimeGetSeconds(player_item.duration);
	Float64 current_seconds = CMTimeGetSeconds(self.player.currentTime);
	if (!isfinite(duration_seconds) || duration_seconds <= 0.0 || !isfinite(current_seconds) || current_seconds < 0.0) {
		self.progressSlider.doubleValue = 0.0;
		return;
	}

	self.progressSlider.doubleValue = MIN(1.0, MAX(0.0, current_seconds / duration_seconds));
}

- (void) updateArtworkImage
{
	NSString* artwork_url = self.artworkURLString ?: @"";
	if (artwork_url.length == 0) {
		self.artworkImageView.image = nil;
		return;
	}

	NSImage* cached_image = [self.avatarLoader cachedImageForURLString:artwork_url];
	if (cached_image != nil) {
		self.artworkImageView.image = cached_image;
		return;
	}

	self.artworkImageView.image = nil;
	[self.avatarLoader loadImageForURLString:artwork_url];
}

- (void) updatePlaybackButtonImage
{
	NSString* symbol_name = self.isPlaying ? @"pause.fill" : @"play.fill";
	NSString* accessibility_description = self.isPlaying ? @"Pause" : @"Play";
	self.playButton.image = [NSImage imageWithSystemSymbolName:symbol_name accessibilityDescription:accessibility_description];
}

- (void) avatarImageDidLoad:(NSNotification*) notification
{
	NSString* url_string = [notification.userInfo[MBAvatarLoaderURLStringUserInfoKey] isKindOfClass:[NSString class]] ? notification.userInfo[MBAvatarLoaderURLStringUserInfoKey] : @"";
	if (![url_string isEqualToString:self.artworkURLString]) {
		return;
	}

	[self updateArtworkImage];
}

- (void) playbackDidFinish:(NSNotification*) notification
{
	#pragma unused(notification)
	[self.player pause];
	self.progressSlider.doubleValue = 1.0;
	[self setPlayingState:NO notify:YES];
}

- (IBAction) skipBackward:(id) sender
{
	#pragma unused(sender)
	if (self.player == nil) {
		return;
	}

	Float64 current_seconds = CMTimeGetSeconds(self.player.currentTime);
	if (!isfinite(current_seconds)) {
		current_seconds = 0.0;
	}

	Float64 target_seconds = MAX(0.0, current_seconds - 30.0);
	CMTime target_time = CMTimeMakeWithSeconds(target_seconds, NSEC_PER_SEC);
	[self.player seekToTime:target_time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
}

- (IBAction) togglePlayback:(id) sender
{
	#pragma unused(sender)
	if (self.player == nil) {
		[self configurePlayerForCurrentEntry];
	}

	if (self.player == nil) {
		return;
	}

	if (self.isPlaying) {
		[self.player pause];
		[self setPlayingState:NO notify:YES];
		return;
	}

	AVPlayerItem* player_item = self.player.currentItem;
	Float64 duration_seconds = CMTimeGetSeconds(player_item.duration);
	Float64 current_seconds = CMTimeGetSeconds(self.player.currentTime);
	BOOL is_at_end = (isfinite(duration_seconds) && duration_seconds > 0.0 && isfinite(current_seconds) && current_seconds >= (duration_seconds - 0.5));
	if (is_at_end) {
		[self.player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
	}

	[self.player play];
	[self setPlayingState:YES notify:YES];
}

- (IBAction) skipForward:(id) sender
{
	#pragma unused(sender)
	if (self.player == nil) {
		return;
	}

	Float64 current_seconds = CMTimeGetSeconds(self.player.currentTime);
	Float64 duration_seconds = CMTimeGetSeconds(self.player.currentItem.duration);
	if (!isfinite(current_seconds)) {
		current_seconds = 0.0;
	}

	Float64 target_seconds = current_seconds + 30.0;
	if (isfinite(duration_seconds) && duration_seconds > 0.0) {
		target_seconds = MIN(duration_seconds, target_seconds);
	}

	CMTime target_time = CMTimeMakeWithSeconds(target_seconds, NSEC_PER_SEC);
	[self.player seekToTime:target_time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
}

- (IBAction) scrubPlaybackPosition:(id) sender
{
	#pragma unused(sender)
	[self seekPlayerToSliderPositionPreservingScrubState:self.isScrubbing];
}

@end
