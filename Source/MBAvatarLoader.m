//
//  MBAvatarLoader.m
//  Inkwell
//
//  Created by Codex on 3/8/26.
//

#import "MBAvatarLoader.h"
#import "MBPathUtilities.h"
#import <CommonCrypto/CommonDigest.h>

static NSTimeInterval const InkwellAvatarCacheExpirationInterval = (14.0 * 24.0 * 60.0 * 60.0);
static NSString* const InkwellAvatarCacheDirectoryName = @"Icons";
static NSString* const InkwellAvatarFallbackExtension = @"avatar";

NSNotificationName const MBAvatarLoaderDidLoadImageNotification = @"MBAvatarLoaderDidLoadImageNotification";
NSString* const MBAvatarLoaderURLStringUserInfoKey = @"url_string";

@interface MBAvatarLoader ()

@property (nonatomic, strong) NSURLSession* imageSession;
@property (nonatomic, strong) NSMutableDictionary* imageByURL;
@property (nonatomic, strong) NSMutableDictionary* cacheDateByURL;
@property (nonatomic, strong) NSMutableSet* pendingURLStrings;

@end

@implementation MBAvatarLoader

+ (instancetype) sharedLoader
{
	static MBAvatarLoader* shared_loader;
	static dispatch_once_t once_token;
	dispatch_once(&once_token, ^{
		shared_loader = [[MBAvatarLoader alloc] initPrivate];
	});
	return shared_loader;
}

- (instancetype) init
{
	return [MBAvatarLoader sharedLoader];
}

- (instancetype) initPrivate
{
	self = [super init];
	if (self) {
		[MBPathUtilities cleanupLegacyFiles];
		self.imageSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
		self.imageByURL = [NSMutableDictionary dictionary];
		self.cacheDateByURL = [NSMutableDictionary dictionary];
		self.pendingURLStrings = [NSMutableSet set];
	}
	return self;
}

- (NSImage* _Nullable) cachedImageForURLString:(NSString*) url_string
{
	NSString* normalized_url = [self normalizedURLString:url_string];
	if (normalized_url.length == 0) {
		return nil;
	}

	NSImage* cached_image = self.imageByURL[normalized_url];
	NSDate* cached_date = self.cacheDateByURL[normalized_url];
	if (cached_image != nil && cached_date != nil && ![self isExpiredDate:cached_date]) {
		return cached_image;
	}
	if (cached_image != nil) {
		[self.imageByURL removeObjectForKey:normalized_url];
		[self.cacheDateByURL removeObjectForKey:normalized_url];
		[self removeCachedImageFileForURLString:normalized_url];
	}

	NSURL* cache_file_url = [self cacheFileURLForURLString:normalized_url createDirectory:NO];
	if (cache_file_url == nil) {
		return nil;
	}

	NSDate* created_date = [self createdDateForCachedFileAtURL:cache_file_url];
	if (created_date == nil || [self isExpiredDate:created_date]) {
		[self removeCachedFileAtURL:cache_file_url];
		return nil;
	}

	NSData* image_data = [NSData dataWithContentsOfURL:cache_file_url];
	if (image_data.length == 0) {
		[self removeCachedFileAtURL:cache_file_url];
		return nil;
	}

	NSImage* image_value = [[NSImage alloc] initWithData:image_data];
	if (image_value == nil) {
		[self removeCachedFileAtURL:cache_file_url];
		return nil;
	}

	self.imageByURL[normalized_url] = image_value;
	self.cacheDateByURL[normalized_url] = created_date;
	return image_value;
}

- (void) loadImageForURLString:(NSString*) url_string
{
	NSString* normalized_url = [self normalizedURLString:url_string];
	if (normalized_url.length == 0) {
		return;
	}

	if ([self cachedImageForURLString:normalized_url] != nil) {
		return;
	}
	if ([self.pendingURLStrings containsObject:normalized_url]) {
		return;
	}

	NSURL* image_url = [NSURL URLWithString:normalized_url];
	if (image_url == nil) {
		return;
	}

	[self.pendingURLStrings addObject:normalized_url];

	__weak typeof(self) weak_self = self;
	NSURLSessionDataTask* task = [self.imageSession dataTaskWithURL:image_url completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
		#pragma unused(response)
			MBAvatarLoader* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		NSImage* image_value = nil;
		if (error == nil && data.length > 0) {
			image_value = [[NSImage alloc] initWithData:data];
		}
		if (image_value != nil) {
			[strong_self writeCachedImageData:data forURLString:normalized_url];
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			[strong_self.pendingURLStrings removeObject:normalized_url];
			if (image_value == nil) {
				return;
			}

			NSDate* cache_date = [NSDate date];
			strong_self.imageByURL[normalized_url] = image_value;
			strong_self.cacheDateByURL[normalized_url] = cache_date;

			[[NSNotificationCenter defaultCenter] postNotificationName:MBAvatarLoaderDidLoadImageNotification object:strong_self userInfo:@{
				MBAvatarLoaderURLStringUserInfoKey: normalized_url
			}];
		});
	}];
	[task resume];
}

