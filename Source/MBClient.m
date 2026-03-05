//
//  MBClient.m
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import "MBClient.h"
#import "MBHighlight.h"
#import "MBSubscription.h"

NSString * const MBClientErrorDomain = @"MBClientErrorDomain";
NSString* const MBClientNetworkingDidStartNotification = @"MBClientNetworkingDidStartNotification";
NSString* const MBClientNetworkingDidStopNotification = @"MBClientNetworkingDidStopNotification";

static NSString * const MBClientIdentifierURL = @"https://micro.ink";
static NSString * const MBRedirectURI = @"inkwell://signin";
static NSString * const MBAuthorizationEndpoint = @"https://micro.blog/indieauth/auth";
static NSString * const MBTokenEndpoint = @"https://micro.blog/indieauth/token";
static NSString * const MBVerifyEndpoint = @"https://micro.blog/account/verify";
static NSString * const MBFeedSubscriptionsEndpoint = @"https://micro.blog/feeds/v2/subscriptions.json";
static NSString * const MBFeedEntriesEndpoint = @"https://micro.blog/feeds/v2/entries.json";
static NSString * const MBFeedUnreadEntriesEndpoint = @"https://micro.blog/feeds/v2/unread_entries.json";
static NSString * const MBFeedIconsEndpoint = @"https://micro.blog/feeds/v2/icons.json";
static NSString* const MBFeedsEndpointBase = @"https://micro.blog/feeds";
static NSInteger const MBFeedEntriesPageSize = 200;
static NSTimeInterval const MBFeedEntriesLookbackInterval = 7.0 * 24.0 * 60.0 * 60.0;

@interface MBClient ()

@property (strong) NSURLSession *session;
@property (assign) NSInteger activeRequestCount;

@end

@implementation MBClient

- (instancetype) init
{
	self = [super init];
	if (self) {
		self.session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
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

		[self finishVerify:YES error:nil completion:completion];
	}];
	[task resume];
}

- (void) fetchFeedEntriesWithToken:(NSString *)token completion:(void (^)(NSArray<MBSubscription *> * _Nullable subscriptions, NSArray<NSDictionary<NSString *,id> *> * _Nullable entries, NSSet * _Nullable unread_entry_ids, NSError * _Nullable error))completion
{
	if (token.length == 0) {
		NSError *error = [NSError errorWithDomain:MBClientErrorDomain code:1005 userInfo:@{ NSLocalizedDescriptionKey: @"Missing token for entries request." }];
		[self finishWithSubscriptions:nil entries:nil unreadEntryIDs:nil error:error completion:completion];
		return;
	}

	NSMutableURLRequest *subscriptions_request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:MBFeedSubscriptionsEndpoint]];
	subscriptions_request.HTTPMethod = @"GET";
	[subscriptions_request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

	NSString *authorization_value = [NSString stringWithFormat:@"Bearer %@", token];
	[subscriptions_request setValue:authorization_value forHTTPHeaderField:@"Authorization"];

	NSURLSessionDataTask *task = [self trackedDataTaskWithRequest:subscriptions_request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
		if (error != nil) {
			[self finishWithSubscriptions:nil entries:nil unreadEntryIDs:nil error:error completion:completion];
			return;
		}

		NSHTTPURLResponse *http_response = (NSHTTPURLResponse *) response;
		if (http_response.statusCode < 200 || http_response.statusCode >= 300) {
			NSString *description = [self responseDescriptionForData:data defaultMessage:@"Subscriptions request failed."];
			NSError *request_error = [NSError errorWithDomain:MBClientErrorDomain code:http_response.statusCode userInfo:@{ NSLocalizedDescriptionKey: description }];
			[self finishWithSubscriptions:nil entries:nil unreadEntryIDs:nil error:request_error completion:completion];
			return;
		}

		id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
		if (![payload isKindOfClass:[NSArray class]]) {
			NSError *parse_error = [NSError errorWithDomain:MBClientErrorDomain code:1006 userInfo:@{ NSLocalizedDescriptionKey: @"Subscriptions response was invalid." }];
			[self finishWithSubscriptions:nil entries:nil unreadEntryIDs:nil error:parse_error completion:completion];
			return;
		}

		NSArray<MBSubscription *> *subscriptions = [self subscriptionsFromPayload:(NSArray *) payload];

		NSDate* cutoff_date = [[NSDate date] dateByAddingTimeInterval:-MBFeedEntriesLookbackInterval];
		NSMutableArray* accumulated_entries = [NSMutableArray array];
		NSMutableSet* seen_entry_ids = [NSMutableSet set];
		[self fetchPagedFeedEntriesWithAuthorizationValue:authorization_value pageNumber:1 cutoffDate:cutoff_date accumulatedEntries:accumulated_entries seenEntryIDs:seen_entry_ids completion:^(NSArray* _Nullable entries, NSError* _Nullable entries_error) {
			if (entries_error != nil) {
				[self finishWithSubscriptions:subscriptions entries:nil unreadEntryIDs:nil error:entries_error completion:completion];
				return;
			}

			NSMutableURLRequest *unread_request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:MBFeedUnreadEntriesEndpoint]];
			unread_request.HTTPMethod = @"GET";
			[unread_request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
			[unread_request setValue:authorization_value forHTTPHeaderField:@"Authorization"];

			NSURLSessionDataTask *unread_task = [self trackedDataTaskWithRequest:unread_request completionHandler:^(NSData * _Nullable unread_data, NSURLResponse * _Nullable unread_response, NSError * _Nullable unread_error) {
				NSSet *unread_entry_ids = nil;
				if (unread_error == nil) {
					NSHTTPURLResponse *unread_http_response = (NSHTTPURLResponse *) unread_response;
					if (unread_http_response.statusCode >= 200 && unread_http_response.statusCode < 300) {
						id unread_payload = [NSJSONSerialization JSONObjectWithData:unread_data options:0 error:nil];
						if ([unread_payload isKindOfClass:[NSArray class]]) {
							unread_entry_ids = [self unreadEntryIDsFromPayload:(NSArray *) unread_payload];
						}
					}
				}

				[self finishWithSubscriptions:subscriptions entries:entries unreadEntryIDs:unread_entry_ids error:nil completion:completion];
			}];
			[unread_task resume];
		}];
	}];
	[task resume];
}

