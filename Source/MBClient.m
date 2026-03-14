//
//  MBClient.m
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import "MBClient.h"
#import "MBHighlight.h"
#import "MBSessionController.h"
#import "MBSubscription.h"

NSString * const MBClientErrorDomain = @"MBClientErrorDomain";
NSString* const MBClientNetworkingDidStartNotification = @"MBClientNetworkingDidStartNotification";
NSString* const MBClientNetworkingDidStopNotification = @"MBClientNetworkingDidStopNotification";
NSString* const InkwellIsPremiumDefaultsKey = @"IsPremium";
NSString* const InkwellHasInkwellDefaultsKey = @"HasInkwell";
NSString* const InkwellUsernameDefaultsKey = @"Username";
NSString* const InkwellUserAvatarURLDefaultsKey = @"UserAvatarURL";
NSString* const InkwellTextBackgroundColorDefaultsKey = @"TextBackgroundColor";
NSString* const InkwellTextFontNameDefaultsKey = @"TextFontName";
NSString* const InkwellTextSizeNameDefaultsKey = @"TextSizeName";
NSString* const InkwellReadingRecapDayOfWeekDefaultsKey = @"ReadingRecapDayOfWeek";
NSString* const InkwellSidebarSelectedEntryIDDefaultsKey = @"SidebarSelectedEntryID";

static NSString * const MBClientIdentifierURL = @"https://micro.ink";
static NSString * const MBRedirectURI = @"inkwell://signin";
#define MBMicroBlogBaseURL @"https://micro.blog"
static NSString * const MBAuthorizationEndpoint = MBMicroBlogBaseURL @"/indieauth/auth";
static NSString * const MBTokenEndpoint = MBMicroBlogBaseURL @"/indieauth/token";
static NSString * const MBVerifyEndpoint = MBMicroBlogBaseURL @"/account/verify";
static NSString * const MBFeedSubscriptionsEndpoint = MBMicroBlogBaseURL @"/feeds/v2/subscriptions.json";
static NSString* const MBFeedSubscriptionsEndpointBase = MBMicroBlogBaseURL @"/feeds/v2/subscriptions";
static NSString * const MBFeedEntriesEndpoint = MBMicroBlogBaseURL @"/feeds/v2/entries.json";
static NSString * const MBFeedUnreadEntriesEndpoint = MBMicroBlogBaseURL @"/feeds/v2/unread_entries.json";
static NSString * const MBFeedStarredEntriesEndpoint = MBMicroBlogBaseURL @"/feeds/v2/starred_entries.json";
static NSString * const MBFeedIconsEndpoint = MBMicroBlogBaseURL @"/feeds/v2/icons.json";
static NSString* const MBRecentBookmarksEndpoint = MBMicroBlogBaseURL @"/posts/bookmarks";
static NSString* const MBFeedHighlightsEndpoint = MBMicroBlogBaseURL @"/feeds/highlights";
static NSString* const MBFeedsEndpointBase = MBMicroBlogBaseURL @"/feeds";
static NSString* const MBFeedsRecapEndpoint = MBMicroBlogBaseURL @"/feeds/recap";
static NSString* const MBFeedsRecapEmailEndpoint = MBMicroBlogBaseURL @"/feeds/recap/email";
static NSInteger const MBFeedEntriesPageSize = 200;
static NSTimeInterval const MBFeedEntriesLookbackInterval = 7.0 * 24.0 * 60.0 * 60.0;
static NSString* const MBUnreadEntryIDsCacheFilename = @"unread_entry_ids.json";
static NSString* const MBHighlightsCacheFilename = @"highlights.json";

@interface MBClient ()

@property (strong) NSURLSession *session;
@property (assign) NSInteger activeRequestCount;
@property (copy) NSSet* cachedUnreadEntryIDs;
@property (copy) NSArray* cachedHighlights;

@end

@implementation MBClient

- (instancetype) init
{
	self = [super init];
	if (self) {
		self.session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
		self.cachedUnreadEntryIDs = [self loadCachedUnreadEntryIDs];
		self.cachedHighlights = [self loadCachedHighlights];
	}
	return self;
}

- (NSString *) clientID
{
	return MBClientIdentifierURL;
}

- (NSString *) redirectURI
{
	return MBRedirectURI;
}

- (NSURL *) authorizationURLWithState:(NSString *)state
{
	NSURLComponents *components = [NSURLComponents componentsWithString:MBAuthorizationEndpoint];
	if (components == nil) {
		return [NSURL URLWithString:MBAuthorizationEndpoint];
	}

	components.queryItems = @[
		[NSURLQueryItem queryItemWithName:@"client_id" value:self.clientID],
		[NSURLQueryItem queryItemWithName:@"scope" value:@"create"],
		[NSURLQueryItem queryItemWithName:@"state" value:state],
		[NSURLQueryItem queryItemWithName:@"response_type" value:@"code"],
		[NSURLQueryItem queryItemWithName:@"redirect_uri" value:self.redirectURI]
	];

	return components.URL;
}

- (void) exchangeAuthorizationCode:(NSString *)code completion:(void (^)(NSString * _Nullable token, NSError * _Nullable error))completion
{
	if (code.length == 0) {
		NSError *error = [NSError errorWithDomain:MBClientErrorDomain code:1001 userInfo:@{ NSLocalizedDescriptionKey: @"Missing authorization code." }];
		[self finishWithToken:nil error:error completion:completion];
		return;
	}

	NSString *body_string = [NSString stringWithFormat:@"code=%@&client_id=%@&grant_type=authorization_code&redirect_uri=%@",
		[self urlEncodedString:code],
		[self urlEncodedString:self.clientID],
		[self urlEncodedString:self.redirectURI]];

	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:MBTokenEndpoint]];
	request.HTTPMethod = @"POST";
	request.HTTPBody = [body_string dataUsingEncoding:NSUTF8StringEncoding];
	[request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
	[request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

	NSURLSessionDataTask *task = [self trackedDataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
		if (error != nil) {
			[self finishWithToken:nil error:error completion:completion];
			return;
		}

		NSHTTPURLResponse *http_response = (NSHTTPURLResponse *) response;
		if (http_response.statusCode < 200 || http_response.statusCode >= 300) {
			NSString *description = [self responseDescriptionForData:data defaultMessage:@"Sign in failed while requesting a token."];
			NSError *request_error = [NSError errorWithDomain:MBClientErrorDomain code:http_response.statusCode userInfo:@{ NSLocalizedDescriptionKey: description }];
			[self finishWithToken:nil error:request_error completion:completion];
			return;
		}

		id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
		if (![payload isKindOfClass:[NSDictionary class]]) {
			NSString *description = @"Token response was invalid.";
			NSError *parse_error = [NSError errorWithDomain:MBClientErrorDomain code:1002 userInfo:@{ NSLocalizedDescriptionKey: description }];
			[self finishWithToken:nil error:parse_error completion:completion];
			return;
		}

		NSDictionary *dictionary = (NSDictionary *) payload;
		NSString *access_token = dictionary[@"access_token"];
		if (access_token.length == 0) {
			NSString *description = dictionary[@"error_description"] ?: @"Missing access token in response.";
			NSError *token_error = [NSError errorWithDomain:MBClientErrorDomain code:1003 userInfo:@{ NSLocalizedDescriptionKey: description }];
			[self finishWithToken:nil error:token_error completion:completion];
			return;
		}

		[self finishWithToken:access_token error:nil completion:completion];
	}];
	[task resume];
}

- (void) verifyToken:(NSString *)token completion:(void (^)(BOOL is_valid, NSError * _Nullable error))completion
{
	if (token.length == 0) {
		NSError *error = [NSError errorWithDomain:MBClientErrorDomain code:1004 userInfo:@{ NSLocalizedDescriptionKey: @"Missing token to verify." }];
		[self finishVerify:NO error:error completion:completion];
		return;
	}

	NSString *body_string = [NSString stringWithFormat:@"token=%@", [self urlEncodedString:token]];

	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:MBVerifyEndpoint]];
	request.HTTPMethod = @"POST";
	request.HTTPBody = [body_string dataUsingEncoding:NSUTF8StringEncoding];
	[request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
	[request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

	NSURLSessionDataTask *task = [self trackedDataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
		if (error != nil) {
			[self finishVerify:NO error:error completion:completion];
			return;
		}

		NSHTTPURLResponse *http_response = (NSHTTPURLResponse *) response;
		if (http_response.statusCode < 200 || http_response.statusCode >= 300) {
			NSString *description = [self responseDescriptionForData:data defaultMessage:@"Token verification failed."];
			NSError *verify_error = [NSError errorWithDomain:MBClientErrorDomain code:http_response.statusCode userInfo:@{ NSLocalizedDescriptionKey: description }];
			[self finishVerify:NO error:verify_error completion:completion];
			return;
		}

		id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
		if (![payload isKindOfClass:[NSDictionary class]]) {
			NSError* parse_error = [NSError errorWithDomain:MBClientErrorDomain code:1024 userInfo:@{ NSLocalizedDescriptionKey: @"Token verification response was invalid." }];
			[self finishVerify:NO error:parse_error completion:completion];
			return;
		}

		NSDictionary* dictionary = (NSDictionary*) payload;
		BOOL is_premium = [self boolValueFromObject:dictionary[@"is_premium"] defaultValue:YES];
		BOOL has_inkwell = [self boolValueFromObject:dictionary[@"has_inkwell"] defaultValue:YES];
		NSString* username = [self stringValueFromObject:dictionary[@"username"]];
		NSString* avatar_url = [self stringValueFromObject:dictionary[@"avatar"]];
		if (avatar_url.length == 0) {
			avatar_url = [self stringValueFromObject:dictionary[@"photo"]];
		}
		NSString* replacement_token = [self stringValueFromObject:dictionary[@"token"]];
		NSString* normalized_replacement_token = [replacement_token stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";

		NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
		if (normalized_replacement_token.length > 0) {
			[defaults setObject:normalized_replacement_token forKey:InkwellTokenDefaultsKey];
		}
		[defaults setBool:is_premium forKey:InkwellIsPremiumDefaultsKey];
		[defaults setBool:has_inkwell forKey:InkwellHasInkwellDefaultsKey];
		if (username.length > 0) {
			[defaults setObject:username forKey:InkwellUsernameDefaultsKey];
		}
		else {
			[defaults removeObjectForKey:InkwellUsernameDefaultsKey];
		}

		NSString* normalized_avatar_url = [avatar_url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		if (normalized_avatar_url.length > 0) {
			[defaults setObject:normalized_avatar_url forKey:InkwellUserAvatarURLDefaultsKey];
		}
		else {
			[defaults removeObjectForKey:InkwellUserAvatarURLDefaultsKey];
		}

		if (!has_inkwell) {
			NSError* inkwell_error = [NSError errorWithDomain:MBClientErrorDomain code:1025 userInfo:@{ NSLocalizedDescriptionKey: @"Inkwell is not enabled for your account yet." }];
			[self finishVerify:NO error:inkwell_error completion:completion];
			return;
		}

		[self finishVerify:YES error:nil completion:completion];
	}];
	[task resume];
}

- (void) fetchFeedEntriesWithToken:(NSString *)token completion:(void (^)(NSArray<MBSubscription *> * _Nullable subscriptions, NSArray<NSDictionary<NSString *,id> *> * _Nullable entries, NSSet * _Nullable unread_entry_ids, BOOL is_finished, NSError * _Nullable error))completion
{
	if (token.length == 0) {
		NSError *error = [NSError errorWithDomain:MBClientErrorDomain code:1005 userInfo:@{ NSLocalizedDescriptionKey: @"Missing token for entries request." }];
		[self finishWithSubscriptions:nil entries:nil unreadEntryIDs:nil isFinished:YES error:error completion:completion];
		return;
	}

	NSString *authorization_value = [NSString stringWithFormat:@"Bearer %@", token];
	NSMutableURLRequest *unread_request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:MBFeedUnreadEntriesEndpoint]];
	unread_request.HTTPMethod = @"GET";
	[unread_request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
	[unread_request setValue:authorization_value forHTTPHeaderField:@"Authorization"];

	NSURLSessionDataTask *unread_task = [self trackedDataTaskWithRequest:unread_request completionHandler:^(NSData * _Nullable unread_data, NSURLResponse * _Nullable unread_response, NSError * _Nullable unread_error) {
		NSSet* unread_entry_ids = nil;
		if (unread_error == nil) {
			NSHTTPURLResponse* unread_http_response = (NSHTTPURLResponse*) unread_response;
			if (unread_http_response.statusCode >= 200 && unread_http_response.statusCode < 300) {
				id unread_payload = [NSJSONSerialization JSONObjectWithData:unread_data options:0 error:nil];
				if ([unread_payload isKindOfClass:[NSArray class]]) {
					unread_entry_ids = [self unreadEntryIDsFromPayload:(NSArray*) unread_payload];
				}
			}
		}

		if (unread_entry_ids == nil) {
			unread_entry_ids = self.cachedUnreadEntryIDs ?: [NSSet set];
		}
		else {
			self.cachedUnreadEntryIDs = unread_entry_ids;
			[self cacheUnreadEntryIDs:self.cachedUnreadEntryIDs];
		}

		NSMutableURLRequest *subscriptions_request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:MBFeedSubscriptionsEndpoint]];
		subscriptions_request.HTTPMethod = @"GET";
		[subscriptions_request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
		[subscriptions_request setValue:authorization_value forHTTPHeaderField:@"Authorization"];

		NSURLSessionDataTask *subscriptions_task = [self trackedDataTaskWithRequest:subscriptions_request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
			NSArray* subscriptions = [self subscriptionsFromData:data response:response error:error];
			if (subscriptions == nil) {
				NSError* subscriptions_error = [self subscriptionsErrorFromData:data response:response error:error];
				[self finishWithSubscriptions:nil entries:nil unreadEntryIDs:nil isFinished:YES error:subscriptions_error completion:completion];
				return;
			}

			NSDate* cutoff_date = [[NSDate date] dateByAddingTimeInterval:-MBFeedEntriesLookbackInterval];
			NSMutableArray* accumulated_entries = [NSMutableArray array];
			NSMutableSet* seen_entry_ids = [NSMutableSet set];
			[self fetchPagedFeedEntriesWithAuthorizationValue:authorization_value pageNumber:1 cutoffDate:cutoff_date accumulatedEntries:accumulated_entries seenEntryIDs:seen_entry_ids update:^(NSArray* updated_entries) {
				[self finishWithSubscriptions:subscriptions entries:updated_entries unreadEntryIDs:unread_entry_ids isFinished:NO error:nil completion:completion];
			} completion:^(NSArray* _Nullable entries, NSError* _Nullable entries_error) {
				if (entries_error != nil) {
					[self finishWithSubscriptions:subscriptions entries:nil unreadEntryIDs:nil isFinished:YES error:entries_error completion:completion];
					return;
				}

				[self finishWithSubscriptions:subscriptions entries:entries unreadEntryIDs:unread_entry_ids isFinished:YES error:nil completion:completion];
			}];
		}];
		[subscriptions_task resume];
	}];
	[unread_task resume];
}

