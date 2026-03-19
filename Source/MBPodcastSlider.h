//
//  MBPodcastSlider.h
//  Inkwell
//
//  Created by Codex on 3/19/26.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface MBPodcastSlider : NSSlider

@property (nonatomic, copy, nullable) void (^trackingStateChangedHandler)(BOOL is_tracking);
@property (nonatomic, assign, readonly) BOOL isTrackingSlider;

@end

NS_ASSUME_NONNULL_END
