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
extern NSString* const InkwellIsPremiumDefaultsKey;
extern NSString* const InkwellHasInkwellDefaultsKey;
extern NSString* const InkwellUsernameDefaultsKey;
extern NSString* const InkwellUserAvatarURLDefaultsKey;
extern NSString* const InkwellTextBackgroundColorDefaultsKey;
extern NSString* const InkwellTextFontNameDefaultsKey;
extern NSString* const InkwellTextSizeNameDefaultsKey;
extern NSString* const InkwellSidebarSelectedEntryIDDefaultsKey;

@interface MBClient : NSObject

@property (copy, readonly) NSString *clientID;
@property (copy, readonly) NSString *redirectURI;

- (NSURL *) authorizationURLWithState:(NSString *)state;
- (void) exchangeAuthorizationCode:(NSString *)code completion:(void (^)(NSString * _Nullable token, NSError * _Nullable error))completion;
- (void) verifyToken:(NSString *)token completion:(void (^)(BOOL is_valid, NSError * _Nullable error))completion;
- (void) fetchFeedSubscriptionsWithToken:(NSString*) token completion:(void (^)(NSArray* _Nullable subscriptions, NSError* _Nullable error))completion;
- (void) createFeedSubscriptionWithURLString:(NSString*) url_string token:(NSString*) token completion:(void (^)(NSInteger status_code, MBSubscription* _Nullable subscription, NSArray* _Nullable choices, NSError* _Nullable error))completion;
- (void) fetchFeedEntriesWithToken:(NSString *)token completion:(void (^)(NSArray<MBSubscription *> * _Nullable subscriptions, NSArray<NSDictionary<NSString *, id> *> * _Nullable entries, NSSet * _Nullable unread_entry_ids, BOOL is_finished, NSError * _Nullable error))completion;
- (void) fetchFeedIconsWithToken:(NSString *)token completion:(void (^)(NSDictionary<NSString *, NSString *> * _Nullable icons_by_host, NSError * _Nullable error))completion;
- (void) fetchConversationForURLString:(NSString*) url_string completion:(void (^)(NSDictionary* _Nullable conversation_payload, NSError* _Nullable error))completion;
- (void) fetchReadingRecapForEntryIDs:(NSArray*) entry_ids token:(NSString*) token completion:(void (^)(NSInteger status_code, NSString* _Nullable html, NSError* _Nullable error))completion;
- (void) beginManualNetworkingActivity;
- (void) endManualNetworkingActivity;
- (void) fetchAllHighlightsWithToken:(NSString*) token completion:(void (^)(NSArray* _Nullable highlights, NSError* _Nullable error))completion;
- (void) fetchHighlightsForEntryID:(NSInteger)entry_id token:(NSString*) token completion:(void (^)(NSArray* _Nullable highlights, NSError* _Nullable error))completion;
- (void) createHighlightForEntryID:(NSInteger)entry_id selectionText:(NSString*) selection_text selectionStart:(NSInteger) selection_start selectionEnd:(NSInteger) selection_end token:(NSString*) token completion:(void (^)(NSString* _Nullable highlight_id, NSError* _Nullable error))completion;
- (void) deleteHighlight:(MBHighlight*) highlight token:(NSString*) token completion:(void (^)(NSError* _Nullable error))completion;
- (NSArray* _Nullable) cachedAllHighlights;
- (NSArray* _Nullable) cachedHighlightsForEntryID:(NSInteger) entry_id;
- (void) mergeRemoteHighlightsIntoCache:(NSArray* _Nullable) highlights;
- (MBHighlight* _Nullable) saveLocalHighlightForEntryID:(NSInteger) entry_id postTitle:(NSString*) post_title postURL:(NSString*) post_url selectionText:(NSString*) selection_text selectionStart:(NSInteger) selection_start selectionEnd:(NSInteger) selection_end;
- (void) assignRemoteHighlightID:(NSString*) highlight_id toLocalHighlightID:(NSString*) local_id entryID:(NSInteger) entry_id;
- (void) deleteFeedSubscription:(MBSubscription*) subscription token:(NSString*) token completion:(void (^)(NSError* _Nullable error))completion;
- (void) markAsRead:(NSInteger)entry_id token:(NSString*) token completion:(void (^)(NSError * _Nullable error))completion;
- (void) markAsUnread:(NSInteger)entry_id token:(NSString*) token completion:(void (^)(NSError * _Nullable error))completion;
- (void) bookmarkEntry:(NSInteger)entry_id token:(NSString*) token completion:(void (^)(NSError * _Nullable error))completion;
- (void) unbookmarkEntry:(NSInteger)entry_id token:(NSString*) token completion:(void (^)(NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
