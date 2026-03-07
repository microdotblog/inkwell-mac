//
//  MBMainController.h
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import <Cocoa/Cocoa.h>

@class MBClient;

NS_ASSUME_NONNULL_BEGIN

@interface MBMainController : NSWindowController

- (instancetype) initWithWindow:(nullable NSWindow *)window;
- (instancetype) initWithWindow:(nullable NSWindow *)window client:(nullable MBClient *)client token:(nullable NSString *)token;
- (IBAction) showPreferences:(id) sender;

@end

NS_ASSUME_NONNULL_END