- (void) fetchFeedSubscriptionsWithToken:(NSString*) token completion:(void (^)(NSArray* _Nullable subscriptions, NSError* _Nullable error))completion
{
	if (token.length == 0) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1033 userInfo:@{ NSLocalizedDescriptionKey: @"Missing token for subscriptions request." }];
		[self finishWithFeedSubscriptions:nil error:error completion:completion];
		return;
	}

	NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:MBFeedSubscriptionsEndpoint]];
	request.HTTPMethod = @"GET";
	[request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

	NSString* authorization_value = [NSString stringWithFormat:@"Bearer %@", token];
	[request setValue:authorization_value forHTTPHeaderField:@"Authorization"];

	NSURLSessionDataTask* task = [self trackedDataTaskWithRequest:request completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
		NSArray* subscriptions = [self subscriptionsFromData:data response:response error:error];
		if (subscriptions == nil) {
			NSError* subscriptions_error = [self subscriptionsErrorFromData:data response:response error:error];
			[self finishWithFeedSubscriptions:nil error:subscriptions_error completion:completion];
			return;
		}

		[self finishWithFeedSubscriptions:subscriptions error:nil completion:completion];
	}];
	[task resume];
}

- (void) createFeedSubscriptionWithURLString:(NSString*) url_string token:(NSString*) token completion:(void (^)(NSInteger status_code, MBSubscription* _Nullable subscription, NSArray* _Nullable choices, NSError* _Nullable error))completion
{
	NSString* trimmed_url_string = [url_string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (trimmed_url_string.length == 0) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1036 userInfo:@{ NSLocalizedDescriptionKey: @"Missing feed URL for subscription request." }];
		[self finishCreateFeedSubscriptionWithStatusCode:0 subscription:nil choices:nil error:error completion:completion];
		return;
	}

	if (token.length == 0) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1037 userInfo:@{ NSLocalizedDescriptionKey: @"Missing token for subscription request." }];
		[self finishCreateFeedSubscriptionWithStatusCode:0 subscription:nil choices:nil error:error completion:completion];
		return;
	}

	NSURL* request_url = [NSURL URLWithString:MBFeedSubscriptionsEndpoint];
	if (request_url == nil) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1038 userInfo:@{ NSLocalizedDescriptionKey: @"Subscriptions endpoint URL was invalid." }];
		[self finishCreateFeedSubscriptionWithStatusCode:0 subscription:nil choices:nil error:error completion:completion];
		return;
	}

	NSData* body_data = [NSJSONSerialization dataWithJSONObject:@{ @"feed_url": trimmed_url_string } options:0 error:nil];
	if (body_data.length == 0) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1039 userInfo:@{ NSLocalizedDescriptionKey: @"Subscription request body was invalid." }];
		[self finishCreateFeedSubscriptionWithStatusCode:0 subscription:nil choices:nil error:error completion:completion];
		return;
	}

	NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:request_url];
	request.HTTPMethod = @"POST";
	request.HTTPBody = body_data;
	[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	[request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

	NSString* authorization_value = [NSString stringWithFormat:@"Bearer %@", token];
	[request setValue:authorization_value forHTTPHeaderField:@"Authorization"];

	NSURLSessionDataTask* task = [self trackedDataTaskWithRequest:request completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
		if (error != nil) {
			[self finishCreateFeedSubscriptionWithStatusCode:0 subscription:nil choices:nil error:error completion:completion];
			return;
		}

		NSHTTPURLResponse* http_response = (NSHTTPURLResponse*) response;
		NSInteger status_code = http_response.statusCode;
		if (status_code == 300) {
			id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
			if (![payload isKindOfClass:[NSArray class]]) {
				NSError* parse_error = [NSError errorWithDomain:MBClientErrorDomain code:1040 userInfo:@{ NSLocalizedDescriptionKey: @"Subscription choices response was invalid." }];
				[self finishCreateFeedSubscriptionWithStatusCode:status_code subscription:nil choices:nil error:parse_error completion:completion];
				return;
			}

			NSArray* choices = [self subscriptionChoicesFromPayload:(NSArray*) payload];
			[self finishCreateFeedSubscriptionWithStatusCode:status_code subscription:nil choices:choices error:nil completion:completion];
			return;
		}

		if (status_code == 302 || (status_code >= 200 && status_code < 300)) {
			id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
			if (![payload isKindOfClass:[NSDictionary class]]) {
				NSError* parse_error = [NSError errorWithDomain:MBClientErrorDomain code:1041 userInfo:@{ NSLocalizedDescriptionKey: @"Subscription response was invalid." }];
				[self finishCreateFeedSubscriptionWithStatusCode:status_code subscription:nil choices:nil error:parse_error completion:completion];
				return;
			}

			MBSubscription* subscription = [self subscriptionFromDictionary:(NSDictionary*) payload];
			if (subscription == nil) {
				NSError* parse_error = [NSError errorWithDomain:MBClientErrorDomain code:1041 userInfo:@{ NSLocalizedDescriptionKey: @"Subscription response was invalid." }];
				[self finishCreateFeedSubscriptionWithStatusCode:status_code subscription:nil choices:nil error:parse_error completion:completion];
				return;
			}

			[self finishCreateFeedSubscriptionWithStatusCode:status_code subscription:subscription choices:nil error:nil completion:completion];
			return;
		}

		NSString* description = [self responseDescriptionForData:data defaultMessage:@"Subscription request failed."];
		NSError* request_error = [NSError errorWithDomain:MBClientErrorDomain code:status_code userInfo:@{ NSLocalizedDescriptionKey: description }];
		[self finishCreateFeedSubscriptionWithStatusCode:status_code subscription:nil choices:nil error:request_error completion:completion];
	}];
	[task resume];
}

- (void) fetchPagedFeedEntriesWithAuthorizationValue:(NSString*) authorization_value pageNumber:(NSInteger) page_number cutoffDate:(NSDate*) cutoff_date accumulatedEntries:(NSMutableArray*) accumulated_entries seenEntryIDs:(NSMutableSet*) seen_entry_ids update:(void (^ _Nullable)(NSArray* entries))update completion:(void (^)(NSArray* _Nullable entries, NSError* _Nullable error))completion
{
	NSURLComponents* components = [NSURLComponents componentsWithString:MBFeedEntriesEndpoint];
	if (components == nil) {
		NSError* parse_error = [NSError errorWithDomain:MBClientErrorDomain code:1007 userInfo:@{ NSLocalizedDescriptionKey: @"Entries endpoint URL was invalid." }];
		[self finishWithPagedEntries:nil error:parse_error completion:completion];
		return;
	}

	NSMutableArray* query_items = [NSMutableArray array];
	[query_items addObject:[NSURLQueryItem queryItemWithName:@"page" value:[NSString stringWithFormat:@"%ld", (long) page_number]]];
	[query_items addObject:[NSURLQueryItem queryItemWithName:@"per_page" value:[NSString stringWithFormat:@"%ld", (long) MBFeedEntriesPageSize]]];
	components.queryItems = [query_items copy];

	NSURL* entries_url = components.URL;
	if (entries_url == nil) {
		NSError* parse_error = [NSError errorWithDomain:MBClientErrorDomain code:1007 userInfo:@{ NSLocalizedDescriptionKey: @"Entries endpoint URL was invalid." }];
		[self finishWithPagedEntries:nil error:parse_error completion:completion];
		return;
	}

	NSMutableURLRequest* entries_request = [NSMutableURLRequest requestWithURL:entries_url];
	entries_request.HTTPMethod = @"GET";
	[entries_request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
	[entries_request setValue:authorization_value forHTTPHeaderField:@"Authorization"];

	NSURLSessionDataTask* entries_task = [self trackedDataTaskWithRequest:entries_request completionHandler:^(NSData * _Nullable entries_data, NSURLResponse * _Nullable entries_response, NSError * _Nullable entries_error) {
		if (entries_error != nil) {
			[self finishWithPagedEntries:nil error:entries_error completion:completion];
			return;
		}

		NSHTTPURLResponse* entries_http_response = (NSHTTPURLResponse*) entries_response;
		if (entries_http_response.statusCode == 404 && page_number > 1) {
			NSArray* filtered_entries = [self filterEntries:accumulated_entries byCutoffDate:cutoff_date];
			[self finishWithPagedEntries:filtered_entries error:nil completion:completion];
			return;
		}

		if (entries_http_response.statusCode < 200 || entries_http_response.statusCode >= 300) {
			NSString* description = [self responseDescriptionForData:entries_data defaultMessage:@"Entries request failed."];
			NSError* request_error = [NSError errorWithDomain:MBClientErrorDomain code:entries_http_response.statusCode userInfo:@{ NSLocalizedDescriptionKey: description }];
			[self finishWithPagedEntries:nil error:request_error completion:completion];
			return;
		}

		id entries_payload = [NSJSONSerialization JSONObjectWithData:entries_data options:0 error:nil];
		if (![entries_payload isKindOfClass:[NSArray class]]) {
			NSError* parse_error = [NSError errorWithDomain:MBClientErrorDomain code:1007 userInfo:@{ NSLocalizedDescriptionKey: @"Entries response was invalid." }];
			[self finishWithPagedEntries:nil error:parse_error completion:completion];
			return;
		}

		NSArray* page_payload = (NSArray*) entries_payload;
		NSDate* oldest_entry_date = nil;
		NSInteger added_count = 0;
		for (id object in page_payload) {
			if (![object isKindOfClass:[NSDictionary class]]) {
				continue;
			}

			NSDictionary* entry_dictionary = (NSDictionary*) object;
			NSInteger entry_id_value = [self integerValueFromObject:entry_dictionary[@"id"]];
			BOOL should_add_entry = YES;
			if (entry_id_value > 0) {
				NSNumber* entry_id_number = @(entry_id_value);
				if ([seen_entry_ids containsObject:entry_id_number]) {
					should_add_entry = NO;
				}
				else {
					[seen_entry_ids addObject:entry_id_number];
				}
			}

			NSDate* entry_date = [self dateValueFromEntry:entry_dictionary];
			if (entry_date != nil) {
				if (oldest_entry_date == nil || [entry_date compare:oldest_entry_date] == NSOrderedAscending) {
					oldest_entry_date = entry_date;
				}
			}

			if (should_add_entry) {
				[accumulated_entries addObject:entry_dictionary];
				added_count += 1;
			}
		}

		BOOL did_reach_cutoff = NO;
		if (oldest_entry_date != nil && [oldest_entry_date compare:cutoff_date] == NSOrderedAscending) {
			did_reach_cutoff = YES;
		}

		BOOL should_continue = YES;
		if (page_payload.count == 0 || added_count == 0) {
			should_continue = NO;
		}
		if (did_reach_cutoff) {
			should_continue = NO;
		}
		if (page_payload.count < MBFeedEntriesPageSize) {
			should_continue = NO;
		}

		NSArray* filtered_entries = [self filterEntries:accumulated_entries byCutoffDate:cutoff_date];
		BOOL should_send_update = (page_number == 1 || added_count > 0);
		if (should_send_update) {
			[self finishWithPagedEntriesUpdate:filtered_entries update:update];
		}

		if (!should_continue) {
			[self finishWithPagedEntries:filtered_entries error:nil completion:completion];
			return;
		}

		[self fetchPagedFeedEntriesWithAuthorizationValue:authorization_value pageNumber:(page_number + 1) cutoffDate:cutoff_date accumulatedEntries:accumulated_entries seenEntryIDs:seen_entry_ids update:update completion:completion];
	}];
	[entries_task resume];
}

- (NSArray*) filterEntries:(NSArray*) entries byCutoffDate:(NSDate*) cutoff_date
{
	if (entries.count == 0 || cutoff_date == nil) {
		return [entries copy];
	}

	NSMutableArray* filtered_entries = [NSMutableArray array];
	for (id object in entries) {
		if (![object isKindOfClass:[NSDictionary class]]) {
			continue;
		}

		NSDictionary* entry_dictionary = (NSDictionary*) object;
		NSDate* entry_date = [self dateValueFromEntry:entry_dictionary];
		if (entry_date == nil || [entry_date compare:cutoff_date] != NSOrderedAscending) {
			[filtered_entries addObject:entry_dictionary];
		}
	}

	return [filtered_entries copy];
}

- (void) fetchFeedIconsWithToken:(NSString *)token completion:(void (^)(NSDictionary<NSString *,NSString *> * _Nullable icons_by_host, NSError * _Nullable error))completion
{
	if (token.length == 0) {
		NSError *error = [NSError errorWithDomain:MBClientErrorDomain code:1008 userInfo:@{ NSLocalizedDescriptionKey: @"Missing token for icons request." }];
		[self finishWithIconsByHost:nil error:error completion:completion];
		return;
	}

	NSMutableURLRequest *icons_request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:MBFeedIconsEndpoint]];
	icons_request.HTTPMethod = @"GET";
	[icons_request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

	NSString *authorization_value = [NSString stringWithFormat:@"Bearer %@", token];
	[icons_request setValue:authorization_value forHTTPHeaderField:@"Authorization"];

	NSURLSessionDataTask *task = [self trackedDataTaskWithRequest:icons_request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
		if (error != nil) {
			[self finishWithIconsByHost:nil error:error completion:completion];
			return;
		}

		NSHTTPURLResponse *http_response = (NSHTTPURLResponse *) response;
		if (http_response.statusCode < 200 || http_response.statusCode >= 300) {
			NSString *description = [self responseDescriptionForData:data defaultMessage:@"Icons request failed."];
			NSError *request_error = [NSError errorWithDomain:MBClientErrorDomain code:http_response.statusCode userInfo:@{ NSLocalizedDescriptionKey: description }];
			[self finishWithIconsByHost:nil error:request_error completion:completion];
			return;
		}

		id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
		if (![payload isKindOfClass:[NSArray class]]) {
			NSError *parse_error = [NSError errorWithDomain:MBClientErrorDomain code:1009 userInfo:@{ NSLocalizedDescriptionKey: @"Icons response was invalid." }];
			[self finishWithIconsByHost:nil error:parse_error completion:completion];
			return;
		}

		NSMutableDictionary<NSString *, NSString *> *icons_by_host = [NSMutableDictionary dictionary];
		for (id object in (NSArray *) payload) {
			if (![object isKindOfClass:[NSDictionary class]]) {
				continue;
			}

			NSDictionary<NSString *, id> *dictionary = (NSDictionary<NSString *, id> *) object;
			NSString *host_value = [self stringValueFromObject:dictionary[@"host"]];
			NSString *url_value = [self stringValueFromObject:dictionary[@"url"]];
			if (host_value.length == 0 || url_value.length == 0) {
				continue;
			}

			icons_by_host[host_value] = url_value;
		}

		[self finishWithIconsByHost:[icons_by_host copy] error:nil completion:completion];
	}];
	[task resume];
}

