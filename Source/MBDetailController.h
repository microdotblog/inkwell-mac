//
//  MBDetailController.h
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface MBDetailController : NSViewController

- (void) showSidebarItem:(NSDictionary<NSString *, NSString *> * _Nullable)item;

@end

NS_ASSUME_NONNULL_END
