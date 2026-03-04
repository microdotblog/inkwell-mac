//
//  MBAuthController.h
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import <Foundation/Foundation.h>

@class MBClient;

NS_ASSUME_NONNULL_BEGIN

@interface MBAuthController : NSObject

- (instancetype) initWithClient:(MBClient *)client;
- (void) beginSignInWithCompletion:(void (^)(NSError * _Nullable error))completion;
- (BOOL) handleCallbackURL:(NSURL *)url completion:(void (^)(NSString * _Nullable token, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
