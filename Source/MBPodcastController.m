//
//  MBPodcastController.m
//  Inkwell
//
//  Created by Codex on 3/18/26.
//

#import "MBPodcastController.h"
#import <AVFoundation/AVFoundation.h>
#import <CommonCrypto/CommonDigest.h>
#import "MBAvatarLoader.h"
#import "MBEntry.h"
#import "MBPathUtilities.h"
#import "MBPodcastChapter.h"
#import "MBPodcastSlider.h"

static NSString* const InkwellPodcastsFilename = @"Podcasts.json";
static NSString* const InkwellPodcastEntryIDKey = @"entry_id";
static NSString* const InkwellPodcastEnclosureURLKey = @"enclosure_url";
static NSString* const InkwellPodcastPlaybackSecondsKey = @"playback_seconds";
static NSString* const InkwellPodcastPlaybackPercentKey = @"playback_percent";
static NSString* const InkwellPodcastLastPlayedAtKey = @"last_played_at";
static NSString* const InkwellPodcastAvatarURLKey = @"avatar_url";
static NSInteger const InkwellPodcastMaximumSavedItems = 50;
static NSTimeInterval const InkwellPodcastSaveInterval = 15.0;
static NSTimeInterval const InkwellPodcastDownloadDelayInterval = 10.0;
static NSString* const InkwellPodcastPlaybackRateDefaultsKey = @"PodcastPlaybackRate";
static NSString* const InkwellPodcastCacheDirectoryName = @"Podcasts";
static NSString* const InkwellPodcastFallbackExtension = @"mp3";
static NSUInteger const InkwellPodcastCacheHashLength = 12;
static CGFloat const InkwellPodcastCollapsedPaneHeight = 118.0;
static CGFloat const InkwellPodcastExpandedChaptersHeight = 400.0;
static CGFloat const InkwellPodcastChapterTimeColumnWidth = 60.0;
static void* InkwellPodcastPlayerStatusContext = &InkwellPodcastPlayerStatusContext;

static uint32_t MBPodcastReadBigEndianUInt32(const unsigned char* bytes)
{
	return ((uint32_t) bytes[0] << 24) | ((uint32_t) bytes[1] << 16) | ((uint32_t) bytes[2] << 8) | (uint32_t) bytes[3];
}

static uint32_t MBPodcastReadSyncsafeUInt32(const unsigned char* bytes)
{
	return ((uint32_t) bytes[0] << 21) | ((uint32_t) bytes[1] << 14) | ((uint32_t) bytes[2] << 7) | (uint32_t) bytes[3];
}

@interface MBPodcastContainerView : NSView

@property (nonatomic, copy, nullable) void (^appearanceChangedHandler)(void);

@end

@interface MBPodcastPassthroughView : NSView

@end

@implementation MBPodcastPassthroughView

- (NSView*) hitTest:(NSPoint) point
{
	#pragma unused(point)
	return nil;
}

@end

@interface MBPodcastPassthroughImageView : NSImageView

@end

@implementation MBPodcastPassthroughImageView

- (NSView*) hitTest:(NSPoint) point
{
	#pragma unused(point)
	return nil;
}

@end

@interface MBPodcastArtworkButton : NSButton

@property (nonatomic, strong) MBPodcastPassthroughImageView* artworkImageView;
@property (nonatomic, strong) MBPodcastPassthroughView* hoverOverlayView;
@property (nonatomic, strong) MBPodcastPassthroughImageView* overlayImageView;
@property (nonatomic, strong, nullable) NSTrackingArea* trackingArea;
@property (nonatomic, assign) BOOL isExpanded;
@property (nonatomic, assign) BOOL isHovering;
@property (nonatomic, assign) BOOL hoverEnabled;

- (void) updateOverlayImage;
- (void) updateHoverState;

@end

@implementation MBPodcastArtworkButton

