//
//  MBPodcastContainerView.h
//  Inkwell
//
//  Created by Codex on 3/31/26.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface MBPodcastContainerView : NSView

@property (nonatomic, copy, nullable) void (^appearanceChangedHandler)(void);

@end

NS_ASSUME_NONNULL_END
