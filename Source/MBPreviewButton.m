//
//  MBPreviewButton.m
//  Inkwell
//
//  Created by Codex on 5/3/26.
//

#import "MBPreviewButton.h"

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
		NSAppearanceName best_match = [self.effectiveAppearance bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]];
		if ([best_match isEqualToString:NSAppearanceNameDarkAqua]) {
			self.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.28 alpha:1.0].CGColor;
		}
		else {
			self.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.92 alpha:1.0].CGColor;
		}
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
