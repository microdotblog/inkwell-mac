//
//  MBPodcastController.h
//  Inkwell
//
//  Created by Codex on 3/18/26.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class MBEntry;

@interface MBPodcastController : NSViewController

+ (void) cleanupCachedAudioFiles;
@property (nonatomic, strong, nullable) MBEntry* entry;
@property (nonatomic, copy) NSString* artworkURLString;
@property (nonatomic, assign, readonly) BOOL isPlaying;
@property (nonatomic, copy, nullable) void (^playbackStateChangedHandler)(BOOL is_playing);

@end

NS_ASSUME_NONNULL_END
