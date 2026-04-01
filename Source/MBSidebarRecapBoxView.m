//
//  MBSidebarRecapBoxView.m
//  Inkwell
//
//  Created by Codex on 3/31/26.
//

#import "MBSidebarRecapBoxView.h"

@implementation MBSidebarRecapBoxView

- (instancetype) initWithFrame:(NSRect) frame_rect
{
	self = [super initWithFrame:frame_rect];
	if (self) {
		[self updateFillColor];
	}
	return self;
}

- (void) viewDidChangeEffectiveAppearance
{
	[super viewDidChangeEffectiveAppearance];
	[self updateFillColor];
}

- (void) updateFillColor
{
	[self.effectiveAppearance performAsCurrentDrawingAppearance:^{
		self.fillColor = [[NSColor controlBackgroundColor] colorWithAlphaComponent:0.5];
	}];
}

@end