- (void) fetchRecentBookmarksWithToken:(NSString*) token completion:(void (^)(NSArray* _Nullable items, NSError* _Nullable error))completion
{
	if (token.length == 0) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1042 userInfo:@{ NSLocalizedDescriptionKey: @"Missing token for bookmarks request." }];
		[self finishWithBookmarks:nil error:error completion:completion];
		return;
	}

	NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:MBRecentBookmarksEndpoint]];
	request.HTTPMethod = @"GET";
	[request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

	NSString* authorization_value = [NSString stringWithFormat:@"Bearer %@", token];
	[request setValue:authorization_value forHTTPHeaderField:@"Authorization"];

	NSURLSessionDataTask* task = [self trackedDataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
		if (error != nil) {
			[self finishWithBookmarks:nil error:error completion:completion];
			return;
		}

		NSHTTPURLResponse* http_response = (NSHTTPURLResponse*) response;
		if (http_response.statusCode < 200 || http_response.statusCode >= 300) {
			NSString* description = [self responseDescriptionForData:data defaultMessage:@"Bookmarks request failed."];
			NSError* request_error = [NSError errorWithDomain:MBClientErrorDomain code:http_response.statusCode userInfo:@{ NSLocalizedDescriptionKey: description }];
			[self finishWithBookmarks:nil error:request_error completion:completion];
			return;
		}

		id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
		if (![payload isKindOfClass:[NSDictionary class]]) {
			NSError* parse_error = [NSError errorWithDomain:MBClientErrorDomain code:1043 userInfo:@{ NSLocalizedDescriptionKey: @"Bookmarks response was invalid." }];
			[self finishWithBookmarks:nil error:parse_error completion:completion];
			return;
		}

		id items_object = payload[@"items"];
		if (![items_object isKindOfClass:[NSArray class]]) {
			NSError* parse_error = [NSError errorWithDomain:MBClientErrorDomain code:1044 userInfo:@{ NSLocalizedDescriptionKey: @"Bookmarks response was invalid." }];
			[self finishWithBookmarks:nil error:parse_error completion:completion];
			return;
		}

		[self finishWithBookmarks:[items_object copy] error:nil completion:completion];
	}];
	[task resume];
}

- (void) fetchConversationForURLString:(NSString*) url_string completion:(void (^)(NSDictionary* _Nullable conversation_payload, NSError* _Nullable error))completion
{
	NSString* trimmed_url_string = [url_string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (trimmed_url_string.length == 0) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1026 userInfo:@{ NSLocalizedDescriptionKey: @"Missing URL for conversation request." }];
		[self finishWithConversationPayload:nil error:error completion:completion];
		return;
	}

	NSURLComponents* components = [NSURLComponents componentsWithString:(MBMicroBlogBaseURL @"/conversation.js")];
	if (components == nil) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1027 userInfo:@{ NSLocalizedDescriptionKey: @"Conversation endpoint URL was invalid." }];
		[self finishWithConversationPayload:nil error:error completion:completion];
		return;
	}

	components.queryItems = @[
		[NSURLQueryItem queryItemWithName:@"url" value:trimmed_url_string],
		[NSURLQueryItem queryItemWithName:@"format" value:@"jsonfeed"]
	];

	NSURL* conversation_url = components.URL;
	if (conversation_url == nil) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1027 userInfo:@{ NSLocalizedDescriptionKey: @"Conversation endpoint URL was invalid." }];
		[self finishWithConversationPayload:nil error:error completion:completion];
		return;
	}

	NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:conversation_url];
	request.HTTPMethod = @"GET";
	[request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

	NSURLSessionDataTask* task = [self.session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
		if (error != nil) {
			[self finishWithConversationPayload:nil error:error completion:completion];
			return;
		}

		NSHTTPURLResponse* http_response = (NSHTTPURLResponse*) response;
		if (http_response.statusCode < 200 || http_response.statusCode >= 300) {
			NSString* description = [self responseDescriptionForData:data defaultMessage:@"Conversation request failed."];
			NSError* request_error = [NSError errorWithDomain:MBClientErrorDomain code:http_response.statusCode userInfo:@{ NSLocalizedDescriptionKey: description }];
			[self finishWithConversationPayload:nil error:request_error completion:completion];
			return;
		}

		id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
		if (![payload isKindOfClass:[NSDictionary class]]) {
			NSError* parse_error = [NSError errorWithDomain:MBClientErrorDomain code:1028 userInfo:@{ NSLocalizedDescriptionKey: @"Conversation response was invalid." }];
			[self finishWithConversationPayload:nil error:parse_error completion:completion];
			return;
		}

		[self finishWithConversationPayload:(NSDictionary*) payload error:nil completion:completion];
	}];
	[task resume];
}

- (void) fetchReadingRecapForEntryIDs:(NSArray*) entry_ids token:(NSString*) token completion:(void (^)(NSInteger status_code, NSString* _Nullable html, NSError* _Nullable error))completion
{
	if (token.length == 0) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1015 userInfo:@{ NSLocalizedDescriptionKey: @"Missing token for recap request." }];
		[self finishWithRecapStatusCode:0 html:nil error:error completion:completion];
		return;
	}

	if (entry_ids.count == 0) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1016 userInfo:@{ NSLocalizedDescriptionKey: @"Missing entry IDs for recap request." }];
		[self finishWithRecapStatusCode:0 html:nil error:error completion:completion];
		return;
	}

	NSMutableArray* payload_entry_ids = [NSMutableArray array];
	for (id object in entry_ids) {
		NSInteger entry_id_value = [self integerValueFromObject:object];
		if (entry_id_value > 0) {
			[payload_entry_ids addObject:@(entry_id_value)];
		}
	}

	if (payload_entry_ids.count == 0) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1016 userInfo:@{ NSLocalizedDescriptionKey: @"Missing entry IDs for recap request." }];
		[self finishWithRecapStatusCode:0 html:nil error:error completion:completion];
		return;
	}

	NSURL* recap_url = [NSURL URLWithString:MBFeedsRecapEndpoint];
	if (recap_url == nil) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1017 userInfo:@{ NSLocalizedDescriptionKey: @"Recap endpoint URL was invalid." }];
		[self finishWithRecapStatusCode:0 html:nil error:error completion:completion];
		return;
	}

	NSData* body_data = [NSJSONSerialization dataWithJSONObject:payload_entry_ids options:0 error:nil];
	if (body_data.length == 0) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1018 userInfo:@{ NSLocalizedDescriptionKey: @"Recap request body was invalid." }];
		[self finishWithRecapStatusCode:0 html:nil error:error completion:completion];
		return;
	}

	NSMutableURLRequest* recap_request = [NSMutableURLRequest requestWithURL:recap_url];
	recap_request.HTTPMethod = @"POST";
	recap_request.HTTPBody = body_data;
	[recap_request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	[recap_request setValue:@"text/html" forHTTPHeaderField:@"Accept"];

	NSString* authorization_value = [NSString stringWithFormat:@"Bearer %@", token];
	[recap_request setValue:authorization_value forHTTPHeaderField:@"Authorization"];

	NSURLSessionDataTask* task = [self trackedDataTaskWithRequest:recap_request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
		if (error != nil) {
			[self finishWithRecapStatusCode:0 html:nil error:error completion:completion];
			return;
		}

		NSHTTPURLResponse* http_response = (NSHTTPURLResponse*) response;
		if (http_response.statusCode == 202) {
			[self finishWithRecapStatusCode:202 html:nil error:nil completion:completion];
			return;
		}

		if (http_response.statusCode == 200) {
			NSString* html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
			if (html.length == 0 && data.length > 0) {
				html = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
			}
			[self finishWithRecapStatusCode:200 html:(html ?: @"") error:nil completion:completion];
			return;
		}

		NSString* description = [self responseDescriptionForData:data defaultMessage:@"Recap request failed."];
		NSError* request_error = [NSError errorWithDomain:MBClientErrorDomain code:http_response.statusCode userInfo:@{ NSLocalizedDescriptionKey: description }];
		[self finishWithRecapStatusCode:http_response.statusCode html:nil error:request_error completion:completion];
	}];
	[task resume];
}

- (void) fetchReadingRecapEmailDayOfWeekWithToken:(NSString*) token completion:(void (^)(NSString* _Nullable day_of_week, NSError* _Nullable error))completion
{
	if (token.length == 0) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1045 userInfo:@{ NSLocalizedDescriptionKey: @"Missing token for recap email request." }];
		[self finishWithReadingRecapDayOfWeek:nil error:error completion:completion];
		return;
	}

	NSURL* request_url = [NSURL URLWithString:MBFeedsRecapEmailEndpoint];
	if (request_url == nil) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1046 userInfo:@{ NSLocalizedDescriptionKey: @"Recap email endpoint URL was invalid." }];
		[self finishWithReadingRecapDayOfWeek:nil error:error completion:completion];
		return;
	}

	NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:request_url];
	request.HTTPMethod = @"GET";
	[request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

	NSString* authorization_value = [NSString stringWithFormat:@"Bearer %@", token];
	[request setValue:authorization_value forHTTPHeaderField:@"Authorization"];

	NSURLSessionDataTask* task = [self trackedDataTaskWithRequest:request completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
		if (error != nil) {
			[self finishWithReadingRecapDayOfWeek:nil error:error completion:completion];
			return;
		}

		NSHTTPURLResponse* http_response = (NSHTTPURLResponse*) response;
		if (http_response.statusCode < 200 || http_response.statusCode >= 300) {
			NSString* description = [self responseDescriptionForData:data defaultMessage:@"Recap email request failed."];
			NSError* request_error = [NSError errorWithDomain:MBClientErrorDomain code:http_response.statusCode userInfo:@{ NSLocalizedDescriptionKey: description }];
			[self finishWithReadingRecapDayOfWeek:nil error:request_error completion:completion];
			return;
		}

		id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
		if (![payload isKindOfClass:[NSDictionary class]]) {
			NSError* parse_error = [NSError errorWithDomain:MBClientErrorDomain code:1047 userInfo:@{ NSLocalizedDescriptionKey: @"Recap email response was invalid." }];
			[self finishWithReadingRecapDayOfWeek:nil error:parse_error completion:completion];
			return;
		}

		NSString* day_of_week = [self stringValueFromObject:payload[@"dayofweek"]];
		[self finishWithReadingRecapDayOfWeek:day_of_week error:nil completion:completion];
	}];
	[task resume];
}

