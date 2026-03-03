//
//  MBClient.m
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import "MBClient.h"

NSString * const MBClientErrorDomain = @"MBClientErrorDomain";

static NSString * const MBClientIdentifierURL = @"https://micro.ink";
static NSString * const MBRedirectURI = @"inkwell://signin";
static NSString * const MBAuthorizationEndpoint = @"https://micro.blog/indieauth/auth";
static NSString * const MBTokenEndpoint = @"https://micro.blog/indieauth/token";
static NSString * const MBVerifyEndpoint = @"https://micro.blog/account/verify";

@interface MBClient ()

@property (strong) NSURLSession *session;

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

	NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
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

	NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
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

@end
