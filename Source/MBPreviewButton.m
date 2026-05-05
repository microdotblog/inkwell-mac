//
//  MBPreviewButton.m
//  Inkwell
//
//  Created by Codex on 5/3/26.
//

#import "MBPreviewButton.h"

static NSString* const InkwellPreviewButtonBackgroundColorName = @"color_preview_button_background";

@interface MBPreviewButton ()

- (NSColor *) selectedBackgroundColor;

@end

@implementation MBPreviewButton

- (void) viewDidMoveToWindow
{
	[super viewDidMoveToWindow];
}

- (NSColor *) selectedBackgroundColor
{
	NSColor* background_color = [NSColor colorNamed:InkwellPreviewButtonBackgroundColorName] ?: [NSColor colorWithCalibratedWhite:0.92 alpha:1.0];
	__block NSColor* resolved_background_color = background_color;
	[self.effectiveAppearance performAsCurrentDrawingAppearance:^{
		resolved_background_color = [background_color colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace] ?: background_color;
	}];
	return resolved_background_color;
}

- (void) drawRect:(NSRect)dirty_rect
{
	if (self.state != NSControlStateValueOn) {
		[super drawRect:dirty_rect];
		return;
	}

	NSBezierPath* background_path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1.0, 1.0) xRadius:18.0 yRadius:18.0];
	[[self selectedBackgroundColor] setFill];
	[background_path fill];

	NSColor* text_color = self.enabled ? NSColor.labelColor : NSColor.disabledControlTextColor;
	NSDictionary* attributes = @{
		NSFontAttributeName: self.font ?: [NSFont systemFontOfSize:NSFont.systemFontSize],
		NSForegroundColorAttributeName: text_color
	};
	NSAttributedString* title = [[NSAttributedString alloc] initWithString:(self.title ?: @"") attributes:attributes];
	NSSize title_size = title.size;
	NSRect title_rect = NSMakeRect(NSMidX(self.bounds) - (title_size.width / 2.0), NSMidY(self.bounds) - (title_size.height / 2.0), title_size.width, title_size.height);
	[title drawInRect:title_rect];
}

- (void) setState:(NSControlStateValue)value
{
	[super setState:value];
	self.needsDisplay = YES;
}

- (void) viewDidChangeEffectiveAppearance
{
	[super viewDidChangeEffectiveAppearance];
	self.needsDisplay = YES;
}

@end
