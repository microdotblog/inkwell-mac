//
//  MBPodcastController.h
//  Inkwell
//
//  Created by Codex on 3/18/26.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class MBEntry;
@class MBPodcastChapter;

@interface MBPodcastController : NSViewController

+ (void) cleanupCachedAudioFiles;
@property (nonatomic, strong, nullable) MBEntry* entry;
@property (nonatomic, copy) NSString* artworkURLString;
@property (nonatomic, copy, readonly) NSArray* chapters;
@property (nonatomic, assign, readonly) BOOL isPlaying;
@property (nonatomic, assign, readonly) CGFloat preferredPaneHeight;
@property (nonatomic, copy, nullable) void (^paneHeightChangedHandler)(CGFloat preferred_height);
@property (nonatomic, copy, nullable) void (^playbackStateChangedHandler)(BOOL is_playing);

@end

NS_ASSUME_NONNULL_END
