//
//  MBExportController.h
//  Inkwell
//
//  Created by Manton Reece on 6/22/26.
//

#import <Cocoa/Cocoa.h>

@class MBClient;

NS_ASSUME_NONNULL_BEGIN

@interface MBExportController : NSObject

@property (nonatomic, assign, readonly) BOOL isExporting;

- (instancetype) initWithClient:(MBClient *)client;
- (void) beginExportFromWindow:(NSWindow * _Nullable)presentationWindow;

@end

NS_ASSUME_NONNULL_END
