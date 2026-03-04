//
//  MBRoundedImageView.m
//  Inkwell
//
//  Created by Manton Reece on 3/4/26.
//

#import "MBRoundedImageView.h"

@implementation MBRoundedImageView

- (instancetype) initWithFrame:(NSRect)frame_rect
{
	self = [super initWithFrame:frame_rect];
	if (self) {
		[self commonInit];
	}
	return self;
}

- (instancetype) initWithCoder:(NSCoder *)coder
{
	self = [super initWithCoder:coder];
	if (self) {
		[self commonInit];
	}
	return self;
}

- (void) commonInit
{
	self.wantsLayer = YES;
	self.layer.masksToBounds = YES;
	self.imageScaling = NSImageScaleAxesIndependently;
}

- (void) layout
{
	[super layout];
	self.layer.cornerRadius = MIN(NSWidth(self.bounds), NSHeight(self.bounds)) * 0.5;
}

@end
