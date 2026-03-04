//
//  MBSidebarController.h
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import <Cocoa/Cocoa.h>

@class MBClient;

NS_ASSUME_NONNULL_BEGIN

@interface MBSidebarController : NSViewController

@property (nonatomic, strong, nullable) MBClient *client;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *items;
@property (nonatomic, copy, nullable) void (^selectionChangedHandler)(NSDictionary<NSString *, NSString *> * _Nullable item);
@property (nonatomic, copy, nullable) NSString *token;

- (void) reloadDataAndSelectFirstItem;

@end

NS_ASSUME_NONNULL_END
