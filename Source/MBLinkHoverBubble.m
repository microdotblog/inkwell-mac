//
//  MBLinkHoverBubble.m
//  Inkwell
//
//  Created by Codex on 3/18/26.
//

#import "MBLinkHoverBubble.h"

static NSString* const InkwellHoverBackgroundColorName = @"color_hover_background";
static CGFloat const InkwellLinkBubbleCornerRadius = 14.0;

@interface MBLinkHoverBubble ()

- (void) updateBubbleBackgroundColor;

@end

@implementation MBLinkHoverBubble

- (instancetype) initWithFrame:(NSRect) frame_rect
{
	self = [super initWithFrame:frame_rect];
	if (self) {
		self.translatesAutoresizingMaskIntoConstraints = NO;
		self.wantsLayer = YES;
		self.layer.cornerRadius = InkwellLinkBubbleCornerRadius;
		self.layer.masksToBounds = YES;
		[self updateBubbleBackgroundColor];
	}
	return self;
}

- (NSView*) hitTest:(NSPoint) point
{
	#pragma unused(point)
	return nil;
}

- (void) viewDidChangeEffectiveAppearance
{
	[super viewDidChangeEffectiveAppearance];
	[self updateBubbleBackgroundColor];
}

- (void) updateBubbleBackgroundColor
{
	NSColor* bubble_background_color = [NSColor colorNamed:InkwellHoverBackgroundColorName];
	if (bubble_background_color == nil) {
		bubble_background_color = [[NSColor controlBackgroundColor] colorWithAlphaComponent:0.96];
	}
	self.layer.backgroundColor = bubble_background_color.CGColor;
}

@end
