//
//  MBPreviewButton.m
//  Inkwell
//
//  Created by Codex on 5/3/26.
//

#import "MBPreviewButton.h"

static NSString* const InkwellPreviewButtonBackgroundColorName = @"color_preview_button_background";

@interface MBPreviewButton ()

- (void) updateSelectedBackground;

@end

@implementation MBPreviewButton

- (void) viewDidMoveToWindow
{
	[super viewDidMoveToWindow];
	
	self.wantsLayer = YES;
	self.layer.cornerRadius = 18;
	self.layer.masksToBounds = YES;
}

- (void) updateSelectedBackground
{
	if (self.state == NSControlStateValueOn) {
		NSColor* background_color = [NSColor colorNamed:InkwellPreviewButtonBackgroundColorName] ?: [NSColor colorWithCalibratedWhite:0.92 alpha:1.0];
		__block NSColor* resolved_background_color = background_color;
		[self.effectiveAppearance performAsCurrentDrawingAppearance:^{
			resolved_background_color = [background_color colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace] ?: background_color;
		}];
		self.layer.backgroundColor = resolved_background_color.CGColor;
		return;
	}

	self.layer.backgroundColor = nil;
}

- (void) setState:(NSControlStateValue)value
{
	[super setState:value];
	[self updateSelectedBackground];
}

- (void) viewDidChangeEffectiveAppearance
{
	[super viewDidChangeEffectiveAppearance];
	[self updateSelectedBackground];
}

@end
