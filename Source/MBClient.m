//
//  MBClient.m
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import "MBClient.h"
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
static NSString * const MBFeedIconsEndpoint = @"https://micro.blog/feeds/v2/icons.json";

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

- (void) fetchFeedEntriesWithToken:(NSString *)token completion:(void (^)(NSArray<MBSubscription *> * _Nullable subscriptions, NSArray<NSDictionary<NSString *,id> *> * _Nullable entries, NSError * _Nullable error))completion
{
	if (token.length == 0) {
		NSError *error = [NSError errorWithDomain:MBClientErrorDomain code:1005 userInfo:@{ NSLocalizedDescriptionKey: @"Missing token for entries request." }];
		[self finishWithSubscriptions:nil entries:nil error:error completion:completion];
		return;
	}

	NSMutableURLRequest *subscriptions_request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:MBFeedSubscriptionsEndpoint]];
	subscriptions_request.HTTPMethod = @"GET";
	[subscriptions_request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

	NSString *authorization_value = [NSString stringWithFormat:@"Bearer %@", token];
	[subscriptions_request setValue:authorization_value forHTTPHeaderField:@"Authorization"];

	NSURLSessionDataTask *task = [self trackedDataTaskWithRequest:subscriptions_request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
		if (error != nil) {
			[self finishWithSubscriptions:nil entries:nil error:error completion:completion];
			return;
		}

		NSHTTPURLResponse *http_response = (NSHTTPURLResponse *) response;
		if (http_response.statusCode < 200 || http_response.statusCode >= 300) {
			NSString *description = [self responseDescriptionForData:data defaultMessage:@"Subscriptions request failed."];
			NSError *request_error = [NSError errorWithDomain:MBClientErrorDomain code:http_response.statusCode userInfo:@{ NSLocalizedDescriptionKey: description }];
			[self finishWithSubscriptions:nil entries:nil error:request_error completion:completion];
			return;
		}

		id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
		if (![payload isKindOfClass:[NSArray class]]) {
			NSError *parse_error = [NSError errorWithDomain:MBClientErrorDomain code:1006 userInfo:@{ NSLocalizedDescriptionKey: @"Subscriptions response was invalid." }];
			[self finishWithSubscriptions:nil entries:nil error:parse_error completion:completion];
			return;
		}

		NSArray<MBSubscription *> *subscriptions = [self subscriptionsFromPayload:(NSArray *) payload];

		NSMutableURLRequest *entries_request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:MBFeedEntriesEndpoint]];
		entries_request.HTTPMethod = @"GET";
		[entries_request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
		[entries_request setValue:authorization_value forHTTPHeaderField:@"Authorization"];

		NSURLSessionDataTask *entries_task = [self trackedDataTaskWithRequest:entries_request completionHandler:^(NSData * _Nullable entries_data, NSURLResponse * _Nullable entries_response, NSError * _Nullable entries_error) {
			if (entries_error != nil) {
				[self finishWithSubscriptions:subscriptions entries:nil error:entries_error completion:completion];
				return;
			}

			NSHTTPURLResponse *entries_http_response = (NSHTTPURLResponse *) entries_response;
			if (entries_http_response.statusCode < 200 || entries_http_response.statusCode >= 300) {
				NSString *description = [self responseDescriptionForData:entries_data defaultMessage:@"Entries request failed."];
				NSError *request_error = [NSError errorWithDomain:MBClientErrorDomain code:entries_http_response.statusCode userInfo:@{ NSLocalizedDescriptionKey: description }];
				[self finishWithSubscriptions:subscriptions entries:nil error:request_error completion:completion];
				return;
			}

			id entries_payload = [NSJSONSerialization JSONObjectWithData:entries_data options:0 error:nil];
			if (![entries_payload isKindOfClass:[NSArray class]]) {
				NSError *parse_error = [NSError errorWithDomain:MBClientErrorDomain code:1007 userInfo:@{ NSLocalizedDescriptionKey: @"Entries response was invalid." }];
				[self finishWithSubscriptions:subscriptions entries:nil error:parse_error completion:completion];
				return;
			}

			NSMutableArray<NSDictionary<NSString *, id> *> *entries = [NSMutableArray array];
			for (id object in (NSArray *) entries_payload) {
				if ([object isKindOfClass:[NSDictionary class]]) {
					[entries addObject:object];
				}
			}

			[self finishWithSubscriptions:subscriptions entries:[entries copy] error:nil completion:completion];
		}];
		[entries_task resume];
	}];
	[task resume];
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

- (void) finishWithSubscriptions:(NSArray<MBSubscription *> * _Nullable)subscriptions entries:(NSArray<NSDictionary<NSString *, id> *> * _Nullable)entries error:(NSError * _Nullable)error completion:(void (^)(NSArray<MBSubscription *> * _Nullable subscriptions, NSArray<NSDictionary<NSString *,id> *> * _Nullable entries, NSError * _Nullable error))completion
{
	if (completion == nil) {
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		completion(subscriptions, entries, error);
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

@end
