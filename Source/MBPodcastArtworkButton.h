//
//  MBPodcastArtworkButton.h
//  Inkwell
//
//  Created by Codex on 3/31/26.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface MBPodcastArtworkButton : NSButton

@property (nonatomic, strong, readonly) NSImageView* artworkImageView;
@property (nonatomic, assign) BOOL isExpanded;
@property (nonatomic, assign) BOOL hoverEnabled;

- (void) updateHoverState;

@end

NS_ASSUME_NONNULL_END
