//
//  MBPhotoZoomController.h
//  Inkwell
//
//  Created by Codex on 4/3/26.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class MBPhotoZoomController;

@interface MBPhotoZoomController : NSWindowController

@property (nonatomic, strong, readonly, nullable) NSURL* imageURL;
@property (nonatomic, copy, nullable) void (^windowWillCloseHandler)(MBPhotoZoomController* controller);

- (NSPoint) cascadeWindowFromTopLeftPoint:(NSPoint) top_left_point;
- (NSPoint) nextWindowCascadeTopLeftPoint;
- (void) showWindowForImageURL:(NSURL *)image_url;

@end

NS_ASSUME_NONNULL_END
