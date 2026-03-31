//
//  MBSidebarRowView.m
//  Inkwell
//
//  Created by Codex on 3/31/26.
//

#import "MBSidebarRowView.h"

static CGFloat const InkwellSidebarRowBackgroundHorizontalInset = 10.0;
static CGFloat const InkwellSidebarRowBackgroundVerticalInset = 2.5;

@implementation MBSidebarRowView

- (void) setCustomBackgroundColor:(NSColor *)custom_background_color
{
	if ((_customBackgroundColor == custom_background_color) || [_customBackgroundColor isEqual:custom_background_color]) {
		return;
	}

	_customBackgroundColor = custom_background_color;
	[self setNeedsDisplay:YES];
}

- (void) setCustomSelectionBackgroundColor:(NSColor*) custom_selection_background_color
{
	if ((_customSelectionBackgroundColor == custom_selection_background_color) || [_customSelectionBackgroundColor isEqual:custom_selection_background_color]) {
		return;
	}

	_customSelectionBackgroundColor = custom_selection_background_color;
	[self setNeedsDisplay:YES];
}

- (void) setCustomBorderColor:(NSColor*) custom_border_color
{
	if ((_customBorderColor == custom_border_color) || [_customBorderColor isEqual:custom_border_color]) {
		return;
	}

	_customBorderColor = custom_border_color;
	[self setNeedsDisplay:YES];
}

- (void) drawBackgroundInRect:(NSRect)dirty_rect
{
	[super drawBackgroundInRect:dirty_rect];
	#pragma unused(dirty_rect)
	NSColor* fill_color = self.customSelectionBackgroundColor;
	if (fill_color == nil) {
		fill_color = self.customBackgroundColor;
	}

	if (fill_color == nil) {
		return;
	}

	NSRect fill_rect = NSInsetRect(self.bounds, InkwellSidebarRowBackgroundHorizontalInset, InkwellSidebarRowBackgroundVerticalInset);
	NSBezierPath* background_path = [NSBezierPath bezierPathWithRoundedRect:fill_rect xRadius:10.0 yRadius:10.0];
	[fill_color setFill];
	[background_path fill];
	if (self.customBorderColor != nil) {
		[self.customBorderColor setStroke];
		background_path.lineWidth = 1.0;
		[background_path stroke];
	}
}

- (void) drawSelectionInRect:(NSRect)dirty_rect
{
	if (self.customSelectionBackgroundColor != nil) {
		#pragma unused(dirty_rect)
		return;
	}

	[super drawSelectionInRect:dirty_rect];
}

@end
