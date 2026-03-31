//
//  MBPodcastArtworkButton.m
//  Inkwell
//
//  Created by Codex on 3/31/26.
//

#import "MBPodcastArtworkButton.h"
#import "MBPodcastPassthroughImageView.h"
#import "MBPodcastPassthroughView.h"

@interface MBPodcastArtworkButton ()

@property (nonatomic, strong, readwrite) NSImageView* artworkImageView;
@property (nonatomic, strong) MBPodcastPassthroughView* hoverOverlayView;
@property (nonatomic, strong) MBPodcastPassthroughImageView* overlayImageView;
@property (nonatomic, strong, nullable) NSTrackingArea* trackingArea;
@property (nonatomic, assign) BOOL isHovering;

- (void) updateOverlayImage;

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