- (NSString*) normalizedURLString:(NSString*) url_string
{
	return [url_string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

- (BOOL) isExpiredDate:(NSDate*) created_date
{
	NSDate* expiration_date = [NSDate dateWithTimeIntervalSinceNow:(-1.0 * InkwellAvatarCacheExpirationInterval)];
	return ([created_date compare:expiration_date] == NSOrderedAscending);
}

- (NSDate* _Nullable) createdDateForCachedFileAtURL:(NSURL*) file_url
{
	if (file_url == nil || ![file_url isFileURL]) {
		return nil;
	}

	NSDictionary* attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:file_url.path error:nil];
	if (![attributes isKindOfClass:[NSDictionary class]]) {
		return nil;
	}

	return attributes[NSFileCreationDate];
}

- (void) writeCachedImageData:(NSData*) image_data forURLString:(NSString*) url_string
{
	if (image_data.length == 0 || url_string.length == 0) {
		return;
	}

	NSURL* cache_file_url = [self cacheFileURLForURLString:url_string createDirectory:YES];
	if (cache_file_url == nil) {
		return;
	}

	[image_data writeToURL:cache_file_url atomically:YES];
}

- (void) removeCachedImageFileForURLString:(NSString*) url_string
{
	NSURL* cache_file_url = [self cacheFileURLForURLString:url_string createDirectory:NO];
	if (cache_file_url == nil) {
		return;
	}

	[self removeCachedFileAtURL:cache_file_url];
}

- (void) removeCachedFileAtURL:(NSURL*) file_url
{
	if (file_url == nil || ![file_url isFileURL]) {
		return;
	}

	[[NSFileManager defaultManager] removeItemAtURL:file_url error:nil];
}

- (NSURL* _Nullable) cacheFileURLForURLString:(NSString*) url_string createDirectory:(BOOL) create_directory
{
	NSURL* directory_url = [self cacheDirectoryURLCreatingIfNeeded:create_directory];
	if (directory_url == nil) {
		return nil;
	}

	NSString* file_name = [self cacheFileNameForURLString:url_string];
	if (file_name.length == 0) {
		return nil;
	}

	return [directory_url URLByAppendingPathComponent:file_name isDirectory:NO];
}

- (NSURL* _Nullable) cacheDirectoryURLCreatingIfNeeded:(BOOL) create_directory
{
	return [MBPathUtilities appSubdirectoryURLForSearchPathDirectory:NSCachesDirectory relativePath:InkwellAvatarCacheDirectoryName createIfNeeded:create_directory];
}

- (NSString*) cacheFileNameForURLString:(NSString*) url_string
{
	NSString* hash_string = [self sha1StringForString:url_string];
	if (hash_string.length == 0) {
		return @"";
	}

	NSString* host_string = [[NSURL URLWithString:url_string].host lowercaseString] ?: @"";
	NSString* base_name = hash_string;
	if (host_string.length > 0) {
		base_name = [NSString stringWithFormat:@"%@-%@", host_string, hash_string];
	}

	NSString* extension_value = [self preferredCacheFileExtensionForURLString:url_string];
	return [base_name stringByAppendingPathExtension:extension_value];
}

- (NSString*) preferredCacheFileExtensionForURLString:(NSString*) url_string
{
	NSString* extension_value = [[NSURL URLWithString:url_string].pathExtension lowercaseString] ?: @"";
	NSArray* good_extensions = @[
		@"jpg",
		@"jpeg",
		@"gif",
		@"png",
		@"ico",
		@"webp"
	];
	if ([good_extensions containsObject:extension_value]) {
		return extension_value;
	}

	return InkwellAvatarFallbackExtension;
}

- (NSString*) sha1StringForString:(NSString*) string_value
{
	NSData* string_data = [string_value dataUsingEncoding:NSUTF8StringEncoding];
	if (string_data.length == 0) {
		return @"";
	}

	unsigned char digest[CC_SHA1_DIGEST_LENGTH];
	CC_SHA1(string_data.bytes, (CC_LONG) string_data.length, digest);

	NSMutableString* result_string = [NSMutableString stringWithCapacity:(CC_SHA1_DIGEST_LENGTH * 2)];
	for (NSInteger i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
		[result_string appendFormat:@"%02x", digest[i]];
	}
	return [result_string copy];
}

@end