- (void) updateReadingRecapEmailDayOfWeek:(NSString*) day_of_week token:(NSString*) token completion:(void (^)(NSError* _Nullable error))completion
{
	if (token.length == 0) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1048 userInfo:@{ NSLocalizedDescriptionKey: @"Missing token for recap email update." }];
		[self finishWithSimpleError:error completion:completion];
		return;
	}

	NSURL* request_url = [NSURL URLWithString:MBFeedsRecapEmailEndpoint];
	if (request_url == nil) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1049 userInfo:@{ NSLocalizedDescriptionKey: @"Recap email endpoint URL was invalid." }];
		[self finishWithSimpleError:error completion:completion];
		return;
	}

	NSString* normalized_day_of_week = [day_of_week stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	NSString* body_string = [NSString stringWithFormat:@"dayofweek=%@", [self urlEncodedString:normalized_day_of_week]];

	NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:request_url];
	request.HTTPMethod = @"POST";
	request.HTTPBody = [body_string dataUsingEncoding:NSUTF8StringEncoding];
	[request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
	[request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

	NSString* authorization_value = [NSString stringWithFormat:@"Bearer %@", token];
	[request setValue:authorization_value forHTTPHeaderField:@"Authorization"];

	NSURLSessionDataTask* task = [self trackedDataTaskWithRequest:request completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
		if (error != nil) {
			[self finishWithSimpleError:error completion:completion];
			return;
		}

		NSHTTPURLResponse* http_response = (NSHTTPURLResponse*) response;
		if (http_response.statusCode < 200 || http_response.statusCode >= 300) {
			NSString* description = [self responseDescriptionForData:data defaultMessage:@"Recap email update failed."];
			NSError* request_error = [NSError errorWithDomain:MBClientErrorDomain code:http_response.statusCode userInfo:@{ NSLocalizedDescriptionKey: description }];
			[self finishWithSimpleError:request_error completion:completion];
			return;
		}

		[self finishWithSimpleError:nil completion:completion];
	}];
	[task resume];
}

- (void) beginManualNetworkingActivity
{
	[self beginNetworkingActivity];
}

- (void) endManualNetworkingActivity
{
	[self endNetworkingActivity];
}

- (void) fetchHighlightsForEntryID:(NSInteger)entry_id token:(NSString*) token completion:(void (^)(NSArray* _Nullable highlights, NSError* _Nullable error))completion
{
	if (entry_id <= 0) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1012 userInfo:@{ NSLocalizedDescriptionKey: @"Missing entry ID for highlights request." }];
		[self finishWithHighlights:nil error:error completion:completion];
		return;
	}

	if (token.length == 0) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1013 userInfo:@{ NSLocalizedDescriptionKey: @"Missing token for highlights request." }];
		[self finishWithHighlights:nil error:error completion:completion];
		return;
	}

	NSString* endpoint = [NSString stringWithFormat:@"%@/%ld/highlights", MBFeedsEndpointBase, (long) entry_id];
	NSMutableURLRequest* highlights_request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:endpoint]];
	highlights_request.HTTPMethod = @"GET";
	[highlights_request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

	NSString* authorization_value = [NSString stringWithFormat:@"Bearer %@", token];
	[highlights_request setValue:authorization_value forHTTPHeaderField:@"Authorization"];

	NSURLSessionDataTask* task = [self trackedDataTaskWithRequest:highlights_request completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
		if (error != nil) {
			[self finishWithHighlights:nil error:error completion:completion];
			return;
		}

		NSHTTPURLResponse* http_response = (NSHTTPURLResponse*) response;
		if (http_response.statusCode < 200 || http_response.statusCode >= 300) {
			NSString* description = [self responseDescriptionForData:data defaultMessage:@"Highlights request failed."];
			NSError* request_error = [NSError errorWithDomain:MBClientErrorDomain code:http_response.statusCode userInfo:@{ NSLocalizedDescriptionKey: description }];
			[self finishWithHighlights:nil error:request_error completion:completion];
			return;
		}

		id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
		if (![payload isKindOfClass:[NSDictionary class]]) {
			NSError* parse_error = [NSError errorWithDomain:MBClientErrorDomain code:1014 userInfo:@{ NSLocalizedDescriptionKey: @"Highlights response was invalid." }];
			[self finishWithHighlights:nil error:parse_error completion:completion];
			return;
		}

		NSArray* highlights = [self highlightsFromFeedPayload:(NSDictionary*) payload defaultEntryID:entry_id];
		[self finishWithHighlights:highlights error:nil completion:completion];
	}];
	[task resume];
}

- (void) fetchAllHighlightsWithToken:(NSString*) token completion:(void (^)(NSArray* _Nullable highlights, NSError* _Nullable error))completion
{
	if (token.length == 0) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1019 userInfo:@{ NSLocalizedDescriptionKey: @"Missing token for all highlights request." }];
		[self finishWithHighlights:nil error:error completion:completion];
		return;
	}

	NSMutableURLRequest* highlights_request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:MBFeedHighlightsEndpoint]];
	highlights_request.HTTPMethod = @"GET";
	[highlights_request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

	NSString* authorization_value = [NSString stringWithFormat:@"Bearer %@", token];
	[highlights_request setValue:authorization_value forHTTPHeaderField:@"Authorization"];

	NSURLSessionDataTask* task = [self trackedDataTaskWithRequest:highlights_request completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
		if (error != nil) {
			[self finishWithHighlights:nil error:error completion:completion];
			return;
		}

		NSHTTPURLResponse* http_response = (NSHTTPURLResponse*) response;
		if (http_response.statusCode < 200 || http_response.statusCode >= 300) {
			NSString* description = [self responseDescriptionForData:data defaultMessage:@"All highlights request failed."];
			NSError* request_error = [NSError errorWithDomain:MBClientErrorDomain code:http_response.statusCode userInfo:@{ NSLocalizedDescriptionKey: description }];
			[self finishWithHighlights:nil error:request_error completion:completion];
			return;
		}

		id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
		if (![payload isKindOfClass:[NSDictionary class]]) {
			NSError* parse_error = [NSError errorWithDomain:MBClientErrorDomain code:1020 userInfo:@{ NSLocalizedDescriptionKey: @"All highlights response was invalid." }];
			[self finishWithHighlights:nil error:parse_error completion:completion];
			return;
		}

		NSArray* highlights = [self highlightsFromFeedPayload:(NSDictionary*) payload defaultEntryID:0];
		[self finishWithHighlights:highlights error:nil completion:completion];
	}];
	[task resume];
}

- (void) createHighlightForEntryID:(NSInteger)entry_id selectionText:(NSString*) selection_text selectionStart:(NSInteger) selection_start selectionEnd:(NSInteger) selection_end token:(NSString*) token completion:(void (^)(NSString* _Nullable highlight_id, NSError* _Nullable error))completion
{
	if (entry_id <= 0) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1021 userInfo:@{ NSLocalizedDescriptionKey: @"Missing entry ID for create highlight request." }];
		[self finishWithHighlightID:nil error:error completion:completion];
		return;
	}

	NSString* trimmed_selection_text = [selection_text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (trimmed_selection_text.length == 0) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1022 userInfo:@{ NSLocalizedDescriptionKey: @"Missing text for create highlight request." }];
		[self finishWithHighlightID:nil error:error completion:completion];
		return;
	}

	if (token.length == 0) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1023 userInfo:@{ NSLocalizedDescriptionKey: @"Missing token for create highlight request." }];
		[self finishWithHighlightID:nil error:error completion:completion];
		return;
	}

	NSString* endpoint = [NSString stringWithFormat:@"%@/%ld/highlights", MBFeedsEndpointBase, (long) entry_id];
	NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:endpoint]];
	request.HTTPMethod = @"POST";
	[request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
	[request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

	NSString* authorization_value = [NSString stringWithFormat:@"Bearer %@", token];
	[request setValue:authorization_value forHTTPHeaderField:@"Authorization"];

	NSMutableArray* body_parts = [NSMutableArray array];
	NSString* encoded_text = [self urlEncodedString:trimmed_selection_text];
	[body_parts addObject:[NSString stringWithFormat:@"text=%@", encoded_text]];
	[body_parts addObject:[NSString stringWithFormat:@"start=%ld", (long) selection_start]];
	[body_parts addObject:[NSString stringWithFormat:@"end=%ld", (long) selection_end]];
	NSString* body_string = [body_parts componentsJoinedByString:@"&"] ?: @"";
	request.HTTPBody = [body_string dataUsingEncoding:NSUTF8StringEncoding];

	NSURLSessionDataTask* task = [self trackedDataTaskWithRequest:request completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
		if (error != nil) {
			[self finishWithHighlightID:nil error:error completion:completion];
			return;
		}

		NSHTTPURLResponse* http_response = (NSHTTPURLResponse*) response;
		if (http_response.statusCode < 200 || http_response.statusCode >= 300) {
			NSString* description = [self responseDescriptionForData:data defaultMessage:@"Create highlight request failed."];
			NSError* request_error = [NSError errorWithDomain:MBClientErrorDomain code:http_response.statusCode userInfo:@{ NSLocalizedDescriptionKey: description }];
			[self finishWithHighlightID:nil error:request_error completion:completion];
			return;
		}

		NSString* returned_highlight_id = @"";
		id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
		if ([payload isKindOfClass:[NSDictionary class]]) {
			NSDictionary* dictionary = (NSDictionary*) payload;
			returned_highlight_id = [self stringValueFromObjectOrNumber:dictionary[@"id"]];
		}

		[self finishWithHighlightID:returned_highlight_id error:nil completion:completion];
	}];
	[task resume];
}

- (void) deleteHighlight:(MBHighlight*) highlight token:(NSString*) token completion:(void (^)(NSError* _Nullable error))completion
{
	if (![highlight isKindOfClass:[MBHighlight class]] || highlight.entryID <= 0) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1030 userInfo:@{ NSLocalizedDescriptionKey: @"Missing highlight for delete request." }];
		[self finishWithSimpleError:error completion:completion];
		return;
	}

	NSString* highlight_id = [self normalizedRemoteHighlightIDForHighlight:highlight];
	if (highlight_id.length == 0) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1031 userInfo:@{ NSLocalizedDescriptionKey: @"This highlight has not been synced yet, so it can't be deleted from the server." }];
		[self finishWithSimpleError:error completion:completion];
		return;
	}

	if (token.length == 0) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1032 userInfo:@{ NSLocalizedDescriptionKey: @"Missing token for delete highlight request." }];
		[self finishWithSimpleError:error completion:completion];
		return;
	}

	NSString* encoded_highlight_id = [self urlEncodedString:highlight_id];
	NSString* endpoint = [NSString stringWithFormat:@"%@/%ld/highlights/%@", MBFeedsEndpointBase, (long) highlight.entryID, encoded_highlight_id];
	NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:endpoint]];
	request.HTTPMethod = @"DELETE";
	[request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

	NSString* authorization_value = [NSString stringWithFormat:@"Bearer %@", token];
	[request setValue:authorization_value forHTTPHeaderField:@"Authorization"];

	NSURLSessionDataTask* task = [self trackedDataTaskWithRequest:request completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
		if (error != nil) {
			[self finishWithSimpleError:error completion:completion];
			return;
		}

		NSHTTPURLResponse* http_response = (NSHTTPURLResponse*) response;
		if (http_response.statusCode < 200 || http_response.statusCode >= 300) {
			NSString* description = [self responseDescriptionForData:data defaultMessage:@"Delete highlight request failed."];
			NSError* request_error = [NSError errorWithDomain:MBClientErrorDomain code:http_response.statusCode userInfo:@{ NSLocalizedDescriptionKey: description }];
			[self finishWithSimpleError:request_error completion:completion];
			return;
		}

		[self removeHighlightFromCache:highlight];
		[self finishWithSimpleError:nil completion:completion];
	}];
	[task resume];
}

