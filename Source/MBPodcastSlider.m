//
//  MBPodcastSlider.m
//  Inkwell
//
//  Created by Codex on 3/19/26.
//

#import "MBPodcastSlider.h"

@interface MBPodcastSliderCell : NSSliderCell

@end

@interface MBPodcastSlider ()

@property (nonatomic, assign, readwrite) BOOL isTrackingSlider;

- (void) notifyTrackingStateChanged:(BOOL) is_tracking;
- (void) sendTrackingAction;

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
	[[[NSColor quaternaryLabelColor] colorWithAlphaComponent:0.6] setFill];
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
	[[NSColor labelColor] setFill];
	[progress_path fill];
}

- (void) drawKnob:(NSRect) knob_rect
{
	#pragma unused(knob_rect)
}

- (BOOL) startTrackingAt:(NSPoint) start_point inView:(NSView*) control_view
{
	BOOL is_tracking = [super startTrackingAt:start_point inView:control_view];
	if ([control_view isKindOfClass:[MBPodcastSlider class]]) {
		[(MBPodcastSlider*) control_view notifyTrackingStateChanged:YES];
	}

	return is_tracking;
}

- (BOOL) continueTracking:(NSPoint) last_point at:(NSPoint) current_point inView:(NSView*) control_view
{
	BOOL should_continue = [super continueTracking:last_point at:current_point inView:control_view];
	if ([control_view isKindOfClass:[MBPodcastSlider class]]) {
		[(MBPodcastSlider*) control_view sendTrackingAction];
	}

	return should_continue;
}

- (void) stopTracking:(NSPoint) last_point at:(NSPoint) stop_point inView:(NSView*) control_view mouseIsUp:(BOOL) flag
{
	[super stopTracking:last_point at:stop_point inView:control_view mouseIsUp:flag];
	if ([control_view isKindOfClass:[MBPodcastSlider class]]) {
		MBPodcastSlider* slider = (MBPodcastSlider*) control_view;
		[slider notifyTrackingStateChanged:NO];
		[slider sendTrackingAction];
	}
}

@end

@implementation MBPodcastSlider

- (instancetype) initWithFrame:(NSRect) frame_rect
{
	self = [super initWithFrame:frame_rect];
	if (self) {
		self.cell = [[MBPodcastSliderCell alloc] init];
	}
	return self;
}

- (void) setDoubleValue:(double) double_value
{
	[super setDoubleValue:double_value];
	[self setNeedsDisplay:YES];
}

- (void) viewDidChangeEffectiveAppearance
{
	[super viewDidChangeEffectiveAppearance];
	[self refreshAppearance];
}

- (void) refreshAppearance
{
	[self setNeedsDisplay:YES];
}

- (void) notifyTrackingStateChanged:(BOOL) is_tracking
{
	self.isTrackingSlider = is_tracking;
	if (self.trackingStateChangedHandler != nil) {
		self.trackingStateChangedHandler(is_tracking);
	}
}

- (void) sendTrackingAction
{
	if (self.action != nil) {
		[self sendAction:self.action to:self.target];
	}
}

@end
