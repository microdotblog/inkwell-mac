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
- (void) showWindowForImageURL:(NSURL *)imageURL relatedPostURL:(NSURL * _Nullable)relatedPostURL;
- (void) updateRelatedPostURL:(NSURL * _Nullable)relatedPostURL;

@end

NS_ASSUME_NONNULL_END
