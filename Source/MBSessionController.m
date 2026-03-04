//
//  MBSessionController.m
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import "MBSessionController.h"

static NSString * const InkwellTokenDefaultsKey = @"Token";

@implementation MBSessionController

- (BOOL) hasToken
{
	NSString *token_value = [self token];
	return token_value.length > 0;
}

- (NSString * _Nullable) token
{
	return [[NSUserDefaults standardUserDefaults] stringForKey:InkwellTokenDefaultsKey];
}

- (void) saveToken:(NSString *)token
{
	if (token.length == 0) {
		return;
	}

	[[NSUserDefaults standardUserDefaults] setObject:token forKey:InkwellTokenDefaultsKey];
}

- (void) clearToken
{
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:InkwellTokenDefaultsKey];
}

@end