- (void) deleteFeedSubscription:(MBSubscription*) subscription token:(NSString*) token completion:(void (^)(NSError* _Nullable error))completion
{
	if (![subscription isKindOfClass:[MBSubscription class]] || subscription.subscriptionID <= 0) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1034 userInfo:@{ NSLocalizedDescriptionKey: @"Missing subscription for delete request." }];
		[self finishWithSimpleError:error completion:completion];
		return;
	}

	if (token.length == 0) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1035 userInfo:@{ NSLocalizedDescriptionKey: @"Missing token for delete subscription request." }];
		[self finishWithSimpleError:error completion:completion];
		return;
	}

	NSString* endpoint = [NSString stringWithFormat:@"%@/%ld.json", MBFeedSubscriptionsEndpointBase, (long) subscription.subscriptionID];
	NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:endpoint]];
	request.HTTPMethod = @"DELETE";
	[request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

	NSString* authorization_value = [NSString stringWithFormat:@"Bearer %@", token];
	[request setValue:authorization_value forHTTPHeaderField:@"Authorization"];

	NSURLSessionDataTask* task = [self trackedDataTaskWithRequest:request completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
		if (error != nil) {
			[self finishWithSimpleError:error completion:completion];
			return;
		}

		NSHTTPURLResponse* http_response = (NSHTTPURLResponse*) response;
		if (http_response.statusCode < 200 || http_response.statusCode >= 300) {
			NSString* description = [self responseDescriptionForData:data defaultMessage:@"Delete subscription request failed."];
			NSError* request_error = [NSError errorWithDomain:MBClientErrorDomain code:http_response.statusCode userInfo:@{ NSLocalizedDescriptionKey: description }];
			[self finishWithSimpleError:request_error completion:completion];
			return;
		}

		[self finishWithSimpleError:nil completion:completion];
	}];
	[task resume];
}

- (NSArray*) cachedHighlightsForEntryID:(NSInteger) entry_id
{
	if (entry_id <= 0) {
		return @[];
	}

	@synchronized (self) {
		NSMutableArray* filtered_highlights = [NSMutableArray array];
		for (id object in self.cachedHighlights ?: @[]) {
			if (![object isKindOfClass:[MBHighlight class]]) {
				continue;
			}

			MBHighlight* highlight = (MBHighlight*) object;
			if (highlight.entryID != entry_id) {
				continue;
			}

			[filtered_highlights addObject:[self highlightCopy:highlight]];
		}

		NSArray* sorted_highlights = [self sortedHighlightsFromHighlights:filtered_highlights];
		return sorted_highlights ?: @[];
	}
}

- (NSArray*) cachedAllHighlights
{
	@synchronized (self) {
		NSMutableArray* copied_highlights = [NSMutableArray array];
		for (id object in self.cachedHighlights ?: @[]) {
			if (![object isKindOfClass:[MBHighlight class]]) {
				continue;
			}

			[copied_highlights addObject:[self highlightCopy:(MBHighlight*) object]];
		}

		NSArray* sorted_highlights = [self sortedHighlightsFromHighlights:copied_highlights];
		return sorted_highlights ?: @[];
	}
}

- (void) mergeRemoteHighlightsIntoCache:(NSArray*) highlights
{
	if (![highlights isKindOfClass:[NSArray class]] || highlights.count == 0) {
		return;
	}

	@synchronized (self) {
		NSMutableArray* merged_highlights = [NSMutableArray arrayWithArray:self.cachedHighlights ?: @[]];
		for (id object in highlights) {
			if (![object isKindOfClass:[MBHighlight class]]) {
				continue;
			}

			MBHighlight* incoming_highlight = (MBHighlight*) object;
			NSInteger index = [self indexOfMatchingHighlight:incoming_highlight inCollection:merged_highlights];
			if (index < 0) {
				[merged_highlights addObject:[self highlightCopy:incoming_highlight]];
				continue;
			}

			MBHighlight* existing_highlight = merged_highlights[index];
			merged_highlights[index] = [self mergedHighlightFromExisting:existing_highlight incoming:incoming_highlight];
		}

		NSArray* normalized_highlights = [self normalizedHighlightsFromHighlights:merged_highlights];
		self.cachedHighlights = normalized_highlights ?: @[];
		[self cacheHighlights:self.cachedHighlights];
	}
}

