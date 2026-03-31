//
//  MBPodcastContainerView.m
//  Inkwell
//
//  Created by Codex on 3/31/26.
//

#import "MBPodcastContainerView.h"

@implementation MBPodcastContainerView

- (void) viewDidChangeEffectiveAppearance
{
	[super viewDidChangeEffectiveAppearance];
	if (self.appearanceChangedHandler != nil) {
		self.appearanceChangedHandler();
	}
}

@end
