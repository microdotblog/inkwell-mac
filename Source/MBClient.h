//
//  MBClient.h
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class MBSubscription;
@class MBHighlight;

extern NSString * const MBClientErrorDomain;
extern NSString* const MBClientNetworkingDidStartNotification;
extern NSString* const MBClientNetworkingDidStopNotification;

@interface MBClient : NSObject

@property (copy, readonly) NSString *clientID;
@property (copy, readonly) NSString *redirectURI;

- (NSURL *) authorizationURLWithState:(NSString *)state;
- (void) exchangeAuthorizationCode:(NSString *)code completion:(void (^)(NSString * _Nullable token, NSError * _Nullable error))completion;
- (void) verifyToken:(NSString *)token completion:(void (^)(BOOL is_valid, NSError * _Nullable error))completion;
- (void) fetchFeedEntriesWithToken:(NSString *)token completion:(void (^)(NSArray<MBSubscription *> * _Nullable subscriptions, NSArray<NSDictionary<NSString *, id> *> * _Nullable entries, NSSet * _Nullable unread_entry_ids, BOOL is_finished, NSError * _Nullable error))completion;
- (void) fetchFeedIconsWithToken:(NSString *)token completion:(void (^)(NSDictionary<NSString *, NSString *> * _Nullable icons_by_host, NSError * _Nullable error))completion;
- (void) fetchReadingRecapForEntryIDs:(NSArray*) entry_ids token:(NSString*) token completion:(void (^)(NSInteger status_code, NSString* _Nullable html, NSError* _Nullable error))completion;
- (void) fetchHighlightsForEntryID:(NSInteger)entry_id token:(NSString*) token completion:(void (^)(NSArray* _Nullable highlights, NSError* _Nullable error))completion;
- (void) markAsRead:(NSInteger)entry_id token:(NSString*) token completion:(void (^)(NSError * _Nullable error))completion;
- (void) markAsUnread:(NSInteger)entry_id token:(NSString*) token completion:(void (^)(NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