- (MBHighlight*) saveLocalHighlightForEntryID:(NSInteger) entry_id postTitle:(NSString*) post_title postURL:(NSString*) post_url selectionText:(NSString*) selection_text selectionStart:(NSInteger) selection_start selectionEnd:(NSInteger) selection_end
{
	if (entry_id <= 0) {
		return nil;
	}

	NSString* trimmed_selection_text = [selection_text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	NSString* trimmed_post_title = [post_title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	NSString* trimmed_post_url = [post_url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (trimmed_selection_text.length == 0) {
		return nil;
	}

	MBHighlight* local_highlight = [[MBHighlight alloc] init];
	local_highlight.entryID = entry_id;
	local_highlight.localID = [self generatedLocalHighlightID];
	local_highlight.highlightID = @"";
	local_highlight.selectionText = trimmed_selection_text;
	local_highlight.postTitle = trimmed_post_title;
	local_highlight.postURL = trimmed_post_url;
	local_highlight.selectionStart = MAX(0, selection_start);
	local_highlight.selectionEnd = MAX(local_highlight.selectionStart + 1, selection_end);
	local_highlight.updatedDate = [NSDate date];

	@synchronized (self) {
		NSMutableArray* merged_highlights = [NSMutableArray arrayWithArray:self.cachedHighlights ?: @[]];
		[merged_highlights addObject:local_highlight];
		NSArray* normalized_highlights = [self normalizedHighlightsFromHighlights:merged_highlights];
		self.cachedHighlights = normalized_highlights ?: @[];
		[self cacheHighlights:self.cachedHighlights];
	}

	return [self highlightCopy:local_highlight];
}

- (void) assignRemoteHighlightID:(NSString*) highlight_id toLocalHighlightID:(NSString*) local_id entryID:(NSInteger) entry_id
{
	NSString* trimmed_highlight_id = [highlight_id stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	NSString* trimmed_local_id = [local_id stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (trimmed_highlight_id.length == 0 || trimmed_local_id.length == 0 || entry_id <= 0) {
		return;
	}

	@synchronized (self) {
		NSMutableArray* updated_highlights = [NSMutableArray arrayWithArray:self.cachedHighlights ?: @[]];
		for (NSInteger i = 0; i < updated_highlights.count; i++) {
			id object = updated_highlights[i];
			if (![object isKindOfClass:[MBHighlight class]]) {
				continue;
			}

			MBHighlight* highlight = (MBHighlight*) object;
			if (highlight.entryID != entry_id) {
				continue;
			}
			NSString* highlight_local_id = highlight.localID ?: @"";
			if (![highlight_local_id isEqualToString:trimmed_local_id]) {
				continue;
			}

			MBHighlight* updated_highlight = [self highlightCopy:highlight];
			updated_highlight.highlightID = trimmed_highlight_id;
			updated_highlight.updatedDate = [NSDate date];
			if (updated_highlight.localID.length == 0) {
				updated_highlight.localID = trimmed_highlight_id;
			}
			updated_highlights[i] = updated_highlight;
			break;
		}

		NSArray* normalized_highlights = [self normalizedHighlightsFromHighlights:updated_highlights];
		self.cachedHighlights = normalized_highlights ?: @[];
		[self cacheHighlights:self.cachedHighlights];
	}
}

- (void) removeHighlightFromCache:(MBHighlight*) highlight
{
	if (![highlight isKindOfClass:[MBHighlight class]]) {
		return;
	}

	@synchronized (self) {
		NSMutableArray* updated_highlights = [NSMutableArray arrayWithArray:self.cachedHighlights ?: @[]];
		for (NSInteger i = ((NSInteger) updated_highlights.count - 1); i >= 0; i--) {
			id object = updated_highlights[i];
			if (![object isKindOfClass:[MBHighlight class]]) {
				continue;
			}

			MBHighlight* cached_highlight = (MBHighlight*) object;
			if (![self isSameStoredHighlight:cached_highlight other:highlight]) {
				continue;
			}

			[updated_highlights removeObjectAtIndex:i];
		}

		NSArray* normalized_highlights = [self normalizedHighlightsFromHighlights:updated_highlights];
		self.cachedHighlights = normalized_highlights ?: @[];
		[self cacheHighlights:self.cachedHighlights];
	}
}

- (void) markAsRead:(NSInteger)entry_id token:(NSString*) token completion:(void (^)(NSError * _Nullable error))completion
{
	[self updateUnreadStateForEntryIDs:@[ @(entry_id) ] token:token should_mark_unread:NO completion:completion];
}

- (void) markEntriesAsRead:(NSArray*) entry_ids token:(NSString*) token completion:(void (^)(NSError * _Nullable error))completion
{
	[self updateUnreadStateForEntryIDs:entry_ids token:token should_mark_unread:NO completion:completion];
}

- (void) markAsUnread:(NSInteger)entry_id token:(NSString*) token completion:(void (^)(NSError * _Nullable error))completion
{
	[self updateUnreadStateForEntryIDs:@[ @(entry_id) ] token:token should_mark_unread:YES completion:completion];
}

- (void) bookmarkEntry:(NSInteger)entry_id token:(NSString*) token completion:(void (^)(NSError * _Nullable error))completion
{
	[self updateBookmarkedStateForEntryID:entry_id token:token should_unbookmark:NO completion:completion];
}

- (void) unbookmarkEntry:(NSInteger)entry_id token:(NSString*) token completion:(void (^)(NSError * _Nullable error))completion
{
	[self updateBookmarkedStateForEntryID:entry_id token:token should_unbookmark:YES completion:completion];
}

- (void) updateUnreadStateForEntryIDs:(NSArray*) entry_ids token:(NSString*) token should_mark_unread:(BOOL)should_mark_unread completion:(void (^)(NSError * _Nullable error))completion
{
	NSMutableArray* normalized_entry_ids = [NSMutableArray array];
	for (NSNumber* entry_id_value in entry_ids) {
		NSInteger entry_id = [entry_id_value integerValue];
		if (entry_id > 0) {
			[normalized_entry_ids addObject:@(entry_id)];
		}
	}

	if (normalized_entry_ids.count == 0) {
		NSError *error = [NSError errorWithDomain:MBClientErrorDomain code:1010 userInfo:@{ NSLocalizedDescriptionKey: @"Missing entry ID for read state update." }];
		[self finishWithSimpleError:error completion:completion];
		return;
	}

	if (token.length == 0) {
		NSError *error = [NSError errorWithDomain:MBClientErrorDomain code:1011 userInfo:@{ NSLocalizedDescriptionKey: @"Missing token for read state update." }];
		[self finishWithSimpleError:error completion:completion];
		return;
	}

	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:MBFeedUnreadEntriesEndpoint]];
	if (should_mark_unread) {
		request.HTTPMethod = @"POST";
	}
	else {
		request.HTTPMethod = @"DELETE";
	}
	[request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
	[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

	NSString *authorization_value = [NSString stringWithFormat:@"Bearer %@", token];
	[request setValue:authorization_value forHTTPHeaderField:@"Authorization"];

	NSDictionary *payload = @{ @"unread_entries": [normalized_entry_ids copy] };
	NSData *body_data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
	request.HTTPBody = body_data;

	NSURLSessionDataTask *task = [self trackedDataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
		if (error != nil) {
			[self finishWithSimpleError:error completion:completion];
			return;
		}

		NSHTTPURLResponse *http_response = (NSHTTPURLResponse *) response;
		if (http_response.statusCode < 200 || http_response.statusCode >= 300) {
			NSString *default_message = should_mark_unread ? @"Mark unread request failed." : @"Mark read request failed.";
			NSString *description = [self responseDescriptionForData:data defaultMessage:default_message];
			NSError *request_error = [NSError errorWithDomain:MBClientErrorDomain code:http_response.statusCode userInfo:@{ NSLocalizedDescriptionKey: description }];
			[self finishWithSimpleError:request_error completion:completion];
			return;
		}

		NSMutableSet* updated_unread_entry_ids = [NSMutableSet setWithSet:(self.cachedUnreadEntryIDs ?: [NSSet set])];
		if (should_mark_unread) {
			[updated_unread_entry_ids addObjectsFromArray:normalized_entry_ids];
		}
		else {
			[updated_unread_entry_ids minusSet:[NSSet setWithArray:normalized_entry_ids]];
		}
		self.cachedUnreadEntryIDs = [updated_unread_entry_ids copy];
		[self cacheUnreadEntryIDs:self.cachedUnreadEntryIDs];

		[self finishWithSimpleError:nil completion:completion];
	}];
	[task resume];
}

- (void) updateBookmarkedStateForEntryID:(NSInteger)entry_id token:(NSString*) token should_unbookmark:(BOOL)should_unbookmark completion:(void (^)(NSError * _Nullable error))completion
{
	if (entry_id <= 0) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1012 userInfo:@{ NSLocalizedDescriptionKey: @"Missing entry ID for bookmark update." }];
		[self finishWithSimpleError:error completion:completion];
		return;
	}

	if (token.length == 0) {
		NSError* error = [NSError errorWithDomain:MBClientErrorDomain code:1013 userInfo:@{ NSLocalizedDescriptionKey: @"Missing token for bookmark update." }];
		[self finishWithSimpleError:error completion:completion];
		return;
	}

	NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:MBFeedStarredEntriesEndpoint]];
	request.HTTPMethod = should_unbookmark ? @"DELETE" : @"POST";
	[request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
	[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

	NSString* authorization_value = [NSString stringWithFormat:@"Bearer %@", token];
	[request setValue:authorization_value forHTTPHeaderField:@"Authorization"];

	NSDictionary* payload = @{ @"starred_entries": @[ @(entry_id) ] };
	NSData* body_data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
	request.HTTPBody = body_data;

	NSURLSessionDataTask* task = [self trackedDataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
		if (error != nil) {
			[self finishWithSimpleError:error completion:completion];
			return;
		}

		NSHTTPURLResponse* http_response = (NSHTTPURLResponse*) response;
		if (http_response.statusCode < 200 || http_response.statusCode >= 300) {
			NSString* default_message = should_unbookmark ? @"Unbookmark request failed." : @"Bookmark request failed.";
			NSString* description = [self responseDescriptionForData:data defaultMessage:default_message];
			NSError* request_error = [NSError errorWithDomain:MBClientErrorDomain code:http_response.statusCode userInfo:@{ NSLocalizedDescriptionKey: description }];
			[self finishWithSimpleError:request_error completion:completion];
			return;
		}

		[self finishWithSimpleError:nil completion:completion];
	}];
	[task resume];
}

- (NSArray<MBSubscription *> *) subscriptionsFromPayload:(NSArray *)payload
{
	NSMutableArray<MBSubscription *> *subscriptions = [NSMutableArray array];

	for (id object in payload) {
		if (![object isKindOfClass:[NSDictionary class]]) {
			continue;
		}

		MBSubscription* subscription = [self subscriptionFromDictionary:(NSDictionary*) object];
		if (subscription == nil) {
			continue;
		}

		[subscriptions addObject:subscription];
	}

	return [subscriptions copy];
}

- (MBSubscription* _Nullable) subscriptionFromDictionary:(NSDictionary*) dictionary
{
	if (![dictionary isKindOfClass:[NSDictionary class]]) {
		return nil;
	}

	MBSubscription* subscription = [[MBSubscription alloc] init];
	subscription.subscriptionID = [self integerValueFromObject:dictionary[@"id"]];
	subscription.feedID = [self integerValueFromObject:dictionary[@"feed_id"]];
	subscription.title = [self stringValueFromObject:dictionary[@"title"]];
	subscription.feedURL = [self stringValueFromObject:dictionary[@"feed_url"]];
	subscription.siteURL = [self stringValueFromObject:dictionary[@"site_url"]];
	subscription.avatarURL = [self avatarURLFromSubscriptionDictionary:dictionary];

	NSString* created_at_string = [self stringValueFromObject:dictionary[@"created_at"]];
	subscription.createdAt = [self dateFromISO8601String:created_at_string];
	return subscription;
}

- (NSArray* _Nullable) subscriptionsFromData:(NSData* _Nullable) data response:(NSURLResponse* _Nullable) response error:(NSError* _Nullable) error
{
	if (error != nil) {
		return nil;
	}

	NSHTTPURLResponse* http_response = (NSHTTPURLResponse*) response;
	if (http_response.statusCode < 200 || http_response.statusCode >= 300) {
		return nil;
	}

	id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
	if (![payload isKindOfClass:[NSArray class]]) {
		return nil;
	}

	return [self subscriptionsFromPayload:(NSArray*) payload];
}

- (NSError* _Nullable) subscriptionsErrorFromData:(NSData* _Nullable) data response:(NSURLResponse* _Nullable) response error:(NSError* _Nullable) error
{
	if (error != nil) {
		return error;
	}

	NSHTTPURLResponse* http_response = (NSHTTPURLResponse*) response;
	if (http_response.statusCode < 200 || http_response.statusCode >= 300) {
		NSString* description = [self responseDescriptionForData:data defaultMessage:@"Subscriptions request failed."];
		return [NSError errorWithDomain:MBClientErrorDomain code:http_response.statusCode userInfo:@{ NSLocalizedDescriptionKey: description }];
	}

	return [NSError errorWithDomain:MBClientErrorDomain code:1006 userInfo:@{ NSLocalizedDescriptionKey: @"Subscriptions response was invalid." }];
}

- (NSArray*) subscriptionChoicesFromPayload:(NSArray*) payload
{
	NSMutableArray* choices = [NSMutableArray array];

	for (id object in payload) {
		if (![object isKindOfClass:[NSDictionary class]]) {
			continue;
		}

		NSDictionary* dictionary = (NSDictionary*) object;
		NSString* title_value = [self stringValueFromObject:dictionary[@"title"]];
		NSString* feed_url_value = [self stringValueFromObject:dictionary[@"feed_url"]];
		if (feed_url_value.length == 0) {
			feed_url_value = [self stringValueFromObject:dictionary[@"url"]];
		}
		if (feed_url_value.length == 0) {
			continue;
		}

		NSDictionary* choice = @{
			@"title": title_value ?: @"",
			@"feed_url": feed_url_value,
			@"is_json_feed": @([self isJSONFeedDictionary:dictionary])
		};
		[choices addObject:choice];
	}

	return [choices copy];
}

- (BOOL) isJSONFeedDictionary:(NSDictionary*) dictionary
{
	if (![dictionary isKindOfClass:[NSDictionary class]]) {
		return NO;
	}

	id json_feed_value = dictionary[@"json_feed"];
	if ([json_feed_value isKindOfClass:[NSDictionary class]]) {
		return YES;
	}

	NSArray* type_keys = @[ @"feed_type", @"type", @"format", @"mime_type", @"content_type", @"version" ];
	for (NSString* key in type_keys) {
		NSString* value = [[self stringValueFromObject:dictionary[key]] lowercaseString];
		if ([value containsString:@"json"]) {
			return YES;
		}
	}

	NSString* feed_url_value = [[self stringValueFromObject:dictionary[@"feed_url"]] lowercaseString];
	if (feed_url_value.length == 0) {
		feed_url_value = [[self stringValueFromObject:dictionary[@"url"]] lowercaseString];
	}

	if ([feed_url_value containsString:@"jsonfeed"]) {
		return YES;
	}

	NSURLComponents* components = [NSURLComponents componentsWithString:feed_url_value];
	NSString* path_value = [components.path lowercaseString] ?: @"";
	NSString* extension_value = [path_value pathExtension] ?: @"";
	if ([extension_value isEqualToString:@"json"]) {
		return YES;
	}

	return NO;
}

- (NSString*) avatarURLFromSubscriptionDictionary:(NSDictionary*) dictionary
{
	NSString* avatar_url = [self stringValueFromObject:dictionary[@"avatar"]];
	if (avatar_url.length > 0) {
		return avatar_url;
	}

	avatar_url = [self stringValueFromObject:dictionary[@"avatar_url"]];
	if (avatar_url.length > 0) {
		return avatar_url;
	}

	avatar_url = [self stringValueFromObject:dictionary[@"icon"]];
	if (avatar_url.length > 0) {
		return avatar_url;
	}

	avatar_url = [self stringValueFromObject:dictionary[@"favicon"]];
	if (avatar_url.length > 0) {
		return avatar_url;
	}

	NSDictionary* json_feed = dictionary[@"json_feed"];
	if (![json_feed isKindOfClass:[NSDictionary class]]) {
		return @"";
	}

	avatar_url = [self stringValueFromObject:json_feed[@"icon"]];
	if (avatar_url.length > 0) {
		return avatar_url;
	}

	return [self stringValueFromObject:json_feed[@"favicon"]];
}

- (NSSet *) unreadEntryIDsFromPayload:(NSArray *)payload
{
	NSMutableSet *unread_entry_ids = [NSMutableSet set];

	for (id object in payload) {
		NSInteger entry_id_value = [self integerValueFromObject:object];
		if (entry_id_value > 0) {
			[unread_entry_ids addObject:@(entry_id_value)];
		}
	}

	return [unread_entry_ids copy];
}

- (NSURL * _Nullable) applicationSupportDirectoryURL
{
	NSFileManager* file_manager = [NSFileManager defaultManager];
	NSArray* application_support_urls = [file_manager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask];
	NSURL* application_support_url = [application_support_urls firstObject];
	if (application_support_url == nil) {
		return nil;
	}

	NSString* bundle_identifier = [[NSBundle mainBundle] bundleIdentifier];
	if (bundle_identifier.length == 0) {
		bundle_identifier = @"Inkwell";
	}

	NSURL* directory_url = [application_support_url URLByAppendingPathComponent:bundle_identifier isDirectory:YES];
	NSError* directory_error = nil;
	BOOL is_directory_ready = [file_manager createDirectoryAtURL:directory_url withIntermediateDirectories:YES attributes:nil error:&directory_error];
	if (!is_directory_ready) {
		return nil;
	}

	return directory_url;
}

- (NSURL * _Nullable) unreadEntryIDsCacheURL
{
	NSURL* directory_url = [self applicationSupportDirectoryURL];
	if (directory_url == nil) {
		return nil;
	}

	return [directory_url URLByAppendingPathComponent:MBUnreadEntryIDsCacheFilename isDirectory:NO];
}

- (NSURL * _Nullable) highlightsCacheURL
{
	NSURL* directory_url = [self applicationSupportDirectoryURL];
	if (directory_url == nil) {
		return nil;
	}

	return [directory_url URLByAppendingPathComponent:MBHighlightsCacheFilename isDirectory:NO];
}

- (NSSet*) loadCachedUnreadEntryIDs
{
	NSURL* cache_url = [self unreadEntryIDsCacheURL];
	if (cache_url == nil) {
		return [NSSet set];
	}

	NSData* data = [NSData dataWithContentsOfURL:cache_url options:0 error:nil];
	if (data.length == 0) {
		return [NSSet set];
	}

	id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
	if (![payload isKindOfClass:[NSArray class]]) {
		return [NSSet set];
	}

	return [self unreadEntryIDsFromPayload:(NSArray *) payload];
}

- (void) cacheUnreadEntryIDs:(NSSet*) unread_entry_ids
{
	NSURL* cache_url = [self unreadEntryIDsCacheURL];
	if (cache_url == nil) {
		return;
	}

	NSArray* sorted_entry_ids = [[unread_entry_ids allObjects] sortedArrayUsingSelector:@selector(compare:)];
	NSData* data = [NSJSONSerialization dataWithJSONObject:sorted_entry_ids options:0 error:nil];
	if (data.length == 0) {
		return;
	}

	[data writeToURL:cache_url atomically:YES];
}

- (NSArray*) loadCachedHighlights
{
	NSURL* cache_url = [self highlightsCacheURL];
	if (cache_url == nil) {
		return @[];
	}

	NSData* data = [NSData dataWithContentsOfURL:cache_url options:0 error:nil];
	if (data.length == 0) {
		return @[];
	}

	id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
	NSArray* items = nil;
	if ([payload isKindOfClass:[NSDictionary class]]) {
		items = [(NSDictionary*) payload objectForKey:@"items"];
	}
	else if ([payload isKindOfClass:[NSArray class]]) {
		items = (NSArray*) payload;
	}

	if (![items isKindOfClass:[NSArray class]]) {
		return @[];
	}

	NSMutableArray* highlights = [NSMutableArray array];
	for (id object in items) {
		if (![object isKindOfClass:[NSDictionary class]]) {
			continue;
		}

		MBHighlight* highlight = [self highlightFromDictionary:(NSDictionary*) object];
		if (highlight == nil) {
			continue;
		}

		[highlights addObject:highlight];
	}

	NSArray* normalized_highlights = [self normalizedHighlightsFromHighlights:highlights];
	return normalized_highlights ?: @[];
}

- (void) cacheHighlights:(NSArray*) highlights
{
	NSURL* cache_url = [self highlightsCacheURL];
	if (cache_url == nil) {
		return;
	}

	NSMutableArray* serialized_highlights = [NSMutableArray array];
	for (id object in highlights ?: @[]) {
		if (![object isKindOfClass:[MBHighlight class]]) {
			continue;
		}

		MBHighlight* highlight = (MBHighlight*) object;
		NSDictionary* dictionary = [self dictionaryFromHighlight:highlight];
		if (dictionary.count == 0) {
			continue;
		}

		[serialized_highlights addObject:dictionary];
	}

	NSDictionary* payload = @{
		@"version": @2,
		@"items": serialized_highlights
	};
	NSData* data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
	if (data.length == 0) {
		return;
	}

	[data writeToURL:cache_url atomically:YES];
}

- (MBHighlight*) highlightFromDictionary:(NSDictionary*) dictionary
{
	if (![dictionary isKindOfClass:[NSDictionary class]]) {
		return nil;
	}

	NSInteger entry_id = [self integerValueFromObject:dictionary[@"entry_id"]];
	if (entry_id <= 0) {
		entry_id = [self integerValueFromObject:dictionary[@"post_id"]];
	}
	if (entry_id <= 0) {
		return nil;
	}

	MBHighlight* highlight = [[MBHighlight alloc] init];
	highlight.entryID = entry_id;
	highlight.localID = [self stringValueFromObjectOrNumber:dictionary[@"id"]];
	highlight.highlightID = [self stringValueFromObjectOrNumber:dictionary[@"highlight_id"]];
	if (highlight.highlightID.length == 0 && highlight.localID.length > 0 && ![highlight.localID hasPrefix:@"hl-"]) {
		highlight.highlightID = highlight.localID;
	}

	NSString* selection_text = [self stringValueFromObject:dictionary[@"selection_text"]];
	if (selection_text.length == 0) {
		selection_text = [self stringValueFromObject:dictionary[@"content_text"]];
	}
	if (selection_text.length == 0) {
		selection_text = [self stringValueFromObject:dictionary[@"text"]];
	}
	highlight.selectionText = selection_text ?: @"";
	highlight.postTitle = [self stringValueFromObject:dictionary[@"title"]];
	if (highlight.postTitle.length == 0) {
		highlight.postTitle = [self stringValueFromObject:dictionary[@"post_title"]];
	}
	highlight.postURL = [self stringValueFromObject:dictionary[@"url"]];
	if (highlight.postURL.length == 0) {
		highlight.postURL = [self stringValueFromObject:dictionary[@"post_url"]];
	}

	NSInteger selection_start = [self integerValueFromObject:dictionary[@"selection_start"]];
	NSInteger selection_end = [self integerValueFromObject:dictionary[@"selection_end"]];
	if (selection_start == 0 && selection_end == 0) {
		selection_start = [self integerValueFromObject:dictionary[@"start_offset"]];
		selection_end = [self integerValueFromObject:dictionary[@"end_offset"]];
	}
	if (selection_start == 0 && selection_end == 0) {
		selection_start = [self integerValueFromObject:dictionary[@"start"]];
		selection_end = [self integerValueFromObject:dictionary[@"end"]];
	}

	selection_start = MAX(0, selection_start);
	selection_end = MAX(selection_start + 1, selection_end);
	highlight.selectionStart = selection_start;
	highlight.selectionEnd = selection_end;

	NSString* updated_string = [self stringValueFromObject:dictionary[@"updated_at"]];
	if (updated_string.length == 0) {
		updated_string = [self stringValueFromObject:dictionary[@"date_published"]];
	}
	if (updated_string.length == 0) {
		updated_string = [self stringValueFromObject:dictionary[@"date_modified"]];
	}
	if (updated_string.length == 0) {
		updated_string = [self stringValueFromObject:dictionary[@"created_at"]];
	}
	highlight.updatedDate = [self dateFromISO8601String:updated_string];

	if (highlight.localID.length == 0) {
		highlight.localID = [NSString stringWithFormat:@"mb-%ld-%ld-%ld",
			(long) highlight.entryID,
			(long) highlight.selectionStart,
			(long) highlight.selectionEnd];
	}

	return highlight;
}

- (NSDictionary*) dictionaryFromHighlight:(MBHighlight*) highlight
{
	if (![highlight isKindOfClass:[MBHighlight class]] || highlight.entryID <= 0) {
		return @{};
	}

	NSMutableDictionary* dictionary = [NSMutableDictionary dictionary];
	dictionary[@"id"] = highlight.localID ?: @"";
	if (highlight.highlightID.length > 0) {
		dictionary[@"highlight_id"] = highlight.highlightID;
	}
	dictionary[@"entry_id"] = @(highlight.entryID);
	dictionary[@"selection_text"] = highlight.selectionText ?: @"";
	dictionary[@"selection_start"] = @(MAX(0, highlight.selectionStart));
	dictionary[@"selection_end"] = @(MAX(MAX(0, highlight.selectionStart) + 1, highlight.selectionEnd));
	if (highlight.postTitle.length > 0) {
		dictionary[@"title"] = highlight.postTitle;
	}
	if (highlight.postURL.length > 0) {
		dictionary[@"url"] = highlight.postURL;
	}

	if (highlight.updatedDate != nil) {
		dictionary[@"updated_at"] = [[self iso8601Formatter] stringFromDate:highlight.updatedDate] ?: @"";
	}

	return dictionary;
}

- (NSISO8601DateFormatter*) iso8601Formatter
{
	static NSISO8601DateFormatter* iso8601_formatter;
	static dispatch_once_t once_token;
	dispatch_once(&once_token, ^{
		iso8601_formatter = [[NSISO8601DateFormatter alloc] init];
		iso8601_formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
	});

	return iso8601_formatter;
}

- (NSString*) generatedLocalHighlightID
{
	long long milliseconds = (long long) ([[NSDate date] timeIntervalSince1970] * 1000.0);
	NSString* uuid_value = [[NSUUID UUID] UUIDString] ?: @"";
	return [NSString stringWithFormat:@"hl-%lld-%@", milliseconds, [uuid_value lowercaseString]];
}

- (MBHighlight*) highlightCopy:(MBHighlight*) highlight
{
	if (![highlight isKindOfClass:[MBHighlight class]]) {
		return nil;
	}

	MBHighlight* copied_highlight = [[MBHighlight alloc] init];
	copied_highlight.entryID = highlight.entryID;
	copied_highlight.localID = highlight.localID ?: @"";
	copied_highlight.highlightID = highlight.highlightID ?: @"";
	copied_highlight.selectionText = highlight.selectionText ?: @"";
	copied_highlight.postTitle = highlight.postTitle ?: @"";
	copied_highlight.postURL = highlight.postURL ?: @"";
	copied_highlight.selectionStart = highlight.selectionStart;
	copied_highlight.selectionEnd = highlight.selectionEnd;
	copied_highlight.updatedDate = highlight.updatedDate;
	return copied_highlight;
}

- (NSString*) normalizedRemoteHighlightIDForHighlight:(MBHighlight*) highlight
{
	if (![highlight isKindOfClass:[MBHighlight class]]) {
		return @"";
	}

	NSString* highlight_id = [highlight.highlightID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (highlight_id.length > 0) {
		return highlight_id;
	}

	NSString* local_id = [highlight.localID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (local_id.length == 0 || [local_id hasPrefix:@"hl-"]) {
		return @"";
	}
	return local_id;
}

- (NSString*) highlightSignature:(MBHighlight*) highlight
{
	if (![highlight isKindOfClass:[MBHighlight class]]) {
		return @"";
	}
	if (highlight.entryID <= 0) {
		return @"";
	}

	NSString* trimmed_text = [highlight.selectionText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (trimmed_text.length == 0) {
		return @"";
	}

	NSInteger start_offset = MAX(0, highlight.selectionStart);
	NSInteger end_offset = MAX(start_offset + 1, highlight.selectionEnd);
	return [NSString stringWithFormat:@"%ld|%ld|%ld|%@", (long) highlight.entryID, (long) start_offset, (long) end_offset, trimmed_text];
}

- (BOOL) isSameStoredHighlight:(MBHighlight*) first_highlight other:(MBHighlight*) second_highlight
{
	if (![first_highlight isKindOfClass:[MBHighlight class]] || ![second_highlight isKindOfClass:[MBHighlight class]]) {
		return NO;
	}

	if (first_highlight.entryID <= 0 || second_highlight.entryID <= 0 || first_highlight.entryID != second_highlight.entryID) {
		return NO;
	}

	NSString* first_remote_id = [self normalizedRemoteHighlightIDForHighlight:first_highlight];
	NSString* second_remote_id = [self normalizedRemoteHighlightIDForHighlight:second_highlight];
	if (first_remote_id.length > 0 && second_remote_id.length > 0) {
		return [first_remote_id isEqualToString:second_remote_id];
	}

	NSString* first_local_id = [first_highlight.localID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	NSString* second_local_id = [second_highlight.localID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (first_local_id.length > 0 && second_local_id.length > 0 && [first_local_id isEqualToString:second_local_id]) {
		return YES;
	}

	NSString* first_signature = [self highlightSignature:first_highlight];
	NSString* second_signature = [self highlightSignature:second_highlight];
	if (first_signature.length == 0 || second_signature.length == 0) {
		return NO;
	}

	return [first_signature isEqualToString:second_signature];
}

- (NSInteger) indexOfMatchingHighlight:(MBHighlight*) highlight inCollection:(NSArray*) highlights
{
	if (![highlight isKindOfClass:[MBHighlight class]] || ![highlights isKindOfClass:[NSArray class]]) {
		return -1;
	}

	for (NSInteger i = 0; i < highlights.count; i++) {
		id object = highlights[i];
		if (![object isKindOfClass:[MBHighlight class]]) {
			continue;
		}

		MBHighlight* existing_highlight = (MBHighlight*) object;
		if ([self isSameStoredHighlight:existing_highlight other:highlight]) {
			return i;
		}
	}

	return -1;
}

- (MBHighlight*) mergedHighlightFromExisting:(MBHighlight*) existing_highlight incoming:(MBHighlight*) incoming_highlight
{
	MBHighlight* merged_highlight = [self highlightCopy:existing_highlight];
	if (merged_highlight == nil) {
		return [self highlightCopy:incoming_highlight];
	}

	if (incoming_highlight.entryID > 0) {
		merged_highlight.entryID = incoming_highlight.entryID;
	}

	NSString* incoming_text = incoming_highlight.selectionText ?: @"";
	if (incoming_text.length > 0) {
		merged_highlight.selectionText = incoming_text;
	}
	NSString* incoming_title = incoming_highlight.postTitle ?: @"";
	if (incoming_title.length > 0) {
		merged_highlight.postTitle = incoming_title;
	}
	NSString* incoming_url_string = incoming_highlight.postURL ?: @"";
	if (incoming_url_string.length > 0) {
		merged_highlight.postURL = incoming_url_string;
	}

	NSInteger incoming_start = MAX(0, incoming_highlight.selectionStart);
	NSInteger incoming_end = MAX(incoming_start + 1, incoming_highlight.selectionEnd);
	if (incoming_highlight.selectionEnd > incoming_highlight.selectionStart) {
		merged_highlight.selectionStart = incoming_start;
		merged_highlight.selectionEnd = incoming_end;
	}

	if (incoming_highlight.updatedDate != nil) {
		if (merged_highlight.updatedDate == nil || [incoming_highlight.updatedDate compare:merged_highlight.updatedDate] == NSOrderedDescending) {
			merged_highlight.updatedDate = incoming_highlight.updatedDate;
		}
	}

	NSString* existing_local_id = [merged_highlight.localID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	NSString* incoming_local_id = [incoming_highlight.localID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (existing_local_id.length == 0) {
		merged_highlight.localID = incoming_local_id;
	}
	else if (![existing_local_id hasPrefix:@"hl-"] && incoming_local_id.length > 0 && [incoming_local_id hasPrefix:@"hl-"]) {
		merged_highlight.localID = incoming_local_id;
	}

	NSString* existing_remote_id = [self normalizedRemoteHighlightIDForHighlight:merged_highlight];
	NSString* incoming_remote_id = [self normalizedRemoteHighlightIDForHighlight:incoming_highlight];
	NSString* resolved_remote_id = incoming_remote_id.length > 0 ? incoming_remote_id : existing_remote_id;
	if (resolved_remote_id.length > 0) {
		merged_highlight.highlightID = resolved_remote_id;
		if ((merged_highlight.localID ?: @"").length == 0) {
			merged_highlight.localID = resolved_remote_id;
		}
	}

	if ((merged_highlight.localID ?: @"").length == 0) {
		merged_highlight.localID = [self generatedLocalHighlightID];
	}

	return merged_highlight;
}

- (long long) highlightSortTimestamp:(MBHighlight*) highlight
{
	if (![highlight isKindOfClass:[MBHighlight class]]) {
		return 0;
	}

	if (highlight.updatedDate != nil) {
		return (long long) ([highlight.updatedDate timeIntervalSince1970] * 1000.0);
	}

	NSString* local_id = highlight.localID ?: @"";
	if ([local_id hasPrefix:@"hl-"]) {
		NSArray* id_parts = [local_id componentsSeparatedByString:@"-"];
		if (id_parts.count > 1) {
			long long timestamp_value = [id_parts[1] longLongValue];
			if (timestamp_value > 0) {
				return timestamp_value;
			}
		}
	}

	return 0;
}

- (NSArray*) sortedHighlightsFromHighlights:(NSArray*) highlights
{
	if (![highlights isKindOfClass:[NSArray class]] || highlights.count == 0) {
		return @[];
	}

	NSArray* sorted_highlights = [highlights sortedArrayUsingComparator:^NSComparisonResult(id first_object, id second_object) {
		MBHighlight* first_highlight = [first_object isKindOfClass:[MBHighlight class]] ? (MBHighlight*) first_object : nil;
		MBHighlight* second_highlight = [second_object isKindOfClass:[MBHighlight class]] ? (MBHighlight*) second_object : nil;
		long long first_timestamp = [self highlightSortTimestamp:first_highlight];
		long long second_timestamp = [self highlightSortTimestamp:second_highlight];
		if (first_timestamp > second_timestamp) {
			return NSOrderedAscending;
		}
		if (first_timestamp < second_timestamp) {
			return NSOrderedDescending;
		}

		NSString* first_id = first_highlight.localID ?: @"";
		NSString* second_id = second_highlight.localID ?: @"";
		return [second_id compare:first_id];
	}];

	return [sorted_highlights copy];
}

- (NSArray*) normalizedHighlightsFromHighlights:(NSArray*) highlights
{
	NSMutableArray* merged_highlights = [NSMutableArray array];
	for (id object in highlights ?: @[]) {
		if (![object isKindOfClass:[MBHighlight class]]) {
			continue;
		}

		MBHighlight* candidate_highlight = [self highlightCopy:(MBHighlight*) object];
		if (candidate_highlight == nil || candidate_highlight.entryID <= 0) {
			continue;
		}

		NSInteger existing_index = [self indexOfMatchingHighlight:candidate_highlight inCollection:merged_highlights];
		if (existing_index < 0) {
			[merged_highlights addObject:candidate_highlight];
			continue;
		}

		MBHighlight* existing_highlight = merged_highlights[existing_index];
		merged_highlights[existing_index] = [self mergedHighlightFromExisting:existing_highlight incoming:candidate_highlight];
	}

	return [self sortedHighlightsFromHighlights:merged_highlights];
}

- (NSArray*) highlightsFromFeedPayload:(NSDictionary*) payload defaultEntryID:(NSInteger)entry_id
{
	id items_payload = payload[@"items"];
	if (![items_payload isKindOfClass:[NSArray class]]) {
		return @[];
	}

	NSMutableArray* highlights = [NSMutableArray array];

	for (id object in (NSArray*) items_payload) {
		if (![object isKindOfClass:[NSDictionary class]]) {
			continue;
		}

		NSDictionary* item = (NSDictionary*) object;
		NSDictionary* microblog_dictionary = nil;
		id microblog_object = item[@"_microblog"];
		if ([microblog_object isKindOfClass:[NSDictionary class]]) {
			microblog_dictionary = (NSDictionary*) microblog_object;
		}

		MBHighlight* highlight = [[MBHighlight alloc] init];
		NSInteger entry_id_value = [self integerValueFromObject:microblog_dictionary[@"entry_id"]];
		if (entry_id_value <= 0) {
			entry_id_value = entry_id;
		}
		if (entry_id_value <= 0) {
			continue;
		}
		highlight.entryID = entry_id_value;
		highlight.localID = [self stringValueFromObjectOrNumber:item[@"id"]];
		highlight.highlightID = highlight.localID;
		highlight.selectionText = [self stringValueFromObject:item[@"content_text"]];
		highlight.postTitle = [self stringValueFromObject:item[@"title"]];
		highlight.postURL = [self stringValueFromObject:item[@"url"]];
		highlight.selectionStart = [self integerValueFromObject:microblog_dictionary[@"selection_start"]];
		highlight.selectionEnd = [self integerValueFromObject:microblog_dictionary[@"selection_end"]];

		NSString* updated_date_string = [self stringValueFromObject:item[@"date_published"]];
		if (updated_date_string.length == 0) {
			updated_date_string = [self stringValueFromObject:item[@"date_modified"]];
		}
		highlight.updatedDate = [self dateFromISO8601String:updated_date_string];
		if (highlight.localID.length == 0) {
			NSString* fallback_identifier = [NSString stringWithFormat:@"mb-%ld-%ld-%ld-%@",
				(long) highlight.entryID,
				(long) highlight.selectionStart,
				(long) highlight.selectionEnd,
				(updated_date_string.length > 0 ? updated_date_string : @"unknown")];
			highlight.localID = fallback_identifier;
		}

		[highlights addObject:highlight];
	}

	return [self normalizedHighlightsFromHighlights:highlights];
}

- (NSDate* _Nullable) dateValueFromEntry:(NSDictionary*) entry
{
	NSString* published_date_value = [self stringValueFromObject:entry[@"date_published"]];
	if (published_date_value.length > 0) {
		return [self dateFromISO8601String:published_date_value];
	}

	NSString* published_value = [self stringValueFromObject:entry[@"published"]];
	if (published_value.length > 0) {
		return [self dateFromISO8601String:published_value];
	}

	NSString* date_value = [self stringValueFromObject:entry[@"date"]];
	if (date_value.length > 0) {
		return [self dateFromISO8601String:date_value];
	}

	return nil;
}

- (NSInteger) integerValueFromObject:(id)object
{
	if ([object isKindOfClass:[NSNumber class]]) {
		return [(NSNumber *) object integerValue];
	}

	if ([object isKindOfClass:[NSString class]]) {
		return [(NSString *) object integerValue];
	}

	return 0;
}

- (BOOL) boolValueFromObject:(id) object defaultValue:(BOOL) default_value
{
	if ([object isKindOfClass:[NSNumber class]]) {
		return [(NSNumber*) object boolValue];
	}

	if ([object isKindOfClass:[NSString class]]) {
		NSString* normalized_value = [[(NSString*) object lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		if ([normalized_value isEqualToString:@"1"] || [normalized_value isEqualToString:@"true"] || [normalized_value isEqualToString:@"yes"]) {
			return YES;
		}

		if ([normalized_value isEqualToString:@"0"] || [normalized_value isEqualToString:@"false"] || [normalized_value isEqualToString:@"no"]) {
			return NO;
		}
	}

	return default_value;
}

- (NSString *) stringValueFromObject:(id)object
{
	if ([object isKindOfClass:[NSString class]]) {
		return object;
	}

	return @"";
}

- (NSString*) stringValueFromObjectOrNumber:(id) object
{
	if ([object isKindOfClass:[NSString class]]) {
		return (NSString*) object;
	}

	if ([object isKindOfClass:[NSNumber class]]) {
		return [(NSNumber*) object stringValue] ?: @"";
	}

	return @"";
}

- (NSDate * _Nullable) dateFromISO8601String:(NSString *)string
{
	if (string.length == 0) {
		return nil;
	}

	static NSISO8601DateFormatter *fractional_date_formatter;
	static NSISO8601DateFormatter *default_date_formatter;
	static dispatch_once_t once_token;
	dispatch_once(&once_token, ^{
		fractional_date_formatter = [[NSISO8601DateFormatter alloc] init];
		fractional_date_formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;

		default_date_formatter = [[NSISO8601DateFormatter alloc] init];
		default_date_formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
	});

	NSDate *date_value = [fractional_date_formatter dateFromString:string];
	if (date_value == nil) {
		return [default_date_formatter dateFromString:string];
	}
	return date_value;
}

- (NSURLSessionDataTask *) trackedDataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completion_handler
{
	[self beginNetworkingActivity];

	MBClient *strong_self = self;
	NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
		@try {
			if (completion_handler != nil) {
				completion_handler(data, response, error);
			}
		}
		@finally {
			[strong_self endNetworkingActivity];
		}
	}];

	return task;
}

- (void) beginNetworkingActivity
{
	BOOL should_notify = NO;

	@synchronized (self) {
		self.activeRequestCount += 1;
		should_notify = (self.activeRequestCount == 1);
	}

	if (!should_notify) {
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		[[NSNotificationCenter defaultCenter] postNotificationName:MBClientNetworkingDidStartNotification object:self];
	});
}

- (void) endNetworkingActivity
{
	BOOL should_notify = NO;

	@synchronized (self) {
		if (self.activeRequestCount > 0) {
			self.activeRequestCount -= 1;
		}
		should_notify = (self.activeRequestCount == 0);
	}

	if (!should_notify) {
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		[[NSNotificationCenter defaultCenter] postNotificationName:MBClientNetworkingDidStopNotification object:self];
	});
}

- (NSString *) urlEncodedString:(NSString *)string
{
	NSMutableCharacterSet *allowed_character_set = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
	[allowed_character_set removeCharactersInString:@"=&+?"];
	NSString *encoded_string = [string stringByAddingPercentEncodingWithAllowedCharacters:allowed_character_set];
	return encoded_string ?: @"";
}

- (NSString *) responseDescriptionForData:(NSData *)data defaultMessage:(NSString *)default_message
{
	if (data.length == 0) {
		return default_message;
	}

	id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
	if ([payload isKindOfClass:[NSDictionary class]]) {
		NSDictionary *dictionary = (NSDictionary *) payload;
		NSString *error_description = dictionary[@"error_description"];
		if (error_description.length > 0) {
			return error_description;
		}

		NSString *error_message = dictionary[@"error"];
		if (error_message.length > 0) {
			return error_message;
		}
	}

	NSString *string_value = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if (string_value.length > 0) {
		return string_value;
	}

	return default_message;
}

- (void) finishWithToken:(NSString * _Nullable)token error:(NSError * _Nullable)error completion:(void (^)(NSString * _Nullable token, NSError * _Nullable error))completion
{
	if (completion == nil) {
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		completion(token, error);
	});
}

- (void) finishVerify:(BOOL)is_valid error:(NSError * _Nullable)error completion:(void (^)(BOOL is_valid, NSError * _Nullable error))completion
{
	if (completion == nil) {
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		completion(is_valid, error);
	});
}

- (void) finishWithSubscriptions:(NSArray<MBSubscription *> * _Nullable)subscriptions entries:(NSArray<NSDictionary<NSString *, id> *> * _Nullable)entries unreadEntryIDs:(NSSet * _Nullable)unread_entry_ids isFinished:(BOOL)is_finished error:(NSError * _Nullable)error completion:(void (^)(NSArray<MBSubscription *> * _Nullable subscriptions, NSArray<NSDictionary<NSString *,id> *> * _Nullable entries, NSSet * _Nullable unread_entry_ids, BOOL is_finished, NSError * _Nullable error))completion
{
	if (completion == nil) {
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		completion(subscriptions, entries, unread_entry_ids, is_finished, error);
	});
}

- (void) finishWithFeedSubscriptions:(NSArray* _Nullable) subscriptions error:(NSError* _Nullable) error completion:(void (^)(NSArray* _Nullable subscriptions, NSError* _Nullable error))completion
{
	if (completion == nil) {
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		completion(subscriptions, error);
	});
}

- (void) finishCreateFeedSubscriptionWithStatusCode:(NSInteger) status_code subscription:(MBSubscription* _Nullable) subscription choices:(NSArray* _Nullable) choices error:(NSError* _Nullable) error completion:(void (^)(NSInteger status_code, MBSubscription* _Nullable subscription, NSArray* _Nullable choices, NSError* _Nullable error))completion
{
	if (completion == nil) {
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		completion(status_code, subscription, choices, error);
	});
}

- (void) finishWithIconsByHost:(NSDictionary<NSString *, NSString *> * _Nullable)icons_by_host error:(NSError * _Nullable)error completion:(void (^)(NSDictionary<NSString *, NSString *> * _Nullable icons_by_host, NSError * _Nullable error))completion
{
	if (completion == nil) {
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		completion(icons_by_host, error);
	});
}