- (void) fetchPagedFeedEntriesWithAuthorizationValue:(NSString*) authorization_value pageNumber:(NSInteger) page_number cutoffDate:(NSDate*) cutoff_date accumulatedEntries:(NSMutableArray*) accumulated_entries seenEntryIDs:(NSMutableSet*) seen_entry_ids completion:(void (^)(NSArray* _Nullable entries, NSError* _Nullable error))completion
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

		if (!should_continue) {
			NSArray* filtered_entries = [self filterEntries:accumulated_entries byCutoffDate:cutoff_date];
			[self finishWithPagedEntries:filtered_entries error:nil completion:completion];
			return;
		}

		[self fetchPagedFeedEntriesWithAuthorizationValue:authorization_value pageNumber:(page_number + 1) cutoffDate:cutoff_date accumulatedEntries:accumulated_entries seenEntryIDs:seen_entry_ids completion:completion];
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

- (void) markAsRead:(NSInteger)entry_id token:(NSString*) token completion:(void (^)(NSError * _Nullable error))completion
{
	[self updateUnreadStateForEntryID:entry_id token:token should_mark_unread:NO completion:completion];
}

- (void) markAsUnread:(NSInteger)entry_id token:(NSString*) token completion:(void (^)(NSError * _Nullable error))completion
{
	[self updateUnreadStateForEntryID:entry_id token:token should_mark_unread:YES completion:completion];
}

- (void) updateUnreadStateForEntryID:(NSInteger)entry_id token:(NSString*) token should_mark_unread:(BOOL)should_mark_unread completion:(void (^)(NSError * _Nullable error))completion
{
	if (entry_id <= 0) {
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

	NSDictionary *payload = @{ @"unread_entries": @[ @(entry_id) ] };
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

		NSDictionary<NSString *, id> *dictionary = (NSDictionary<NSString *, id> *) object;
		MBSubscription *subscription = [[MBSubscription alloc] init];
		subscription.subscriptionID = [self integerValueFromObject:dictionary[@"id"]];
		subscription.feedID = [self integerValueFromObject:dictionary[@"feed_id"]];
		subscription.title = [self stringValueFromObject:dictionary[@"title"]];
		subscription.feedURL = [self stringValueFromObject:dictionary[@"feed_url"]];
		subscription.siteURL = [self stringValueFromObject:dictionary[@"site_url"]];

		NSString *created_at_string = [self stringValueFromObject:dictionary[@"created_at"]];
		subscription.createdAt = [self dateFromISO8601String:created_at_string];

		[subscriptions addObject:subscription];
	}

	return [subscriptions copy];
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
		highlight.entryID = entry_id_value;
		highlight.selectionText = [self stringValueFromObject:item[@"content_text"]];
		highlight.selectionStart = [self integerValueFromObject:microblog_dictionary[@"selection_start"]];
		highlight.selectionEnd = [self integerValueFromObject:microblog_dictionary[@"selection_end"]];

		NSString* updated_date_string = [self stringValueFromObject:item[@"date_published"]];
		if (updated_date_string.length == 0) {
			updated_date_string = [self stringValueFromObject:item[@"date_modified"]];
		}
		highlight.updatedDate = [self dateFromISO8601String:updated_date_string];

		[highlights addObject:highlight];
	}

	return [highlights copy];
}

- (NSDate* _Nullable) dateValueFromEntry:(NSDictionary*) entry
{
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

- (NSString *) stringValueFromObject:(id)object
{
	if ([object isKindOfClass:[NSString class]]) {
		return object;
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

- (void) finishWithSubscriptions:(NSArray<MBSubscription *> * _Nullable)subscriptions entries:(NSArray<NSDictionary<NSString *, id> *> * _Nullable)entries unreadEntryIDs:(NSSet * _Nullable)unread_entry_ids error:(NSError * _Nullable)error completion:(void (^)(NSArray<MBSubscription *> * _Nullable subscriptions, NSArray<NSDictionary<NSString *,id> *> * _Nullable entries, NSSet * _Nullable unread_entry_ids, NSError * _Nullable error))completion
{
	if (completion == nil) {
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		completion(subscriptions, entries, unread_entry_ids, error);
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

- (void) finishWithPagedEntries:(NSArray* _Nullable)entries error:(NSError* _Nullable)error completion:(void (^)(NSArray* _Nullable entries, NSError* _Nullable error))completion
{
	if (completion == nil) {
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		completion(entries, error);
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

- (void) finishWithSimpleError:(NSError * _Nullable)error completion:(void (^)(NSError * _Nullable error))completion
{
	if (completion == nil) {
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		completion(error);
	});
}

@end
