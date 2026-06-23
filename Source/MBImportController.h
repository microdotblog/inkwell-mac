//
//  MBImportController.h
//  Inkwell
//
//  Created by Manton Reece on 6/22/26.
//

#import <Cocoa/Cocoa.h>

@class MBClient;

NS_ASSUME_NONNULL_BEGIN

@interface MBImportController : NSWindowController

@property (nonatomic, assign, readonly) BOOL isImporting;

- (instancetype) initWithClient:(MBClient *)client token:(NSString *)token;
- (void) beginImportFromWindow:(NSWindow * _Nullable)presentationWindow completion:(void (^)(BOOL didChangeFeeds))completion;

@end

NS_ASSUME_NONNULL_END
