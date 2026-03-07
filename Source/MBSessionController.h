//
//  MBSessionController.h
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString* const InkwellTokenDefaultsKey;

@interface MBSessionController : NSObject

- (BOOL) hasToken;
- (NSString * _Nullable) token;
- (void) saveToken:(NSString *)token;
- (void) clearToken;

@end

NS_ASSUME_NONNULL_END