- (void) finishWithBookmarks:(NSArray* _Nullable) items error:(NSError* _Nullable) error completion:(void (^)(NSArray* _Nullable items, NSError* _Nullable error))completion
{
	if (completion == nil) {
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		completion(items, error);
	});
}

- (void) finishWithPagedEntries:(NSArray* _Nullable)entries error:(NSError* _Nullable)error completion:(void (^)(NSArray* _Nullable entries, NSError* _Nullable error))completion
{
	if (completion == nil) {
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		completion(entries, error);
	});
}

- (void) finishWithPagedEntriesUpdate:(NSArray*) entries update:(void (^ _Nullable)(NSArray* entries))update
{
	if (update == nil) {
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		update(entries ?: @[]);
	});
}

- (void) finishWithRecapStatusCode:(NSInteger)status_code html:(NSString* _Nullable)html error:(NSError* _Nullable)error completion:(void (^)(NSInteger status_code, NSString* _Nullable html, NSError* _Nullable error))completion
{
	if (completion == nil) {
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		completion(status_code, html, error);
	});
}

- (void) finishWithReadingRecapDayOfWeek:(NSString* _Nullable)day_of_week error:(NSError* _Nullable)error completion:(void (^)(NSString* _Nullable day_of_week, NSError* _Nullable error))completion
{
	if (completion == nil) {
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		completion(day_of_week, error);
	});
}

- (void) finishWithHighlights:(NSArray* _Nullable)highlights error:(NSError* _Nullable)error completion:(void (^)(NSArray* _Nullable highlights, NSError* _Nullable error))completion
{
	if (completion == nil) {
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		completion(highlights, error);
	});
}

- (void) finishWithHighlightID:(NSString* _Nullable)highlight_id error:(NSError* _Nullable)error completion:(void (^)(NSString* _Nullable highlight_id, NSError* _Nullable error))completion
{
	if (completion == nil) {
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		completion(highlight_id, error);
	});
}

- (void) finishWithSimpleError:(NSError * _Nullable)error completion:(void (^)(NSError * _Nullable error))completion
{
	if (completion == nil) {
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		completion(error);
	});
}

- (void) finishWithConversationPayload:(NSDictionary* _Nullable)conversation_payload error:(NSError* _Nullable)error completion:(void (^)(NSDictionary* _Nullable conversation_payload, NSError* _Nullable error))completion
{
	if (completion == nil) {
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		completion(conversation_payload, error);
	});
}

@end
