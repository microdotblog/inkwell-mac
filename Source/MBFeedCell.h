//
//  MBFeedCell.h
//  Inkwell
//
//  Created by Codex on 3/18/26.
//

#import <Cocoa/Cocoa.h>

@class MBSubscription;

NS_ASSUME_NONNULL_BEGIN

@interface MBFeedCell : NSTableCellView

@property (copy, nullable) NSMenu* (^contextMenuHandler)(void);

- (void) configureWithSubscription:(MBSubscription*) subscription avatarImage:(NSImage*) avatar_image;

@end

NS_ASSUME_NONNULL_END
