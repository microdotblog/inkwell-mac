//
//  MBSidebarController.h
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface MBSidebarController : NSViewController

@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *items;
@property (nonatomic, copy, nullable) void (^selectionChangedHandler)(NSDictionary<NSString *, NSString *> * _Nullable item);

- (void) reloadDataAndSelectFirstItem;

@end

NS_ASSUME_NONNULL_END
