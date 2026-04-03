//
//  MBPhotoZoomController.h
//  Inkwell
//
//  Created by Codex on 4/3/26.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface MBPhotoZoomController : NSWindowController

- (void) showWindowForImageURL:(NSURL *)image_url;

@end

NS_ASSUME_NONNULL_END
