//
//  MBPodcastPassthroughImageView.m
//  Inkwell
//
//  Created by Codex on 3/31/26.
//

#import "MBPodcastPassthroughImageView.h"

@implementation MBPodcastPassthroughImageView

- (NSView*) hitTest:(NSPoint) point
{
	#pragma unused(point)
	return nil;
}

@end
