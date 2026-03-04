//
//  MBSidebarController.h
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import <Cocoa/Cocoa.h>

@class MBClient;
@class MBEntry;

NS_ASSUME_NONNULL_BEGIN

@interface MBSidebarController : NSViewController

@property (nonatomic, strong, nullable) MBClient *client;
@property (nonatomic, copy) NSArray<MBEntry *> *items;
@property (nonatomic, copy, nullable) void (^selectionChangedHandler)(MBEntry * _Nullable item);
@property (nonatomic, copy, nullable) NSString *token;

- (void) reloadDataAndSelectFirstItem;

@end

NS_ASSUME_NONNULL_END
