//
//  MBClient.h
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class MBSubscription;

extern NSString * const MBClientErrorDomain;
extern NSString* const MBClientNetworkingDidStartNotification;
extern NSString* const MBClientNetworkingDidStopNotification;

@interface MBClient : NSObject

@property (copy, readonly) NSString *clientID;
@property (copy, readonly) NSString *redirectURI;

- (NSURL *) authorizationURLWithState:(NSString *)state;
- (void) exchangeAuthorizationCode:(NSString *)code completion:(void (^)(NSString * _Nullable token, NSError * _Nullable error))completion;
- (void) verifyToken:(NSString *)token completion:(void (^)(BOOL is_valid, NSError * _Nullable error))completion;
- (void) fetchFeedEntriesWithToken:(NSString *)token completion:(void (^)(NSArray<MBSubscription *> * _Nullable subscriptions, NSArray<NSDictionary<NSString *, id> *> * _Nullable entries, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
