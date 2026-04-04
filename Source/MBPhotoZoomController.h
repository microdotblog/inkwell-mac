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

+ (NSURL * _Nullable) normalizedImageURL:(NSURL *)imageURL;
- (NSPoint) cascadeWindowFromTopLeftPoint:(NSPoint) topLeftPoint;
- (NSPoint) nextWindowCascadeTopLeftPoint;
- (void) showWindowForImageURL:(NSURL *)imageURL;

@end

NS_ASSUME_NONNULL_END