- (instancetype) initWithFrame:(NSRect) frame_rect
{
	self = [super initWithFrame:frame_rect];
	if (self) {
		self.translatesAutoresizingMaskIntoConstraints = NO;
		self.bordered = NO;
		self.buttonType = NSButtonTypeMomentaryChange;
		self.focusRingType = NSFocusRingTypeNone;
		self.title = @"";
		self.imagePosition = NSNoImage;
		self.wantsLayer = YES;
		self.layer.cornerRadius = 5.0;
		self.layer.masksToBounds = YES;

		MBPodcastPassthroughImageView* artwork_image_view = [[MBPodcastPassthroughImageView alloc] initWithFrame:NSZeroRect];
		artwork_image_view.translatesAutoresizingMaskIntoConstraints = NO;
		artwork_image_view.imageScaling = NSImageScaleAxesIndependently;
		[self addSubview:artwork_image_view];

		MBPodcastPassthroughView* hover_overlay_view = [[MBPodcastPassthroughView alloc] initWithFrame:NSZeroRect];
		hover_overlay_view.translatesAutoresizingMaskIntoConstraints = NO;
		hover_overlay_view.wantsLayer = YES;
		hover_overlay_view.layer.backgroundColor = [NSColor colorWithWhite:0.0 alpha:0.24].CGColor;
		hover_overlay_view.alphaValue = 0.0;
		[self addSubview:hover_overlay_view];

		MBPodcastPassthroughImageView* overlay_image_view = [[MBPodcastPassthroughImageView alloc] initWithFrame:NSZeroRect];
		overlay_image_view.translatesAutoresizingMaskIntoConstraints = NO;
		overlay_image_view.imageScaling = NSImageScaleNone;
		overlay_image_view.contentTintColor = [NSColor whiteColor];
		[hover_overlay_view addSubview:overlay_image_view];

		[NSLayoutConstraint activateConstraints:@[
			[artwork_image_view.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
			[artwork_image_view.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
			[artwork_image_view.topAnchor constraintEqualToAnchor:self.topAnchor],
			[artwork_image_view.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
			[hover_overlay_view.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
			[hover_overlay_view.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
			[hover_overlay_view.topAnchor constraintEqualToAnchor:self.topAnchor],
			[hover_overlay_view.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
			[overlay_image_view.centerXAnchor constraintEqualToAnchor:hover_overlay_view.centerXAnchor],
			[overlay_image_view.centerYAnchor constraintEqualToAnchor:hover_overlay_view.centerYAnchor]
		]];

		self.artworkImageView = artwork_image_view;
		self.hoverOverlayView = hover_overlay_view;
		self.overlayImageView = overlay_image_view;
		self.hoverEnabled = NO;
		[self updateOverlayImage];
	}
	return self;
}

- (void) updateTrackingAreas
{
	[super updateTrackingAreas];
	if (self.trackingArea != nil) {
		[self removeTrackingArea:self.trackingArea];
	}

	NSTrackingAreaOptions tracking_options = NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp | NSTrackingInVisibleRect;
	self.trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect options:tracking_options owner:self userInfo:nil];
	[self addTrackingArea:self.trackingArea];
}

- (void) mouseEntered:(NSEvent*) event
{
	#pragma unused(event)
	self.isHovering = YES;
	[self updateHoverState];
}

- (void) mouseExited:(NSEvent*) event
{
	#pragma unused(event)
	self.isHovering = NO;
	[self updateHoverState];
}

- (void) setIsExpanded:(BOOL) is_expanded
{
	_isExpanded = is_expanded;
	[self updateOverlayImage];
}

- (void) updateOverlayImage
{
	NSString* symbol_name = self.isExpanded ? @"chevron.down" : @"chevron.up";
	NSImageSymbolConfiguration* configuration = [NSImageSymbolConfiguration configurationWithPointSize:12.0 weight:NSFontWeightSemibold];
	NSImage* symbol_image = [NSImage imageWithSystemSymbolName:symbol_name accessibilityDescription:nil];
	self.overlayImageView.image = [symbol_image imageWithSymbolConfiguration:configuration];
}

- (void) updateHoverState
{
	BOOL should_show_overlay = (self.hoverEnabled && self.isHovering);
	self.hoverOverlayView.alphaValue = should_show_overlay ? 1.0 : 0.0;
}

@end

@interface MBPodcastController () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) NSView* artworkBackgroundView;
@property (nonatomic, strong) MBPodcastArtworkButton* artworkButton;
@property (nonatomic, strong) NSImageView* artworkImageView;
@property (nonatomic, strong) NSView* chaptersContainerView;
@property (nonatomic, strong) NSScrollView* chaptersScrollView;
@property (nonatomic, strong) NSTableView* chaptersTableView;
@property (nonatomic, strong) NSView* chaptersSeparatorLineView;
@property (nonatomic, strong) NSLayoutConstraint* chaptersContainerHeightConstraint;
@property (nonatomic, strong) NSButton* backButton;
@property (nonatomic, strong) NSButton* playButton;
@property (nonatomic, strong) NSButton* forwardButton;
@property (nonatomic, strong) MBPodcastSlider* progressSlider;
@property (nonatomic, strong) NSTextField* currentTimeLabel;
@property (nonatomic, strong) NSTextField* remainingTimeLabel;
@property (nonatomic, strong) NSProgressIndicator* loadingIndicator;
@property (nonatomic, strong) NSPopUpButton* playbackRatePopUpButton;
@property (nonatomic, strong) MBAvatarLoader* avatarLoader;
@property (nonatomic, strong) NSURLSession* downloadSession;
@property (nonatomic, strong) NSMutableSet* pendingDownloadURLStrings;
@property (nonatomic, strong) NSMutableArray* playbackRecords;
@property (nonatomic, copy, readwrite) NSArray* chapters;
@property (nonatomic, strong, nullable) NSTimer* playbackSaveTimer;
@property (nonatomic, strong, nullable) AVPlayer* player;
@property (nonatomic, copy) NSString* currentEnclosureURLString;
@property (nonatomic, strong, nullable) id timeObserverToken;
@property (nonatomic, assign) BOOL isObservingPlayerStatus;
@property (nonatomic, assign) BOOL isScrubbing;
@property (nonatomic, assign) BOOL isShowingChapterList;
@property (nonatomic, assign) NSUInteger currentChapterIndex;
@property (nonatomic, assign, readwrite) BOOL isPlaying;
@property (nonatomic, assign) NSUInteger pendingDownloadToken;

- (void) addPlayerStatusObserverIfNeeded;
- (void) applyPreferredPlaybackRateIfNeeded;
- (void) cacheAudioForURLStringIfNeeded:(NSString*) url_string;
- (NSURL* _Nullable) cachedAudioFileURLForURLString:(NSString*) url_string createDirectory:(BOOL) create_directory;
- (NSString*) cachedAudioFilenameForURLString:(NSString*) url_string;
- (BOOL) cachedAudioFileExistsForURLString:(NSString*) url_string;
- (void) configurePlaybackRatePopUpButton:(NSPopUpButton*) popup_button;
- (NSUInteger) chapterIndexForPlaybackSeconds:(Float64) playback_seconds;
- (Float64) chapterDurationSecondsAtIndex:(NSUInteger) index;
- (NSString*) chapterDurationStringForIndex:(NSUInteger) index;
- (NSButton*) transportButtonWithSymbolName:(NSString*) symbol_name accessibilityDescription:(NSString*) accessibility_description action:(SEL) action;
- (void) configurePlayerForCurrentEntry;
- (NSDate* _Nullable) dateFromISO8601String:(NSString*) string;
- (Float64) displayedCurrentPlaybackSeconds;
- (Float64) displayedDurationSeconds;
- (NSString*) formattedTimeStringForSeconds:(Float64) seconds;
- (NSISO8601DateFormatter*) iso8601Formatter;
- (NSString*) normalizedEnclosureURLString:(NSString*) url_string;
- (void) notifyPaneHeightIfNeeded;
- (NSUInteger) offsetOfID3TerminatorInData:(NSData*) data encodingByte:(uint8_t) encoding_byte startOffset:(NSUInteger) start_offset;
- (Float64) parsedDurationSecondsFromString:(NSString*) duration_string;
- (NSURL* _Nullable) playbackRecordsFileURLCreateIfNeeded:(BOOL) create_if_needed;
- (NSMutableDictionary* _Nullable) playbackRecordForEntry:(MBEntry*) entry createIfNeeded:(BOOL) create_if_needed;
- (NSInteger) id3MajorVersionForAudioFileURL:(NSURL*) file_url;
- (BOOL) isMP3AudioFileURL:(NSURL*) file_url;
- (void) loadChaptersForCachedAudioFileURL:(NSURL*) file_url completion:(void (^ _Nullable)(void)) completion;
- (void) loadChapterMetadataGroupsForAsset:(AVAsset*) asset completion:(void (^)(NSArray* chapters)) completion;
- (void) loadID3MetadataForAudioFileURL:(NSURL*) file_url asset:(AVAsset*) asset completion:(void (^)(NSArray* chapters)) completion;
- (void) loadPodcastChaptersForAudioFileURL:(NSURL*) file_url completion:(void (^)(NSArray* chapters)) completion;
- (MBPodcastChapter* _Nullable) podcastChapterFromID3MetadataItem:(AVMetadataItem*) item tagMajorVersion:(NSInteger) tag_major_version;
- (NSArray*) podcastChaptersFromID3MetadataItems:(NSArray*) metadata_items audioFileURL:(NSURL*) file_url;
- (NSArray*) podcastChaptersFromMetadataGroups:(NSArray*) chapter_groups;
- (NSString*) preferredCachedAudioExtensionForURLString:(NSString*) url_string;
- (BOOL) shouldApplyChaptersForAudioFileURL:(NSURL*) file_url;
- (NSString* _Nullable) stringFromID3TextFrameData:(NSData*) data;
- (NSURL* _Nullable) urlFromID3URLFrameData:(NSData*) data;
- (void) setChapterListExpanded:(BOOL) is_expanded animated:(BOOL) animated;
- (void) seekToChapterAtIndex:(NSUInteger) index;
- (void) loadPlaybackRecords;
- (void) persistPlaybackRecordsToDisk;
- (void) persistPlaybackStateForCurrentEntryToDisk;
- (void) playbackSaveTimerDidFire:(NSTimer*) timer;
- (double) preferredPlaybackRate;
- (void) removePlayerStatusObserverIfNeeded;
- (void) removeTimeObserverIfNeeded;
- (Float64) savedPlaybackSecondsForEntry:(MBEntry* _Nullable) entry;
- (double) savedPlaybackPercentForEntry:(MBEntry* _Nullable) entry;
- (void) restorePlaybackPositionForCurrentEntry;
- (void) scheduleAudioDownloadIfStillPlaying;
- (void) schedulePlaybackSaveTimerIfNeeded;
- (void) seekPlayerToSliderPositionPreservingScrubState:(BOOL) preserve_scrub_state;
- (NSString*) shortSHA1StringForString:(NSString*) string_value;
- (void) setPlayingState:(BOOL) is_playing notify:(BOOL) should_notify;
- (void) sortAndTrimPlaybackRecords;
- (void) stopPlaybackSaveTimer;
- (void) trimCachedAudioFilesIfNeeded;
- (void) updateCurrentChapterIndexForPlaybackSeconds:(Float64) playback_seconds;
- (void) updatePlaybackRecordForEntry:(MBEntry* _Nullable) entry artworkURLString:(NSString*) artwork_url_string;
- (void) updateLoadingIndicator;
- (void) updateAppearance;
- (void) updateProgressSliderForCurrentTime;
- (void) updateTimeLabels;
- (void) updateArtworkImage;
- (void) updatePlaybackButtonImage;
- (void) avatarImageDidLoad:(NSNotification*) notification;
- (void) playbackDidFinish:(NSNotification*) notification;
- (IBAction) skipBackward:(id) sender;
- (IBAction) playbackRateSelectionChanged:(id) sender;
- (IBAction) toggleChaptersList:(id) sender;
- (IBAction) togglePlayback:(id) sender;
- (IBAction) skipForward:(id) sender;
- (IBAction) scrubPlaybackPosition:(id) sender;

@end

@implementation MBPodcastContainerView

- (void) viewDidChangeEffectiveAppearance
{
	[super viewDidChangeEffectiveAppearance];
	if (self.appearanceChangedHandler != nil) {
		self.appearanceChangedHandler();
	}
}

@end

@implementation MBPodcastController

+ (NSURL* _Nullable) cachedAudioDirectoryURLCreatingIfNeeded:(BOOL) create_directory
{
	return [MBPathUtilities appSubdirectoryURLForSearchPathDirectory:NSCachesDirectory relativePath:InkwellPodcastCacheDirectoryName createIfNeeded:create_directory];
}

+ (void) cleanupCachedAudioFiles
{
	NSURL* directory_url = [self cachedAudioDirectoryURLCreatingIfNeeded:NO];
	if (directory_url == nil) {
		return;
	}

	NSFileManager* file_manager = [NSFileManager defaultManager];
	NSArray* cached_file_urls = [file_manager contentsOfDirectoryAtURL:directory_url includingPropertiesForKeys:@[ NSURLIsDirectoryKey, NSURLCreationDateKey ] options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
	if (cached_file_urls.count == 0) {
		return;
	}

	NSArray* sorted_file_urls = [cached_file_urls sortedArrayUsingComparator:^NSComparisonResult(NSURL* left_url, NSURL* right_url) {
		NSNumber* left_is_directory = nil;
		[left_url getResourceValue:&left_is_directory forKey:NSURLIsDirectoryKey error:nil];
		NSNumber* right_is_directory = nil;
		[right_url getResourceValue:&right_is_directory forKey:NSURLIsDirectoryKey error:nil];
		if (left_is_directory.boolValue != right_is_directory.boolValue) {
			return left_is_directory.boolValue ? NSOrderedDescending : NSOrderedAscending;
		}

		NSDate* left_creation_date = nil;
		[left_url getResourceValue:&left_creation_date forKey:NSURLCreationDateKey error:nil];
		NSDate* right_creation_date = nil;
		[right_url getResourceValue:&right_creation_date forKey:NSURLCreationDateKey error:nil];
		if (left_creation_date == nil && right_creation_date == nil) {
			return NSOrderedSame;
		}
		if (left_creation_date == nil) {
			return NSOrderedDescending;
		}
		if (right_creation_date == nil) {
			return NSOrderedAscending;
		}
		return [right_creation_date compare:left_creation_date];
	}];

	NSUInteger kept_file_count = 0;
	for (NSURL* file_url in sorted_file_urls) {
		NSNumber* is_directory = nil;
		[file_url getResourceValue:&is_directory forKey:NSURLIsDirectoryKey error:nil];
		if (is_directory.boolValue) {
			continue;
		}

		kept_file_count += 1;
		if (kept_file_count <= InkwellPodcastMaximumSavedItems) {
			continue;
		}

		[file_manager removeItemAtURL:file_url error:nil];
	}
}

- (instancetype) init
{
	self = [super initWithNibName:nil bundle:nil];
	if (self) {
		_artworkURLString = @"";
		_currentEnclosureURLString = @"";
		_chapters = @[];
		_currentChapterIndex = NSNotFound;
		self.avatarLoader = [MBAvatarLoader sharedLoader];
		self.downloadSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
		self.pendingDownloadURLStrings = [NSMutableSet set];
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
	[self removePlayerStatusObserverIfNeeded];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:MBAvatarLoaderDidLoadImageNotification object:self.avatarLoader];
	[self removeTimeObserverIfNeeded];
}

- (CGFloat) preferredPaneHeight
{
	if (self.isShowingChapterList && self.chapters.count > 0) {
		return InkwellPodcastCollapsedPaneHeight + InkwellPodcastExpandedChaptersHeight;
	}

	return InkwellPodcastCollapsedPaneHeight;
}

- (void) loadView
{
	MBPodcastContainerView* container_view = [[MBPodcastContainerView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 260.0, InkwellPodcastCollapsedPaneHeight)];
	container_view.translatesAutoresizingMaskIntoConstraints = NO;
	container_view.wantsLayer = YES;
	NSColor* background_color = [NSColor colorNamed:@"color_podcast_background"] ?: [NSColor colorWithWhite:0.92 alpha:0.78];
	container_view.layer.backgroundColor = background_color.CGColor;
	__weak typeof(self) weak_self = self;
	container_view.appearanceChangedHandler = ^{
		MBPodcastController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		[strong_self updateAppearance];
	};

	NSView* chapters_container_view = [[NSView alloc] initWithFrame:NSZeroRect];
	chapters_container_view.translatesAutoresizingMaskIntoConstraints = NO;

	NSTableView* chapters_table_view = [[NSTableView alloc] initWithFrame:NSZeroRect];
	chapters_table_view.translatesAutoresizingMaskIntoConstraints = NO;
	chapters_table_view.delegate = self;
	chapters_table_view.dataSource = self;
	chapters_table_view.headerView = nil;
	chapters_table_view.backgroundColor = [NSColor clearColor];
	chapters_table_view.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
	chapters_table_view.focusRingType = NSFocusRingTypeNone;
	chapters_table_view.intercellSpacing = NSMakeSize(0.0, 4.0);
	chapters_table_view.allowsEmptySelection = YES;

	NSTableColumn* title_column = [[NSTableColumn alloc] initWithIdentifier:@"ChapterTitleColumn"];
	title_column.resizingMask = NSTableColumnAutoresizingMask;
	[chapters_table_view addTableColumn:title_column];

	NSTableColumn* time_column = [[NSTableColumn alloc] initWithIdentifier:@"ChapterTimeColumn"];
	time_column.width = InkwellPodcastChapterTimeColumnWidth;
	time_column.minWidth = InkwellPodcastChapterTimeColumnWidth;
	time_column.maxWidth = InkwellPodcastChapterTimeColumnWidth;
	time_column.resizingMask = NSTableColumnNoResizing;
	[chapters_table_view addTableColumn:time_column];

	NSScrollView* chapters_scroll_view = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	chapters_scroll_view.translatesAutoresizingMaskIntoConstraints = NO;
	chapters_scroll_view.drawsBackground = NO;
	chapters_scroll_view.borderType = NSNoBorder;
	chapters_scroll_view.hasVerticalScroller = YES;
	chapters_scroll_view.documentView = chapters_table_view;

	NSView* chapters_separator_line_view = [[NSView alloc] initWithFrame:NSZeroRect];
	chapters_separator_line_view.translatesAutoresizingMaskIntoConstraints = NO;
	chapters_separator_line_view.wantsLayer = YES;
	chapters_separator_line_view.hidden = YES;

	[chapters_container_view addSubview:chapters_scroll_view];
	[chapters_container_view addSubview:chapters_separator_line_view];
	[NSLayoutConstraint activateConstraints:@[
		[chapters_scroll_view.leadingAnchor constraintEqualToAnchor:chapters_container_view.leadingAnchor constant:12.0],
		[chapters_scroll_view.trailingAnchor constraintEqualToAnchor:chapters_container_view.trailingAnchor constant:-10.0],
		[chapters_scroll_view.topAnchor constraintEqualToAnchor:chapters_container_view.topAnchor constant:12.0],
		[chapters_scroll_view.bottomAnchor constraintEqualToAnchor:chapters_container_view.bottomAnchor constant:-12.0],
		[chapters_separator_line_view.leadingAnchor constraintEqualToAnchor:chapters_container_view.leadingAnchor],
		[chapters_separator_line_view.trailingAnchor constraintEqualToAnchor:chapters_container_view.trailingAnchor],
		[chapters_separator_line_view.bottomAnchor constraintEqualToAnchor:chapters_container_view.bottomAnchor],
		[chapters_separator_line_view.heightAnchor constraintEqualToConstant:1.0]
	]];

	NSView* artwork_background_view = [[NSView alloc] initWithFrame:NSZeroRect];
	artwork_background_view.translatesAutoresizingMaskIntoConstraints = NO;
	artwork_background_view.wantsLayer = YES;
	artwork_background_view.layer.cornerRadius = 5.0;
	artwork_background_view.layer.masksToBounds = YES;
	artwork_background_view.layer.backgroundColor = [NSColor colorWithWhite:0.72 alpha:1.0].CGColor;

	MBPodcastArtworkButton* artwork_button = [[MBPodcastArtworkButton alloc] initWithFrame:NSZeroRect];
	artwork_button.target = self;
	artwork_button.action = @selector(toggleChaptersList:);
	artwork_button.accessibilityLabel = @"Show Chapters";
	artwork_button.hoverEnabled = NO;

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
	progress_slider.trackingStateChangedHandler = ^(BOOL is_tracking) {
		MBPodcastController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		strong_self.isScrubbing = is_tracking;
		[strong_self updateTimeLabels];
	};

	NSTextField* current_time_label = [NSTextField labelWithString:@"0:00"];
	current_time_label.translatesAutoresizingMaskIntoConstraints = NO;
	current_time_label.font = [NSFont systemFontOfSize:9.0 weight:NSFontWeightRegular];
	current_time_label.textColor = [NSColor secondaryLabelColor];
	current_time_label.alignment = NSTextAlignmentLeft;

	NSTextField* remaining_time_label = [NSTextField labelWithString:@"-0:00"];
	remaining_time_label.translatesAutoresizingMaskIntoConstraints = NO;
	remaining_time_label.font = [NSFont systemFontOfSize:9.0 weight:NSFontWeightRegular];
	remaining_time_label.textColor = [NSColor secondaryLabelColor];
	remaining_time_label.alignment = NSTextAlignmentRight;

	NSProgressIndicator* loading_indicator = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
	loading_indicator.translatesAutoresizingMaskIntoConstraints = NO;
	loading_indicator.style = NSProgressIndicatorStyleSpinning;
	loading_indicator.controlSize = NSControlSizeSmall;
	loading_indicator.displayedWhenStopped = NO;
	loading_indicator.hidden = YES;

	NSPopUpButton* playback_rate_popup_button = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
	playback_rate_popup_button.translatesAutoresizingMaskIntoConstraints = NO;
	playback_rate_popup_button.controlSize = NSControlSizeSmall;
	playback_rate_popup_button.font = [NSFont systemFontOfSize:12.0];
	playback_rate_popup_button.bordered = NO;
	playback_rate_popup_button.preferredEdge = NSMaxYEdge;
	playback_rate_popup_button.contentTintColor = [NSColor labelColor];
	playback_rate_popup_button.hidden = NO;
	if ([playback_rate_popup_button.cell isKindOfClass:[NSPopUpButtonCell class]]) {
		NSPopUpButtonCell* popup_button_cell = (NSPopUpButtonCell*) playback_rate_popup_button.cell;
		popup_button_cell.arrowPosition = NSPopUpNoArrow;
		popup_button_cell.bordered = NO;
		popup_button_cell.alignment = NSTextAlignmentCenter;
	}
	[self configurePlaybackRatePopUpButton:playback_rate_popup_button];

	[artwork_background_view addSubview:artwork_button];
	[NSLayoutConstraint activateConstraints:@[
		[artwork_button.leadingAnchor constraintEqualToAnchor:artwork_background_view.leadingAnchor],
		[artwork_button.trailingAnchor constraintEqualToAnchor:artwork_background_view.trailingAnchor],
		[artwork_button.topAnchor constraintEqualToAnchor:artwork_background_view.topAnchor],
		[artwork_button.bottomAnchor constraintEqualToAnchor:artwork_background_view.bottomAnchor]
	]];

	NSView* bottom_content_view = [[NSView alloc] initWithFrame:NSZeroRect];
	bottom_content_view.translatesAutoresizingMaskIntoConstraints = NO;

	NSView* controls_container_view = [[NSView alloc] initWithFrame:NSZeroRect];
	controls_container_view.translatesAutoresizingMaskIntoConstraints = NO;

	[controls_container_view addSubview:controls_stack_view];
	[controls_container_view addSubview:progress_slider];
	[controls_container_view addSubview:current_time_label];
	[controls_container_view addSubview:remaining_time_label];
	[NSLayoutConstraint activateConstraints:@[
		[controls_stack_view.centerXAnchor constraintEqualToAnchor:controls_container_view.centerXAnchor],
		[controls_stack_view.topAnchor constraintEqualToAnchor:controls_container_view.topAnchor constant:22.0],
		[progress_slider.topAnchor constraintEqualToAnchor:controls_stack_view.bottomAnchor constant:18.0],
		[progress_slider.leadingAnchor constraintEqualToAnchor:controls_container_view.leadingAnchor],
		[progress_slider.trailingAnchor constraintEqualToAnchor:controls_container_view.trailingAnchor],
		[current_time_label.topAnchor constraintEqualToAnchor:progress_slider.bottomAnchor constant:-3.0],
		[current_time_label.leadingAnchor constraintEqualToAnchor:progress_slider.leadingAnchor],
		[current_time_label.bottomAnchor constraintEqualToAnchor:controls_container_view.bottomAnchor constant:-13.0],
		[remaining_time_label.topAnchor constraintEqualToAnchor:progress_slider.bottomAnchor constant:-3.0],
		[remaining_time_label.trailingAnchor constraintEqualToAnchor:progress_slider.trailingAnchor],
		[remaining_time_label.bottomAnchor constraintEqualToAnchor:controls_container_view.bottomAnchor constant:-13.0]
	]];

	[bottom_content_view addSubview:artwork_background_view];
	[bottom_content_view addSubview:controls_container_view];
	[bottom_content_view addSubview:loading_indicator];
	[bottom_content_view addSubview:playback_rate_popup_button];

	[container_view addSubview:chapters_container_view];
	[container_view addSubview:bottom_content_view];
	NSLayoutConstraint* chapters_container_height_constraint = [chapters_container_view.heightAnchor constraintEqualToConstant:0.0];
	[NSLayoutConstraint activateConstraints:@[
		[back_button.widthAnchor constraintEqualToConstant:28.0],
		[back_button.heightAnchor constraintEqualToConstant:28.0],
		[play_button.widthAnchor constraintEqualToConstant:28.0],
		[play_button.heightAnchor constraintEqualToConstant:28.0],
		[forward_button.widthAnchor constraintEqualToConstant:28.0],
		[forward_button.heightAnchor constraintEqualToConstant:28.0],
		[chapters_container_view.leadingAnchor constraintEqualToAnchor:container_view.leadingAnchor],
		[chapters_container_view.trailingAnchor constraintEqualToAnchor:container_view.trailingAnchor],
		[chapters_container_view.topAnchor constraintEqualToAnchor:container_view.topAnchor],
		chapters_container_height_constraint,
		[bottom_content_view.leadingAnchor constraintEqualToAnchor:container_view.leadingAnchor],
		[bottom_content_view.trailingAnchor constraintEqualToAnchor:container_view.trailingAnchor],
		[bottom_content_view.bottomAnchor constraintEqualToAnchor:container_view.bottomAnchor],
		[bottom_content_view.heightAnchor constraintEqualToConstant:InkwellPodcastCollapsedPaneHeight],
		[chapters_container_view.bottomAnchor constraintEqualToAnchor:bottom_content_view.topAnchor],
		[artwork_background_view.leadingAnchor constraintEqualToAnchor:bottom_content_view.leadingAnchor constant:18.0],
		[artwork_background_view.topAnchor constraintEqualToAnchor:bottom_content_view.topAnchor constant:22.0],
		[artwork_background_view.widthAnchor constraintEqualToConstant:40.0],
		[artwork_background_view.heightAnchor constraintEqualToConstant:40.0],
		[loading_indicator.widthAnchor constraintEqualToConstant:16.0],
		[loading_indicator.heightAnchor constraintEqualToConstant:16.0],
		[loading_indicator.centerYAnchor constraintEqualToAnchor:artwork_background_view.centerYAnchor],
		[loading_indicator.trailingAnchor constraintEqualToAnchor:bottom_content_view.trailingAnchor constant:-28.0],
		[playback_rate_popup_button.widthAnchor constraintEqualToConstant:52.0],
		[playback_rate_popup_button.centerYAnchor constraintEqualToAnchor:artwork_background_view.centerYAnchor],
		[playback_rate_popup_button.trailingAnchor constraintEqualToAnchor:bottom_content_view.trailingAnchor constant:-14.0],
		[controls_container_view.leadingAnchor constraintEqualToAnchor:bottom_content_view.leadingAnchor constant:18.0],
		[controls_container_view.trailingAnchor constraintEqualToAnchor:bottom_content_view.trailingAnchor constant:-18.0],
		[controls_container_view.topAnchor constraintEqualToAnchor:bottom_content_view.topAnchor],
		[controls_container_view.bottomAnchor constraintEqualToAnchor:bottom_content_view.bottomAnchor]
	]];

	self.artworkButton = artwork_button;
	self.artworkBackgroundView = artwork_background_view;
	self.artworkImageView = artwork_button.artworkImageView;
	self.chaptersContainerView = chapters_container_view;
	self.chaptersScrollView = chapters_scroll_view;
	self.chaptersTableView = chapters_table_view;
	self.chaptersSeparatorLineView = chapters_separator_line_view;
	self.chaptersContainerHeightConstraint = chapters_container_height_constraint;
	self.backButton = back_button;
	self.playButton = play_button;
	self.forwardButton = forward_button;
	self.progressSlider = progress_slider;
	self.currentTimeLabel = current_time_label;
	self.remainingTimeLabel = remaining_time_label;
	self.loadingIndicator = loading_indicator;
	self.playbackRatePopUpButton = playback_rate_popup_button;
	self.view = container_view;
	[self updateArtworkImage];
	[self updatePlaybackButtonImage];
	[self updateLoadingIndicator];
	[self updateTimeLabels];
	[self updateAppearance];
}

- (void) setEntry:(MBEntry* _Nullable) entry
{
	NSString* previous_enclosure_url = [_entry.enclosureURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	NSString* next_enclosure_url = [entry.enclosureURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	BOOL did_change_entry = (_entry.entryID != entry.entryID || ![previous_enclosure_url isEqualToString:next_enclosure_url]);
	if (!did_change_entry) {
		_entry = entry;
		return;
	}

	if (did_change_entry) {
		[self updatePlaybackRecordForEntry:_entry artworkURLString:self.artworkURLString];
		[self persistPlaybackRecordsToDisk];
		self.progressSlider.doubleValue = 0.0;
		self.currentChapterIndex = NSNotFound;
		self.chapters = @[];
		[self setChapterListExpanded:NO animated:NO];
	}

	_entry = entry;
	self.progressSlider.doubleValue = [self savedPlaybackPercentForEntry:entry];
	[self updateTimeLabels];
	[self configurePlayerForCurrentEntry];
}

- (void) setChapters:(NSArray*) chapters
{
	NSArray* sanitized_chapters = [chapters isKindOfClass:[NSArray class]] ? [chapters copy] : @[];
	BOOL did_change_chapters = ![_chapters isEqualToArray:sanitized_chapters];
	if (!did_change_chapters) {
		return;
	}

	_chapters = sanitized_chapters;
	if (_chapters.count == 0 && self.isShowingChapterList) {
		[self setChapterListExpanded:NO animated:NO];
	}

	self.artworkButton.hoverEnabled = (_chapters.count > 0);
	self.artworkButton.accessibilityLabel = self.isShowingChapterList ? @"Hide Chapters" : @"Show Chapters";
	[self.artworkButton updateHoverState];
	[self.chaptersTableView reloadData];
	[self updateCurrentChapterIndexForPlaybackSeconds:[self displayedCurrentPlaybackSeconds]];
}

- (void) setArtworkURLString:(NSString*) artwork_url_string
{
	_artworkURLString = [artwork_url_string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	[self updateArtworkImage];
	[self updatePlaybackRecordForEntry:self.entry artworkURLString:_artworkURLString];
	[self persistPlaybackRecordsToDisk];
}

- (void) notifyPaneHeightIfNeeded
{
	if (self.paneHeightChangedHandler != nil) {
		self.paneHeightChangedHandler(self.preferredPaneHeight);
	}
}

- (void) setChapterListExpanded:(BOOL) is_expanded animated:(BOOL) animated
{
	BOOL can_expand = (self.chapters.count > 0);
	BOOL next_is_expanded = (is_expanded && can_expand);
	CGFloat target_height = next_is_expanded ? InkwellPodcastExpandedChaptersHeight : 0.0;
	if (self.isShowingChapterList == next_is_expanded && self.chaptersContainerHeightConstraint.constant == target_height) {
		return;
	}

	self.isShowingChapterList = next_is_expanded;
	self.artworkButton.isExpanded = self.isShowingChapterList;
	self.artworkButton.accessibilityLabel = self.isShowingChapterList ? @"Hide Chapters" : @"Show Chapters";
	self.chaptersSeparatorLineView.hidden = !self.isShowingChapterList;

	if (animated) {
		[self.view layoutSubtreeIfNeeded];
		[NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
			context.duration = 0.18;
			context.allowsImplicitAnimation = YES;
			self.chaptersContainerHeightConstraint.constant = target_height;
			[self.view layoutSubtreeIfNeeded];
		} completionHandler:nil];
	}
	else {
		self.chaptersContainerHeightConstraint.constant = target_height;
		[self.view layoutSubtreeIfNeeded];
	}

	[self notifyPaneHeightIfNeeded];
}

- (NSButton*) transportButtonWithSymbolName:(NSString*) symbol_name accessibilityDescription:(NSString*) accessibility_description action:(SEL) action
{
	NSButton* button = [NSButton buttonWithTitle:@"" target:self action:action];
	button.translatesAutoresizingMaskIntoConstraints = NO;
	button.bordered = NO;
	button.imagePosition = NSImageOnly;
	button.imageScaling = NSImageScaleProportionallyUpOrDown;
	button.contentTintColor = [NSColor labelColor];
	button.image = [NSImage imageWithSystemSymbolName:symbol_name accessibilityDescription:accessibility_description];
	button.image.template = YES;
	return button;
}

- (void) addPlayerStatusObserverIfNeeded
{
	if (self.player == nil || self.isObservingPlayerStatus) {
		return;
	}

	[self.player addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:InkwellPodcastPlayerStatusContext];
	self.isObservingPlayerStatus = YES;
}

- (void) removePlayerStatusObserverIfNeeded
{
	if (self.player == nil || !self.isObservingPlayerStatus) {
		return;
	}

	[self.player removeObserver:self forKeyPath:@"status" context:InkwellPodcastPlayerStatusContext];
	self.isObservingPlayerStatus = NO;
}

- (void) configurePlaybackRatePopUpButton:(NSPopUpButton*) popup_button
{
	[popup_button removeAllItems];

	NSArray* playback_rate_values = @[
		@(1.0),
		@(1.1),
		@(1.2),
		@(1.3),
		@(1.5),
		@(1.8),
		@(2.0)
	];
	NSArray* playback_rate_titles = @[
		@"1×",
		@"1.1×",
		@"1.2×",
		@"1.3×",
		@"1.5×",
		@"1.8×",
		@"2×"
	];

	for (NSInteger i = 0; i < playback_rate_titles.count; i++) {
		NSString* title = playback_rate_titles[(NSUInteger) i];
		NSNumber* value = playback_rate_values[(NSUInteger) i];
		[popup_button addItemWithTitle:title];
		NSMenuItem* item = [popup_button itemAtIndex:i];
		item.representedObject = value;
	}

	double preferred_playback_rate = [self preferredPlaybackRate];
	NSInteger selected_index = 0;
	for (NSInteger i = 0; i < popup_button.numberOfItems; i++) {
		NSMenuItem* item = [popup_button itemAtIndex:i];
		NSNumber* value = [item.representedObject isKindOfClass:[NSNumber class]] ? item.representedObject : @(1.0);
		if (fabs(value.doubleValue - preferred_playback_rate) < DBL_EPSILON) {
			selected_index = i;
			break;
		}
	}

	[popup_button selectItemAtIndex:selected_index];
	popup_button.target = self;
	popup_button.action = @selector(playbackRateSelectionChanged:);
}

- (double) preferredPlaybackRate
{
	double playback_rate = [[NSUserDefaults standardUserDefaults] doubleForKey:InkwellPodcastPlaybackRateDefaultsKey];
	if (playback_rate <= 0.0) {
		return 1.0;
	}

	return playback_rate;
}

- (void) applyPreferredPlaybackRateIfNeeded
{
	if (self.player == nil || !self.isPlaying || self.player.status != AVPlayerStatusReadyToPlay) {
		return;
	}

	self.player.rate = [self preferredPlaybackRate];
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

- (NSString*) normalizedEnclosureURLString:(NSString*) url_string
{
	return [url_string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

- (NSURL* _Nullable) cachedAudioFileURLForURLString:(NSString*) url_string createDirectory:(BOOL) create_directory
{
	NSString* normalized_url = [self normalizedEnclosureURLString:url_string];
	if (normalized_url.length == 0) {
		return nil;
	}

	NSURL* directory_url = [[self class] cachedAudioDirectoryURLCreatingIfNeeded:create_directory];
	if (directory_url == nil) {
		return nil;
	}

	NSString* file_name = [self cachedAudioFilenameForURLString:normalized_url];
	if (file_name.length == 0) {
		return nil;
	}

	return [directory_url URLByAppendingPathComponent:file_name isDirectory:NO];
}

- (BOOL) cachedAudioFileExistsForURLString:(NSString*) url_string
{
	NSURL* cache_file_url = [self cachedAudioFileURLForURLString:url_string createDirectory:NO];
	if (cache_file_url == nil || !cache_file_url.isFileURL) {
		return NO;
	}

	NSFileManager* file_manager = [NSFileManager defaultManager];
	BOOL is_directory = NO;
	if (![file_manager fileExistsAtPath:cache_file_url.path isDirectory:&is_directory] || is_directory) {
		return NO;
	}

	NSDictionary* file_attributes = [file_manager attributesOfItemAtPath:cache_file_url.path error:nil];
	NSNumber* file_size = [file_attributes[NSFileSize] respondsToSelector:@selector(unsignedLongLongValue)] ? file_attributes[NSFileSize] : @(0);
	if (file_size.unsignedLongLongValue == 0) {
		[file_manager removeItemAtURL:cache_file_url error:nil];
		return NO;
	}

	return YES;
}

- (NSString*) cachedAudioFilenameForURLString:(NSString*) url_string
{
	NSString* normalized_url = [self normalizedEnclosureURLString:url_string];
	NSString* hash_string = [self shortSHA1StringForString:normalized_url];
	if (hash_string.length == 0) {
		return @"";
	}

	NSString* host_string = [[NSURL URLWithString:normalized_url].host lowercaseString] ?: @"";
	NSString* base_name = hash_string;
	if (host_string.length > 0) {
		base_name = [NSString stringWithFormat:@"%@-%@", host_string, hash_string];
	}

	return [base_name stringByAppendingPathExtension:[self preferredCachedAudioExtensionForURLString:normalized_url]];
}

- (NSString*) preferredCachedAudioExtensionForURLString:(NSString*) url_string
{
	NSString* extension_value = [[NSURL URLWithString:url_string].pathExtension lowercaseString] ?: @"";
	if (extension_value.length > 0) {
		return extension_value;
	}

	return InkwellPodcastFallbackExtension;
}

- (NSString*) shortSHA1StringForString:(NSString*) string_value
{
	NSData* string_data = [string_value dataUsingEncoding:NSUTF8StringEncoding];
	if (string_data.length == 0) {
		return @"";
	}

	unsigned char digest[CC_SHA1_DIGEST_LENGTH];
	CC_SHA1(string_data.bytes, (CC_LONG) string_data.length, digest);

	NSMutableString* full_hash = [NSMutableString stringWithCapacity:(CC_SHA1_DIGEST_LENGTH * 2)];
	for (NSInteger i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
		[full_hash appendFormat:@"%02x", digest[i]];
	}

	if (full_hash.length <= InkwellPodcastCacheHashLength) {
		return [full_hash copy];
	}

	return [full_hash substringToIndex:InkwellPodcastCacheHashLength];
}

- (NSString*) formattedTimeStringForSeconds:(Float64) seconds
{
	NSInteger total_seconds = (NSInteger) llround(MAX(0.0, seconds));
	NSInteger hours = total_seconds / 3600;
	if (hours > 0) {
		NSInteger minutes = (total_seconds % 3600) / 60;
		NSInteger remaining_seconds = total_seconds % 60;
		return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long) hours, (long) minutes, (long) remaining_seconds];
	}

	NSInteger minutes = total_seconds / 60;
	NSInteger remaining_seconds = total_seconds % 60;
	return [NSString stringWithFormat:@"%ld:%02ld", (long) minutes, (long) remaining_seconds];
}

- (Float64) chapterDurationSecondsAtIndex:(NSUInteger) index
{
	if (index >= self.chapters.count) {
		return 0.0;
	}

	MBPodcastChapter* chapter = self.chapters[index];
	Float64 start_seconds = MAX(0.0, chapter.startSeconds);
	Float64 end_seconds = 0.0;
	if ((index + 1) < self.chapters.count) {
		MBPodcastChapter* next_chapter = self.chapters[index + 1];
		end_seconds = MAX(start_seconds, next_chapter.startSeconds);
	}
	else {
		end_seconds = [self displayedDurationSeconds];
		if (!isfinite(end_seconds) || end_seconds <= start_seconds) {
			return 0.0;
		}
	}

	return MAX(0.0, end_seconds - start_seconds);
}

- (NSUInteger) chapterIndexForPlaybackSeconds:(Float64) playback_seconds
{
	if (self.chapters.count == 0 || !isfinite(playback_seconds) || playback_seconds < 0.0) {
		return NSNotFound;
	}

	for (NSUInteger i = 0; i < self.chapters.count; i++) {
		MBPodcastChapter* chapter = self.chapters[i];
		Float64 start_seconds = MAX(0.0, chapter.startSeconds);
		Float64 next_start_seconds = DBL_MAX;
		if ((i + 1) < self.chapters.count) {
			MBPodcastChapter* next_chapter = self.chapters[i + 1];
			next_start_seconds = MAX(start_seconds, next_chapter.startSeconds);
		}

		if (playback_seconds >= start_seconds && playback_seconds < next_start_seconds) {
			return i;
		}
	}

	MBPodcastChapter* last_chapter = self.chapters.lastObject;
	if (last_chapter != nil && playback_seconds >= MAX(0.0, last_chapter.startSeconds)) {
		return (self.chapters.count - 1);
	}

	return NSNotFound;
}

- (NSString*) chapterDurationStringForIndex:(NSUInteger) index
{
	Float64 duration_seconds = [self chapterDurationSecondsAtIndex:index];
	if (!isfinite(duration_seconds) || duration_seconds <= 0.0) {
		return @"";
	}

	NSInteger total_seconds = (NSInteger) llround(duration_seconds);
	if (total_seconds < 60) {
		return [NSString stringWithFormat:@"%lds", (long) MAX(1, total_seconds)];
	}

	NSInteger total_minutes = (NSInteger) lround(duration_seconds / 60.0);
	return [NSString stringWithFormat:@"%ldm", (long) MAX(1, total_minutes)];
}

- (void) updateCurrentChapterIndexForPlaybackSeconds:(Float64) playback_seconds
{
	NSUInteger next_chapter_index = [self chapterIndexForPlaybackSeconds:playback_seconds];
	if (self.currentChapterIndex == next_chapter_index) {
		return;
	}

	NSUInteger previous_chapter_index = self.currentChapterIndex;
	self.currentChapterIndex = next_chapter_index;

	if (self.chaptersTableView == nil) {
		return;
	}

	NSMutableIndexSet* row_indexes = [NSMutableIndexSet indexSet];
	if (previous_chapter_index != NSNotFound && previous_chapter_index < self.chapters.count) {
		[row_indexes addIndex:previous_chapter_index];
	}
	if (next_chapter_index != NSNotFound && next_chapter_index < self.chapters.count) {
		[row_indexes addIndex:next_chapter_index];
	}

	if (row_indexes.count == 0) {
		return;
	}

	NSIndexSet* column_indexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.chaptersTableView.numberOfColumns)];
	[self.chaptersTableView reloadDataForRowIndexes:row_indexes columnIndexes:column_indexes];
}

- (Float64) displayedDurationSeconds
{
	Float64 duration_seconds = 0.0;
	if (self.player.currentItem != nil) {
		Float64 current_duration_seconds = CMTimeGetSeconds(self.player.currentItem.duration);
		if (isfinite(current_duration_seconds) && current_duration_seconds > 0.0) {
			duration_seconds = current_duration_seconds;
		}
	}

	if (duration_seconds > 0.0) {
		return duration_seconds;
	}

	NSString* duration_string = [self.entry.itunesDuration stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	return [self parsedDurationSecondsFromString:duration_string];
}

- (Float64) parsedDurationSecondsFromString:(NSString*) duration_string
{
	NSString* trimmed_duration_string = [duration_string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (trimmed_duration_string.length == 0) {
		return 0.0;
	}

	if (![trimmed_duration_string containsString:@":"]) {
		return MAX(0.0, trimmed_duration_string.doubleValue);
	}

	NSArray* components = [trimmed_duration_string componentsSeparatedByString:@":"];
	if (components.count == 0) {
		return 0.0;
	}

	Float64 total_seconds = 0.0;
	for (NSString* component in components) {
		NSString* trimmed_component = [component stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		if (trimmed_component.length == 0) {
			return 0.0;
		}

		total_seconds = (total_seconds * 60.0) + MAX(0.0, trimmed_component.doubleValue);
	}

	return total_seconds;
}

- (Float64) savedPlaybackSecondsForEntry:(MBEntry* _Nullable) entry
{
	NSMutableDictionary* dictionary = [self playbackRecordForEntry:entry createIfNeeded:NO];
	if (dictionary == nil) {
		return 0.0;
	}

	id playback_seconds_value = dictionary[InkwellPodcastPlaybackSecondsKey];
	Float64 playback_seconds = [playback_seconds_value respondsToSelector:@selector(doubleValue)] ? [playback_seconds_value doubleValue] : 0.0;
	return MAX(0.0, playback_seconds);
}

- (Float64) displayedCurrentPlaybackSeconds
{
	if (self.isScrubbing) {
		return [self displayedDurationSeconds] * MIN(1.0, MAX(0.0, self.progressSlider.doubleValue));
	}

	if (self.player != nil) {
		Float64 current_seconds = CMTimeGetSeconds(self.player.currentTime);
		if (isfinite(current_seconds) && current_seconds >= 0.0) {
			return current_seconds;
		}
	}

	Float64 saved_playback_seconds = [self savedPlaybackSecondsForEntry:self.entry];
	if (saved_playback_seconds > 0.0) {
		return saved_playback_seconds;
	}

	return [self displayedDurationSeconds] * MIN(1.0, MAX(0.0, self.progressSlider.doubleValue));
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
		[self updateTimeLabels];
		return;
	}

	id playback_percent_value = dictionary[InkwellPodcastPlaybackPercentKey];
	double playback_percent = [playback_percent_value respondsToSelector:@selector(doubleValue)] ? [playback_percent_value doubleValue] : 0.0;
	playback_percent = MIN(1.0, MAX(0.0, playback_percent));
	self.progressSlider.doubleValue = playback_percent;
	[self updateTimeLabels];

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

- (void) updateTimeLabels
{
	Float64 current_seconds = [self displayedCurrentPlaybackSeconds];
	Float64 duration_seconds = [self displayedDurationSeconds];
	Float64 remaining_seconds = MAX(0.0, duration_seconds - current_seconds);

	self.currentTimeLabel.stringValue = [self formattedTimeStringForSeconds:current_seconds];
	self.remainingTimeLabel.stringValue = [NSString stringWithFormat:@"-%@", [self formattedTimeStringForSeconds:remaining_seconds]];
	[self updateCurrentChapterIndexForPlaybackSeconds:current_seconds];
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

- (void) scheduleAudioDownloadIfStillPlaying
{
	NSString* enclosure_url = [self.currentEnclosureURLString copy];
	if (enclosure_url.length == 0 || [self cachedAudioFileExistsForURLString:enclosure_url]) {
		return;
	}

	self.pendingDownloadToken += 1;
	NSUInteger download_token = self.pendingDownloadToken;
	__weak typeof(self) weak_self = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (InkwellPodcastDownloadDelayInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		MBPodcastController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}
		if (download_token != strong_self.pendingDownloadToken) {
			return;
		}
		if (!strong_self.isPlaying) {
			return;
		}
		if (![strong_self.currentEnclosureURLString isEqualToString:enclosure_url]) {
			return;
		}

		[strong_self cacheAudioForURLStringIfNeeded:enclosure_url];
	});
}

- (void) cacheAudioForURLStringIfNeeded:(NSString*) url_string
{
	NSString* normalized_url = [self normalizedEnclosureURLString:url_string];
	if (normalized_url.length == 0 || [self.pendingDownloadURLStrings containsObject:normalized_url] || [self cachedAudioFileExistsForURLString:normalized_url]) {
		return;
	}

	NSURL* remote_url = [NSURL URLWithString:normalized_url];
	NSURL* cache_file_url = [self cachedAudioFileURLForURLString:normalized_url createDirectory:YES];
	if (remote_url == nil || cache_file_url == nil) {
		return;
	}

	[self.pendingDownloadURLStrings addObject:normalized_url];

	__weak typeof(self) weak_self = self;
	NSURLSessionDownloadTask* task = [self.downloadSession downloadTaskWithURL:remote_url completionHandler:^(NSURL* _Nullable location, NSURLResponse* _Nullable response, NSError* _Nullable error) {
		MBPodcastController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		NSFileManager* file_manager = [NSFileManager defaultManager];
		BOOL did_cache_file = NO;
		BOOL did_receive_success_response = ([response isKindOfClass:[NSHTTPURLResponse class]] && ((NSHTTPURLResponse*) response).statusCode == 200);
		if (error == nil && did_receive_success_response && location != nil && ![strong_self cachedAudioFileExistsForURLString:normalized_url]) {
			[file_manager removeItemAtURL:cache_file_url error:nil];
			if ([file_manager moveItemAtURL:location toURL:cache_file_url error:nil]) {
				NSDate* now = [NSDate date];
				[file_manager setAttributes:@{
					NSFileCreationDate: now,
					NSFileModificationDate: now
				} ofItemAtPath:cache_file_url.path error:nil];
				did_cache_file = YES;
			}
		}

		if (!did_cache_file && location != nil) {
			[file_manager removeItemAtURL:location error:nil];
		}

		void (^finish_cache)(void) = ^{
			dispatch_async(dispatch_get_main_queue(), ^{
				[strong_self.pendingDownloadURLStrings removeObject:normalized_url];
				if (did_cache_file) {
					[strong_self trimCachedAudioFilesIfNeeded];
				}
			});
		};
		if (!did_cache_file) {
			finish_cache();
			return;
		}

		[strong_self loadChaptersForCachedAudioFileURL:cache_file_url completion:^{
			finish_cache();
		}];
	}];
	[task resume];
}

- (void) loadChaptersForCachedAudioFileURL:(NSURL*) file_url completion:(void (^ _Nullable)(void)) completion
{
	[self loadPodcastChaptersForAudioFileURL:file_url completion:^(NSArray* chapters) {
		dispatch_async(dispatch_get_main_queue(), ^{
			if ([self shouldApplyChaptersForAudioFileURL:file_url]) {
				self.chapters = chapters ?: @[];
			}
			if (completion != nil) {
				completion();
			}
		});
	}];
}

- (void) loadPodcastChaptersForAudioFileURL:(NSURL*) file_url completion:(void (^)(NSArray* chapters)) completion
{
	AVURLAsset* asset = [AVURLAsset URLAssetWithURL:file_url options:nil];
	if ([self isMP3AudioFileURL:file_url]) {
		[self loadID3MetadataForAudioFileURL:file_url asset:asset completion:completion];
		return;
	}

	[self loadChapterMetadataGroupsForAsset:asset completion:completion];
}

- (void) loadChapterMetadataGroupsForAsset:(AVAsset*) asset completion:(void (^)(NSArray* chapters)) completion
{
	[asset loadChapterMetadataGroupsBestMatchingPreferredLanguages:[NSLocale preferredLanguages] completionHandler:^(NSArray* _Nullable chapter_groups, NSError* _Nullable error) {
		if (error != nil || chapter_groups.count == 0) {
			completion(@[]);
			return;
		}

		completion([self podcastChaptersFromMetadataGroups:chapter_groups]);
	}];
}

- (void) loadID3MetadataForAudioFileURL:(NSURL*) file_url asset:(AVAsset*) asset completion:(void (^)(NSArray* chapters)) completion
{
	[asset loadMetadataForFormat:AVMetadataFormatID3Metadata completionHandler:^(NSArray* _Nullable metadata_items, NSError* _Nullable error) {
		if (error == nil && metadata_items.count > 0) {
			NSArray* chapters = [self podcastChaptersFromID3MetadataItems:metadata_items audioFileURL:file_url];
			if (chapters.count > 0) {
				completion(chapters);
				return;
			}
		}

		[self loadChapterMetadataGroupsForAsset:asset completion:completion];
	}];
}

- (NSArray*) podcastChaptersFromID3MetadataItems:(NSArray*) metadata_items audioFileURL:(NSURL*) file_url
{
	NSInteger tag_major_version = [self id3MajorVersionForAudioFileURL:file_url];
	NSMutableArray* chapters = [NSMutableArray array];
	for (AVMetadataItem* item in metadata_items) {
		MBPodcastChapter* chapter = [self podcastChapterFromID3MetadataItem:item tagMajorVersion:tag_major_version];
		if (chapter != nil) {
			[chapters addObject:chapter];
		}
	}

	return [chapters copy];
}

- (MBPodcastChapter* _Nullable) podcastChapterFromID3MetadataItem:(AVMetadataItem*) item tagMajorVersion:(NSInteger) tag_major_version
{
	if (![item.keySpace isEqualToString:AVMetadataKeySpaceID3] || ![item.key isKindOfClass:[NSString class]]) {
		return nil;
	}

	NSString* frame_id = (NSString*) item.key;
	if (![frame_id isEqualToString:@"CHAP"]) {
		return nil;
	}

	NSData* frame_data = item.dataValue;
	if (frame_data.length <= 17) {
		return nil;
	}

	const unsigned char* bytes = frame_data.bytes;
	NSUInteger element_id_length = 0;
	while (element_id_length < frame_data.length && bytes[element_id_length] != 0x00) {
		element_id_length += 1;
	}
	if (element_id_length >= frame_data.length || frame_data.length < (element_id_length + 17)) {
		return nil;
	}

	NSUInteger offset = element_id_length + 1;
	uint32_t start_time_milliseconds = MBPodcastReadBigEndianUInt32(bytes + offset);
	offset += 16;

	NSString* title = nil;
	NSURL* chapter_url = nil;
	NSUInteger header_size = 10;
	while ((offset + header_size) <= frame_data.length) {
		const unsigned char* subframe_header_bytes = bytes + offset;
		if (subframe_header_bytes[0] == 0x00 && subframe_header_bytes[1] == 0x00 && subframe_header_bytes[2] == 0x00 && subframe_header_bytes[3] == 0x00) {
			break;
		}

		NSString* subframe_id = [[NSString alloc] initWithBytes:subframe_header_bytes length:4 encoding:NSASCIIStringEncoding];
		if (subframe_id.length != 4) {
			break;
		}

		uint32_t subframe_size = (tag_major_version >= 4) ? MBPodcastReadSyncsafeUInt32(subframe_header_bytes + 4) : MBPodcastReadBigEndianUInt32(subframe_header_bytes + 4);
		offset += header_size;
		if (subframe_size == 0 || (offset + subframe_size) > frame_data.length) {
			break;
		}

		NSData* subframe_data = [frame_data subdataWithRange:NSMakeRange(offset, subframe_size)];
		if ([subframe_id isEqualToString:@"TIT2"]) {
			title = [self stringFromID3TextFrameData:subframe_data];
		}
		else if ([subframe_id isEqualToString:@"WXXX"]) {
			chapter_url = [self urlFromID3URLFrameData:subframe_data];
		}

		offset += subframe_size;
	}

	MBPodcastChapter* chapter = [[MBPodcastChapter alloc] init];
	chapter.startSeconds = ((NSTimeInterval) start_time_milliseconds) / 1000.0;
	chapter.title = title;
	chapter.url = chapter_url;
	return chapter;
}

- (NSArray*) podcastChaptersFromMetadataGroups:(NSArray*) chapter_groups
{
	NSMutableArray* chapters = [NSMutableArray arrayWithCapacity:chapter_groups.count];
	for (AVTimedMetadataGroup* group in chapter_groups) {
		CMTime start_time = group.timeRange.start;
		Float64 seconds = CMTimeGetSeconds(start_time);

		NSString* title = nil;
		NSURL* chapter_url = nil;
		for (AVMetadataItem* item in group.items) {
			if ([item.commonKey isEqualToString:AVMetadataCommonKeyTitle]) {
				title = item.stringValue;
			}
			else if ([item.identifier isEqualToString:AVMetadataIdentifierQuickTimeUserDataURLLink] || [item.identifier isEqualToString:AVMetadataIdentifierID3MetadataUserURL] || [item.identifier isEqualToString:AVMetadataIdentifierIcyMetadataStreamURL]) {
				NSString* url_string = item.stringValue ?: @"";
				if (url_string.length > 0) {
					chapter_url = [NSURL URLWithString:url_string];
				}
				else if ([item.value isKindOfClass:[NSURL class]]) {
					chapter_url = (NSURL*) item.value;
				}
			}
		}

		MBPodcastChapter* chapter = [[MBPodcastChapter alloc] init];
		chapter.startSeconds = seconds;
		chapter.title = title;
		chapter.url = chapter_url;
		[chapters addObject:chapter];
	}

	return [chapters copy];
}

- (BOOL) isMP3AudioFileURL:(NSURL*) file_url
{
	NSString* extension_value = file_url.pathExtension.lowercaseString ?: @"";
	return [extension_value isEqualToString:@"mp3"];
}

- (NSInteger) id3MajorVersionForAudioFileURL:(NSURL*) file_url
{
	NSFileHandle* file_handle = [NSFileHandle fileHandleForReadingFromURL:file_url error:nil];
	if (file_handle == nil) {
		return 4;
	}

	NSData* header_data = [file_handle readDataOfLength:10];
	[file_handle closeFile];
	if (header_data.length < 10) {
		return 4;
	}

	const unsigned char* bytes = header_data.bytes;
	if (!(bytes[0] == 'I' && bytes[1] == 'D' && bytes[2] == '3')) {
		return 4;
	}

	return (NSInteger) bytes[3];
}

- (NSString* _Nullable) stringFromID3TextFrameData:(NSData*) data
{
	if (data.length == 0) {
		return nil;
	}

	const unsigned char* bytes = data.bytes;
	uint8_t encoding_byte = bytes[0];
	NSData* string_data = [data subdataWithRange:NSMakeRange(1, data.length - 1)];
	NSStringEncoding string_encoding = NSISOLatin1StringEncoding;
	if (encoding_byte == 1) {
		string_encoding = NSUTF16StringEncoding;
	}
	else if (encoding_byte == 2) {
		string_encoding = NSUTF16BigEndianStringEncoding;
	}
	else if (encoding_byte == 3) {
		string_encoding = NSUTF8StringEncoding;
	}

	NSString* string_value = [[NSString alloc] initWithData:string_data encoding:string_encoding];
	string_value = [string_value stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\0\r\n\t "]];
	return (string_value.length > 0) ? string_value : nil;
}

- (NSUInteger) offsetOfID3TerminatorInData:(NSData*) data encodingByte:(uint8_t) encoding_byte startOffset:(NSUInteger) start_offset
{
	const unsigned char* bytes = data.bytes;
	NSUInteger terminator_length = ((encoding_byte == 1) || (encoding_byte == 2)) ? 2 : 1;
	if (terminator_length == 1) {
		for (NSUInteger i = start_offset; i < data.length; i++) {
			if (bytes[i] == 0x00) {
				return i;
			}
		}
		return NSNotFound;
	}

	for (NSUInteger i = start_offset; (i + 1) < data.length; i++) {
		if (bytes[i] == 0x00 && bytes[i + 1] == 0x00) {
			return i;
		}
	}
	return NSNotFound;
}

- (NSURL* _Nullable) urlFromID3URLFrameData:(NSData*) data
{
	if (data.length == 0) {
		return nil;
	}

	const unsigned char* bytes = data.bytes;
	uint8_t encoding_byte = bytes[0];
	NSUInteger url_offset = 1;
	NSUInteger terminator_offset = [self offsetOfID3TerminatorInData:data encodingByte:encoding_byte startOffset:1];
	if (terminator_offset != NSNotFound) {
		NSUInteger terminator_length = ((encoding_byte == 1) || (encoding_byte == 2)) ? 2 : 1;
		url_offset = terminator_offset + terminator_length;
	}
	if (url_offset >= data.length) {
		return nil;
	}

	NSData* url_data = [data subdataWithRange:NSMakeRange(url_offset, data.length - url_offset)];
	NSString* url_string = [[NSString alloc] initWithData:url_data encoding:NSISOLatin1StringEncoding];
	url_string = [[url_string ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\0\r\n\t "]] copy];
	if (url_string.length == 0) {
		return nil;
	}

	return [NSURL URLWithString:url_string];
}

- (BOOL) shouldApplyChaptersForAudioFileURL:(NSURL*) file_url
{
	NSString* current_enclosure_url = [self.currentEnclosureURLString copy] ?: @"";
	if (current_enclosure_url.length == 0) {
		return NO;
	}

	NSURL* current_cache_file_url = [self cachedAudioFileURLForURLString:current_enclosure_url createDirectory:NO];
	if (current_cache_file_url == nil) {
		return NO;
	}

	return [current_cache_file_url.path isEqualToString:file_url.path];
}

- (void) trimCachedAudioFilesIfNeeded
{
	[[self class] cleanupCachedAudioFiles];
}

- (void) updateLoadingIndicator
{
	BOOL is_loading = (self.player != nil && self.player.status != AVPlayerStatusReadyToPlay);
	self.loadingIndicator.hidden = !is_loading;
	self.playbackRatePopUpButton.hidden = is_loading;
	if (is_loading) {
		[self.loadingIndicator startAnimation:nil];
	}
	else {
		[self.loadingIndicator stopAnimation:nil];
	}
}

- (void) updateAppearance
{
	NSAppearance* appearance = self.view.effectiveAppearance ?: NSApp.effectiveAppearance;
	[appearance performAsCurrentDrawingAppearance:^{
		NSColor* background_color = [NSColor colorNamed:@"color_podcast_background"] ?: [NSColor colorWithWhite:0.92 alpha:0.78];
		self.view.layer.backgroundColor = background_color.CGColor;
		self.backButton.contentTintColor = [NSColor labelColor];
		self.playButton.contentTintColor = [NSColor labelColor];
		self.forwardButton.contentTintColor = [NSColor labelColor];
		self.currentTimeLabel.textColor = [NSColor secondaryLabelColor];
		self.remainingTimeLabel.textColor = [NSColor secondaryLabelColor];
		self.playbackRatePopUpButton.contentTintColor = [NSColor labelColor];
		self.chaptersSeparatorLineView.layer.backgroundColor = [NSColor separatorColor].CGColor;
		[self updatePlaybackButtonImage];
		[self.progressSlider refreshAppearance];
		[self.chaptersTableView reloadData];
		[self.view setNeedsDisplay:YES];
	}];
}

- (NSInteger) numberOfRowsInTableView:(NSTableView*) table_view
{
	if (table_view != self.chaptersTableView) {
		return 0;
	}

	return self.chapters.count;
}

- (NSView* _Nullable) tableView:(NSTableView*) table_view viewForTableColumn:(NSTableColumn*) table_column row:(NSInteger) row
{
	if (table_view != self.chaptersTableView || row < 0 || row >= (NSInteger) self.chapters.count) {
		return nil;
	}

	NSString* identifier = [table_column.identifier isEqualToString:@"ChapterTimeColumn"] ? @"PodcastChapterTimeCell" : @"PodcastChapterTitleCell";
	NSTableCellView* cell_view = [table_view makeViewWithIdentifier:identifier owner:self];
	if (cell_view == nil) {
		cell_view = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
		cell_view.identifier = identifier;

		NSTextField* text_field = [NSTextField labelWithString:@""];
		text_field.translatesAutoresizingMaskIntoConstraints = NO;
		text_field.lineBreakMode = NSLineBreakByTruncatingTail;
		text_field.maximumNumberOfLines = 1;
		[cell_view addSubview:text_field];
		[NSLayoutConstraint activateConstraints:@[
			[text_field.leadingAnchor constraintEqualToAnchor:cell_view.leadingAnchor constant:4.0],
			[text_field.trailingAnchor constraintEqualToAnchor:cell_view.trailingAnchor constant:-4.0],
			[text_field.centerYAnchor constraintEqualToAnchor:cell_view.centerYAnchor]
		]];
		cell_view.textField = text_field;
	}

	MBPodcastChapter* chapter = self.chapters[(NSUInteger) row];
	NSTextField* text_field = cell_view.textField;
	BOOL is_current_chapter = (self.currentChapterIndex == (NSUInteger) row);
	if ([table_column.identifier isEqualToString:@"ChapterTimeColumn"]) {
		text_field.stringValue = [self chapterDurationStringForIndex:(NSUInteger) row];
		text_field.font = [NSFont monospacedDigitSystemFontOfSize:11.0 weight:is_current_chapter ? NSFontWeightSemibold : NSFontWeightMedium];
		text_field.textColor = is_current_chapter ? [NSColor labelColor] : [NSColor secondaryLabelColor];
		text_field.alignment = NSTextAlignmentRight;
	}
	else {
		text_field.stringValue = [chapter.title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		text_field.font = [NSFont systemFontOfSize:12.0 weight:is_current_chapter ? NSFontWeightSemibold : NSFontWeightRegular];
		text_field.textColor = [NSColor labelColor];
		text_field.alignment = NSTextAlignmentLeft;
	}

	return cell_view;
}

- (CGFloat) tableView:(NSTableView*) table_view heightOfRow:(NSInteger) row
{
	#pragma unused(row)
	if (table_view != self.chaptersTableView) {
		return 20.0;
	}

	return 30.0;
}

- (BOOL) tableView:(NSTableView*) table_view shouldSelectRow:(NSInteger) row
{
	#pragma unused(row)
	return (table_view == self.chaptersTableView);
}

- (void) tableViewSelectionDidChange:(NSNotification*) notification
{
	NSTableView* table_view = [notification.object isKindOfClass:[NSTableView class]] ? (NSTableView*) notification.object : nil;
	if (table_view != self.chaptersTableView) {
		return;
	}

	NSInteger selected_row = table_view.selectedRow;
	if (selected_row < 0 || selected_row >= (NSInteger) self.chapters.count) {
		return;
	}

	[self seekToChapterAtIndex:(NSUInteger) selected_row];
	[table_view deselectAll:nil];
}

- (void) configurePlayerForCurrentEntry
{
	NSString* enclosure_url = [self normalizedEnclosureURLString:self.entry.enclosureURL];
	if ([enclosure_url isEqualToString:self.currentEnclosureURLString]) {
		return;
	}

	[[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.player.currentItem];
	[self.player pause];
	[self removePlayerStatusObserverIfNeeded];
	[self removeTimeObserverIfNeeded];
	self.player = nil;
	self.currentEnclosureURLString = enclosure_url;
	self.pendingDownloadToken += 1;
	[self setPlayingState:NO notify:NO];
	self.progressSlider.doubleValue = [self savedPlaybackPercentForEntry:self.entry];
	[self updateLoadingIndicator];
	[self updateTimeLabels];

	if (enclosure_url.length == 0) {
		return;
	}

	NSURL* podcast_url = [NSURL URLWithString:enclosure_url];
	if (podcast_url == nil) {
		return;
	}

	NSURL* playback_url = podcast_url;
	if ([self cachedAudioFileExistsForURLString:enclosure_url]) {
		NSURL* cache_file_url = [self cachedAudioFileURLForURLString:enclosure_url createDirectory:NO];
		if (cache_file_url != nil) {
			playback_url = cache_file_url;
			[self loadChaptersForCachedAudioFileURL:cache_file_url completion:nil];
		}
	}

	AVPlayerItem* player_item = [AVPlayerItem playerItemWithURL:playback_url];
	AVPlayer* player = [AVPlayer playerWithPlayerItem:player_item];
	player.automaticallyWaitsToMinimizeStalling = YES;
	self.player = player;
	[self addPlayerStatusObserverIfNeeded];

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
	[self updateTimeLabels];

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
	if (!self.isPlaying) {
		self.pendingDownloadToken += 1;
	}
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
		[self updateTimeLabels];
		return;
	}

	AVPlayerItem* player_item = self.player.currentItem;
	if (player_item == nil) {
		if (self.entry == nil) {
			self.progressSlider.doubleValue = 0.0;
		}
		[self updateTimeLabels];
		return;
	}

	Float64 duration_seconds = CMTimeGetSeconds(player_item.duration);
	Float64 current_seconds = CMTimeGetSeconds(self.player.currentTime);
	if (!isfinite(duration_seconds) || duration_seconds <= 0.0 || !isfinite(current_seconds) || current_seconds < 0.0) {
		[self updateTimeLabels];
		return;
	}

	self.progressSlider.doubleValue = MIN(1.0, MAX(0.0, current_seconds / duration_seconds));
	[self updateTimeLabels];
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
	self.playButton.image.template = YES;
}

- (void) avatarImageDidLoad:(NSNotification*) notification
{
	NSString* url_string = [notification.userInfo[MBAvatarLoaderURLStringUserInfoKey] isKindOfClass:[NSString class]] ? notification.userInfo[MBAvatarLoaderURLStringUserInfoKey] : @"";
	if (![url_string isEqualToString:self.artworkURLString]) {
		return;
	}

	[self updateArtworkImage];
}

- (void) observeValueForKeyPath:(NSString*) key_path ofObject:(id) object change:(NSDictionary<NSKeyValueChangeKey,id>*) change context:(void*) context
{
	#pragma unused(change)
	if (context == InkwellPodcastPlayerStatusContext) {
		#pragma unused(object)
		dispatch_async(dispatch_get_main_queue(), ^{
			[self updateLoadingIndicator];
			if (self.player.status == AVPlayerStatusFailed) {
				[self.player pause];
				[self setPlayingState:NO notify:YES];
				return;
			}

			[self applyPreferredPlaybackRateIfNeeded];
			[self.chaptersTableView reloadData];
		});
		return;
	}

	[super observeValueForKeyPath:key_path ofObject:object change:change context:context];
}

- (void) playbackDidFinish:(NSNotification*) notification
{
	#pragma unused(notification)
	[self.player pause];
	self.progressSlider.doubleValue = 1.0;
	[self updateTimeLabels];
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

- (void) seekToChapterAtIndex:(NSUInteger) index
{
	if (index >= self.chapters.count) {
		return;
	}

	if (self.player == nil) {
		[self configurePlayerForCurrentEntry];
	}

	if (self.player == nil) {
		return;
	}

	MBPodcastChapter* chapter = self.chapters[index];
	Float64 target_seconds = MAX(0.0, chapter.startSeconds);
	CMTime target_time = CMTimeMakeWithSeconds(target_seconds, NSEC_PER_SEC);
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

- (IBAction) toggleChaptersList:(id) sender
{
	#pragma unused(sender)
	if (self.chapters.count == 0) {
		return;
	}

	[self setChapterListExpanded:!self.isShowingChapterList animated:YES];
}

- (IBAction) togglePlayback:(id) sender
{
	#pragma unused(sender)
	if (self.player == nil) {
		[self configurePlayerForCurrentEntry];
	}

	AVPlayerItem* player_item = self.player.currentItem;
	BOOL has_failed_player = (self.player.status == AVPlayerStatusFailed || player_item.status == AVPlayerItemStatusFailed);
	if (has_failed_player) {
		self.currentEnclosureURLString = @"";
		[self configurePlayerForCurrentEntry];
		player_item = self.player.currentItem;
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

	if (player_item == nil || self.player.status == AVPlayerStatusFailed || player_item.status == AVPlayerItemStatusFailed) {
		return;
	}

	Float64 duration_seconds = CMTimeGetSeconds(player_item.duration);
	Float64 current_seconds = CMTimeGetSeconds(self.player.currentTime);
	BOOL is_at_end = (isfinite(duration_seconds) && duration_seconds > 0.0 && isfinite(current_seconds) && current_seconds >= (duration_seconds - 0.5));
	if (is_at_end) {
		[self.player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
	}

	[self.player play];
	[self setPlayingState:YES notify:YES];
	[self applyPreferredPlaybackRateIfNeeded];
	[self scheduleAudioDownloadIfStillPlaying];
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
	[self updateTimeLabels];
	if (!self.isScrubbing) {
		[self seekPlayerToSliderPositionPreservingScrubState:NO];
	}
}

- (IBAction) playbackRateSelectionChanged:(id) sender
{
	NSPopUpButton* popup_button = [sender isKindOfClass:[NSPopUpButton class]] ? (NSPopUpButton*) sender : self.playbackRatePopUpButton;
	NSNumber* selected_value = [[popup_button selectedItem].representedObject isKindOfClass:[NSNumber class]] ? [popup_button selectedItem].representedObject : @(1.0);
	[[NSUserDefaults standardUserDefaults] setDouble:selected_value.doubleValue forKey:InkwellPodcastPlaybackRateDefaultsKey];
	[self applyPreferredPlaybackRateIfNeeded];
}

@end
