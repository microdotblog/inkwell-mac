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
#import "MBPathUtilities.h"

static NSString* const InkwellPodcastsFilename = @"Podcasts.json";
static NSString* const InkwellPodcastEntryIDKey = @"entry_id";
static NSString* const InkwellPodcastEnclosureURLKey = @"enclosure_url";
static NSString* const InkwellPodcastPlaybackSecondsKey = @"playback_seconds";
static NSString* const InkwellPodcastPlaybackPercentKey = @"playback_percent";
static NSString* const InkwellPodcastLastPlayedAtKey = @"last_played_at";
static NSString* const InkwellPodcastAvatarURLKey = @"avatar_url";
static NSInteger const InkwellPodcastMaximumSavedItems = 50;
static NSTimeInterval const InkwellPodcastSaveInterval = 15.0;

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

- (void) setDoubleValue:(double) double_value
{
	[super setDoubleValue:double_value];
	[self setNeedsDisplay:YES];
}

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
@property (nonatomic, strong) NSMutableArray* playbackRecords;
@property (nonatomic, strong, nullable) NSTimer* playbackSaveTimer;
@property (nonatomic, strong, nullable) AVPlayer* player;
@property (nonatomic, copy) NSString* currentEnclosureURLString;
@property (nonatomic, strong, nullable) id timeObserverToken;
@property (nonatomic, assign) BOOL isScrubbing;
@property (nonatomic, assign, readwrite) BOOL isPlaying;

- (NSButton*) transportButtonWithSymbolName:(NSString*) symbol_name accessibilityDescription:(NSString*) accessibility_description action:(SEL) action;
- (void) configurePlayerForCurrentEntry;
- (NSDate* _Nullable) dateFromISO8601String:(NSString*) string;
- (NSISO8601DateFormatter*) iso8601Formatter;
- (NSURL* _Nullable) playbackRecordsFileURLCreateIfNeeded:(BOOL) create_if_needed;
- (NSMutableDictionary* _Nullable) playbackRecordForEntry:(MBEntry*) entry createIfNeeded:(BOOL) create_if_needed;
- (void) loadPlaybackRecords;
- (void) persistPlaybackRecordsToDisk;
- (void) persistPlaybackStateForCurrentEntryToDisk;
- (void) playbackSaveTimerDidFire:(NSTimer*) timer;
- (void) removeTimeObserverIfNeeded;
- (double) savedPlaybackPercentForEntry:(MBEntry* _Nullable) entry;
- (void) restorePlaybackPositionForCurrentEntry;
- (void) schedulePlaybackSaveTimerIfNeeded;
- (void) seekPlayerToSliderPositionPreservingScrubState:(BOOL) preserve_scrub_state;
- (void) setPlayingState:(BOOL) is_playing notify:(BOOL) should_notify;
- (void) sortAndTrimPlaybackRecords;
- (void) stopPlaybackSaveTimer;
- (void) updatePlaybackRecordForEntry:(MBEntry* _Nullable) entry artworkURLString:(NSString*) artwork_url_string;
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
		_artworkURLString = @"";
		_currentEnclosureURLString = @"";
		self.avatarLoader = [MBAvatarLoader sharedLoader];
		self.playbackRecords = [NSMutableArray array];
		[self loadPlaybackRecords];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(avatarImageDidLoad:) name:MBAvatarLoaderDidLoadImageNotification object:self.avatarLoader];
	}
	return self;
}

