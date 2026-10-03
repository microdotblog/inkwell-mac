//
//  MBSidebarRowView.m
//  Inkwell
//
//  Created by Codex on 3/31/26.
//

#import "MBSidebarRowView.h"
#import "MBSidebarCell.h"

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

- (void) setSelected:(BOOL)selected
{
	[super setSelected:selected];
	[self updateCellAppearance];
	[self setNeedsDisplay:YES];
}

- (void) setEmphasized:(BOOL)emphasized
{
	[super setEmphasized:emphasized];
	[self updateCellAppearance];
}

- (void) didAddSubview:(NSView *)subview
{
	[super didAddSubview:subview];
	[self updateCellAppearance];
}

- (void) updateCellAppearance
{
	for (NSView* view in self.subviews) {
		if ([view isKindOfClass:[MBSidebarCell class]]) {
			[(MBSidebarCell*) view updateAppearance];
		}
	}
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
	if (self.isSelected || self.customBackgroundColor == nil) {
		return;
	}

	NSRect fill_rect = NSInsetRect(self.bounds, InkwellSidebarRowBackgroundHorizontalInset, InkwellSidebarRowBackgroundVerticalInset);
	NSBezierPath* background_path = [NSBezierPath bezierPathWithRoundedRect:fill_rect xRadius:10.0 yRadius:10.0];
	[self.customBackgroundColor setFill];
	[background_path fill];
	if (self.customBorderColor != nil) {
		[self.customBorderColor setStroke];
		background_path.lineWidth = 1.0;
		[background_path stroke];
	}
}

@end
