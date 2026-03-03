//
//  MBWelcomeController.h
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface MBWelcomeController : NSWindowController

@property (copy, nullable) void (^signInHandler)(void);

@end

NS_ASSUME_NONNULL_END