- (void) dealloc
{
	[self persistPlaybackStateForCurrentEntryToDisk];
	[self stopPlaybackSaveTimer];
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
	NSString* previous_enclosure_url = [_entry.enclosureURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	NSString* next_enclosure_url = [entry.enclosureURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	BOOL did_change_entry = (_entry.entryID != entry.entryID || ![previous_enclosure_url isEqualToString:next_enclosure_url]);
	if (did_change_entry) {
		[self updatePlaybackRecordForEntry:_entry artworkURLString:self.artworkURLString];
		[self persistPlaybackRecordsToDisk];
		self.progressSlider.doubleValue = 0.0;
	}

	_entry = entry;
	self.progressSlider.doubleValue = [self savedPlaybackPercentForEntry:entry];
	[self configurePlayerForCurrentEntry];
}

- (void) setArtworkURLString:(NSString*) artwork_url_string
{
	_artworkURLString = [artwork_url_string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	[self updateArtworkImage];
	[self updatePlaybackRecordForEntry:self.entry artworkURLString:_artworkURLString];
	[self persistPlaybackRecordsToDisk];
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

- (void) loadPlaybackRecords
{
	[self.playbackRecords removeAllObjects];

	NSURL* file_url = [self playbackRecordsFileURLCreateIfNeeded:NO];
	if (file_url == nil) {
		return;
	}

	NSData* data = [NSData dataWithContentsOfURL:file_url];
	if (data.length == 0) {
		return;
	}

	id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
	if (![payload isKindOfClass:[NSArray class]]) {
		return;
	}

	for (id item in (NSArray*) payload) {
		if (![item isKindOfClass:[NSDictionary class]]) {
			continue;
		}

		NSDictionary* dictionary = (NSDictionary*) item;
		NSString* enclosure_url = [dictionary[InkwellPodcastEnclosureURLKey] isKindOfClass:[NSString class]] ? dictionary[InkwellPodcastEnclosureURLKey] : @"";
		enclosure_url = [enclosure_url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		if (enclosure_url.length == 0) {
			continue;
		}

		id entry_id_value = dictionary[InkwellPodcastEntryIDKey];
		NSInteger entry_id = [entry_id_value respondsToSelector:@selector(integerValue)] ? [entry_id_value integerValue] : 0;

		id playback_seconds_value = dictionary[InkwellPodcastPlaybackSecondsKey];
		Float64 playback_seconds = [playback_seconds_value respondsToSelector:@selector(doubleValue)] ? [playback_seconds_value doubleValue] : 0.0;
		playback_seconds = MAX(0.0, playback_seconds);

		id playback_percent_value = dictionary[InkwellPodcastPlaybackPercentKey];
		double playback_percent = [playback_percent_value respondsToSelector:@selector(doubleValue)] ? [playback_percent_value doubleValue] : 0.0;
		playback_percent = MIN(1.0, MAX(0.0, playback_percent));

		NSString* last_played_at = [dictionary[InkwellPodcastLastPlayedAtKey] isKindOfClass:[NSString class]] ? dictionary[InkwellPodcastLastPlayedAtKey] : @"";
		last_played_at = [last_played_at stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";

		NSString* avatar_url = [dictionary[InkwellPodcastAvatarURLKey] isKindOfClass:[NSString class]] ? dictionary[InkwellPodcastAvatarURLKey] : @"";
		avatar_url = [avatar_url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";

		NSMutableDictionary* sanitized_dictionary = [NSMutableDictionary dictionary];
		sanitized_dictionary[InkwellPodcastEntryIDKey] = @(MAX(0, entry_id));
		sanitized_dictionary[InkwellPodcastEnclosureURLKey] = enclosure_url;
		sanitized_dictionary[InkwellPodcastPlaybackSecondsKey] = @(playback_seconds);
		sanitized_dictionary[InkwellPodcastPlaybackPercentKey] = @(playback_percent);
		sanitized_dictionary[InkwellPodcastLastPlayedAtKey] = last_played_at;
		sanitized_dictionary[InkwellPodcastAvatarURLKey] = avatar_url;
		[self.playbackRecords addObject:sanitized_dictionary];
	}

	[self sortAndTrimPlaybackRecords];
}

- (NSURL* _Nullable) playbackRecordsFileURLCreateIfNeeded:(BOOL) create_if_needed
{
	return [MBPathUtilities appFileURLForSearchPathDirectory:NSApplicationSupportDirectory filename:InkwellPodcastsFilename createDirectoryIfNeeded:create_if_needed];
}

- (NSMutableDictionary* _Nullable) playbackRecordForEntry:(MBEntry*) entry createIfNeeded:(BOOL) create_if_needed
{
	if (entry == nil || ![entry hasAudioEnclosure]) {
		return nil;
	}

	NSString* enclosure_url = [entry.enclosureURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (entry.entryID <= 0 || enclosure_url.length == 0) {
		return nil;
	}

	for (NSMutableDictionary* dictionary in self.playbackRecords) {
		if (![dictionary isKindOfClass:[NSMutableDictionary class]]) {
			continue;
		}

		id entry_id_value = dictionary[InkwellPodcastEntryIDKey];
		NSInteger entry_id = [entry_id_value respondsToSelector:@selector(integerValue)] ? [entry_id_value integerValue] : 0;
		NSString* saved_enclosure_url = [dictionary[InkwellPodcastEnclosureURLKey] isKindOfClass:[NSString class]] ? dictionary[InkwellPodcastEnclosureURLKey] : @"";
		if ((entry_id > 0 && entry_id == entry.entryID) || [saved_enclosure_url isEqualToString:enclosure_url]) {
			return dictionary;
		}
	}

	if (!create_if_needed) {
		return nil;
	}

	NSMutableDictionary* dictionary = [NSMutableDictionary dictionary];
	dictionary[InkwellPodcastEntryIDKey] = @(entry.entryID);
	dictionary[InkwellPodcastEnclosureURLKey] = enclosure_url;
	dictionary[InkwellPodcastPlaybackSecondsKey] = @(0.0);
	dictionary[InkwellPodcastPlaybackPercentKey] = @(0.0);
	dictionary[InkwellPodcastLastPlayedAtKey] = @"";
	dictionary[InkwellPodcastAvatarURLKey] = @"";
	[self.playbackRecords addObject:dictionary];
	return dictionary;
}

- (NSISO8601DateFormatter*) iso8601Formatter
{
	static NSISO8601DateFormatter* iso8601_formatter;
	static dispatch_once_t once_token;
	dispatch_once(&once_token, ^{
		iso8601_formatter = [[NSISO8601DateFormatter alloc] init];
		iso8601_formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
	});

	return iso8601_formatter;
}

- (NSDate* _Nullable) dateFromISO8601String:(NSString*) string
{
	NSString* trimmed_string = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (trimmed_string.length == 0) {
		return nil;
	}

	static NSISO8601DateFormatter* default_date_formatter;
	static dispatch_once_t once_token;
	dispatch_once(&once_token, ^{
		default_date_formatter = [[NSISO8601DateFormatter alloc] init];
		default_date_formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
	});

	NSDate* date_value = [[self iso8601Formatter] dateFromString:trimmed_string];
	if (date_value != nil) {
		return date_value;
	}

	return [default_date_formatter dateFromString:trimmed_string];
}

- (void) sortAndTrimPlaybackRecords
{
	[self.playbackRecords sortUsingComparator:^NSComparisonResult(NSDictionary* left_dictionary, NSDictionary* right_dictionary) {
		NSString* left_date_string = [left_dictionary[InkwellPodcastLastPlayedAtKey] isKindOfClass:[NSString class]] ? left_dictionary[InkwellPodcastLastPlayedAtKey] : @"";
		NSString* right_date_string = [right_dictionary[InkwellPodcastLastPlayedAtKey] isKindOfClass:[NSString class]] ? right_dictionary[InkwellPodcastLastPlayedAtKey] : @"";
		NSDate* left_date = [self dateFromISO8601String:left_date_string];
		NSDate* right_date = [self dateFromISO8601String:right_date_string];
		if (left_date == nil && right_date == nil) {
			return NSOrderedSame;
		}
		if (left_date == nil) {
			return NSOrderedDescending;
		}
		if (right_date == nil) {
			return NSOrderedAscending;
		}
		return [right_date compare:left_date];
	}];

	while (self.playbackRecords.count > InkwellPodcastMaximumSavedItems) {
		[self.playbackRecords removeLastObject];
	}
}

- (void) updatePlaybackRecordForEntry:(MBEntry* _Nullable) entry artworkURLString:(NSString*) artwork_url_string
{
	NSMutableDictionary* dictionary = [self playbackRecordForEntry:entry createIfNeeded:YES];
	if (dictionary == nil) {
		return;
	}

	id saved_playback_seconds_value = dictionary[InkwellPodcastPlaybackSecondsKey];
	Float64 playback_seconds = [saved_playback_seconds_value respondsToSelector:@selector(doubleValue)] ? [saved_playback_seconds_value doubleValue] : 0.0;
	if (self.player != nil) {
		Float64 current_seconds = CMTimeGetSeconds(self.player.currentTime);
		if (isfinite(current_seconds) && current_seconds >= 0.0) {
			playback_seconds = current_seconds;
		}
	}

	double playback_percent = MIN(1.0, MAX(0.0, self.progressSlider.doubleValue));
	NSString* trimmed_avatar_url = [artwork_url_string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	NSString* last_played_at = [[self iso8601Formatter] stringFromDate:[NSDate date]] ?: @"";

	dictionary[InkwellPodcastEntryIDKey] = @(entry.entryID);
	dictionary[InkwellPodcastEnclosureURLKey] = [entry.enclosureURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	dictionary[InkwellPodcastPlaybackSecondsKey] = @(playback_seconds);
	dictionary[InkwellPodcastPlaybackPercentKey] = @(playback_percent);
	dictionary[InkwellPodcastLastPlayedAtKey] = last_played_at;
	dictionary[InkwellPodcastAvatarURLKey] = trimmed_avatar_url;
	[self sortAndTrimPlaybackRecords];
}

- (void) restorePlaybackPositionForCurrentEntry
{
	NSMutableDictionary* dictionary = [self playbackRecordForEntry:self.entry createIfNeeded:NO];
	if (dictionary == nil) {
		self.progressSlider.doubleValue = 0.0;
		return;
	}

	id playback_percent_value = dictionary[InkwellPodcastPlaybackPercentKey];
	double playback_percent = [playback_percent_value respondsToSelector:@selector(doubleValue)] ? [playback_percent_value doubleValue] : 0.0;
	playback_percent = MIN(1.0, MAX(0.0, playback_percent));
	self.progressSlider.doubleValue = playback_percent;

	id playback_seconds_value = dictionary[InkwellPodcastPlaybackSecondsKey];
	Float64 playback_seconds = [playback_seconds_value respondsToSelector:@selector(doubleValue)] ? [playback_seconds_value doubleValue] : 0.0;
	if (playback_seconds <= 0.0 || self.player == nil) {
		return;
	}

	CMTime target_time = CMTimeMakeWithSeconds(playback_seconds, NSEC_PER_SEC);
	__weak typeof(self) weak_self = self;
	[self.player seekToTime:target_time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
		if (!finished) {
			return;
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			MBPodcastController* strong_self = weak_self;
			if (strong_self == nil || strong_self.isScrubbing) {
				return;
			}

			[strong_self updateProgressSliderForCurrentTime];
		});
	}];
}

- (double) savedPlaybackPercentForEntry:(MBEntry* _Nullable) entry
{
	NSMutableDictionary* dictionary = [self playbackRecordForEntry:entry createIfNeeded:NO];
	if (dictionary == nil) {
		return 0.0;
	}

	id playback_percent_value = dictionary[InkwellPodcastPlaybackPercentKey];
	double playback_percent = [playback_percent_value respondsToSelector:@selector(doubleValue)] ? [playback_percent_value doubleValue] : 0.0;
	return MIN(1.0, MAX(0.0, playback_percent));
}

- (void) persistPlaybackRecordsToDisk
{
	[self sortAndTrimPlaybackRecords];

	NSURL* file_url = [self playbackRecordsFileURLCreateIfNeeded:YES];
	if (file_url == nil) {
		return;
	}

	NSData* data = [NSJSONSerialization dataWithJSONObject:self.playbackRecords options:0 error:nil];
	if (data == nil) {
		return;
	}

	[data writeToURL:file_url atomically:YES];
}

- (void) persistPlaybackStateForCurrentEntryToDisk
{
	[self updatePlaybackRecordForEntry:self.entry artworkURLString:self.artworkURLString];
	[self persistPlaybackRecordsToDisk];
}

- (void) schedulePlaybackSaveTimerIfNeeded
{
	if (self.playbackSaveTimer != nil || !self.isPlaying || self.player == nil) {
		return;
	}

	self.playbackSaveTimer = [NSTimer scheduledTimerWithTimeInterval:InkwellPodcastSaveInterval target:self selector:@selector(playbackSaveTimerDidFire:) userInfo:nil repeats:YES];
}

- (void) stopPlaybackSaveTimer
{
	[self.playbackSaveTimer invalidate];
	self.playbackSaveTimer = nil;
}

- (void) playbackSaveTimerDidFire:(NSTimer*) timer
{
	#pragma unused(timer)
	[self persistPlaybackStateForCurrentEntryToDisk];
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
	self.progressSlider.doubleValue = [self savedPlaybackPercentForEntry:self.entry];

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
	[self restorePlaybackPositionForCurrentEntry];
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
	if (self.isPlaying) {
		[self schedulePlaybackSaveTimerIfNeeded];
	}
	else {
		[self stopPlaybackSaveTimer];
	}

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
		if (self.entry == nil) {
			self.progressSlider.doubleValue = 0.0;
		}
		return;
	}

	Float64 duration_seconds = CMTimeGetSeconds(player_item.duration);
	Float64 current_seconds = CMTimeGetSeconds(self.player.currentTime);
	if (!isfinite(duration_seconds) || duration_seconds <= 0.0 || !isfinite(current_seconds) || current_seconds < 0.0) {
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
	[self persistPlaybackStateForCurrentEntryToDisk];
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
		[self persistPlaybackStateForCurrentEntryToDisk];
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
