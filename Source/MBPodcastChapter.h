//
//  MBPodcastChapter.h
//  Inkwell
//
//  Created by Codex on 3/20/26.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MBPodcastChapter : NSObject

@property (nonatomic, assign) NSTimeInterval startSeconds;
@property (nonatomic, copy, nullable) NSString* title;
@property (nonatomic, strong, nullable) NSURL* url;

@end

NS_ASSUME_NONNULL_END
