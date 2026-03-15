//
//  MBPathUtilities.m
//  Inkwell
//
//  Created by Codex on 3/15/26.
//

#import "MBPathUtilities.h"

static NSString* const InkwellLegacyHighlightsCacheFilename = @"highlights.json";
static NSString* const InkwellLegacyUnreadEntryIDsCacheFilename = @"unread_entry_ids.json";
static NSString* const InkwellLegacyIconsDirectoryName = @"Icons";

@implementation MBPathUtilities

+ (NSURL* _Nullable) appContainerDirectoryURLForSearchPathDirectory:(NSSearchPathDirectory) search_path_directory createIfNeeded:(BOOL) create_if_needed
{
	NSFileManager* file_manager = [NSFileManager defaultManager];
	NSArray* directory_urls = [file_manager URLsForDirectory:search_path_directory inDomains:NSUserDomainMask];
	NSURL* base_directory_url = [directory_urls firstObject];
	if (base_directory_url == nil) {
		return nil;
	}

	NSString* bundle_identifier = [[NSBundle mainBundle] bundleIdentifier];
	if (bundle_identifier.length == 0) {
		bundle_identifier = @"Inkwell";
	}

	NSURL* container_directory_url = [base_directory_url URLByAppendingPathComponent:bundle_identifier isDirectory:YES];
	if (!create_if_needed) {
		return container_directory_url;
	}

	if (![file_manager createDirectoryAtURL:container_directory_url withIntermediateDirectories:YES attributes:nil error:nil]) {
		return nil;
	}

	return container_directory_url;
}

+ (NSURL* _Nullable) appSubdirectoryURLForSearchPathDirectory:(NSSearchPathDirectory) search_path_directory relativePath:(NSString*) relative_path createIfNeeded:(BOOL) create_if_needed
{
	NSString* trimmed_relative_path = [relative_path stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (trimmed_relative_path.length == 0) {
		return [self appContainerDirectoryURLForSearchPathDirectory:search_path_directory createIfNeeded:create_if_needed];
	}

	NSURL* container_directory_url = [self appContainerDirectoryURLForSearchPathDirectory:search_path_directory createIfNeeded:create_if_needed];
	if (container_directory_url == nil) {
		return nil;
	}

	NSURL* subdirectory_url = [container_directory_url URLByAppendingPathComponent:trimmed_relative_path isDirectory:YES];
	if (!create_if_needed) {
		return subdirectory_url;
	}

	if (![[NSFileManager defaultManager] createDirectoryAtURL:subdirectory_url withIntermediateDirectories:YES attributes:nil error:nil]) {
		return nil;
	}

	return subdirectory_url;
}

+ (NSURL* _Nullable) appFileURLForSearchPathDirectory:(NSSearchPathDirectory) search_path_directory filename:(NSString*) filename createDirectoryIfNeeded:(BOOL) create_directory_if_needed
{
	NSString* trimmed_filename = [filename stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (trimmed_filename.length == 0) {
		return nil;
	}

	NSURL* container_directory_url = [self appContainerDirectoryURLForSearchPathDirectory:search_path_directory createIfNeeded:create_directory_if_needed];
	if (container_directory_url == nil) {
		return nil;
	}

	return [container_directory_url URLByAppendingPathComponent:trimmed_filename isDirectory:NO];
}

+ (void) cleanupLegacyFiles
{
	static dispatch_once_t once_token;
	dispatch_once(&once_token, ^{
		NSURL* application_support_directory_url = [self appContainerDirectoryURLForSearchPathDirectory:NSApplicationSupportDirectory createIfNeeded:NO];
		if (application_support_directory_url == nil) {
			return;
		}

		NSFileManager* file_manager = [NSFileManager defaultManager];
		NSArray* legacy_relative_paths = @[
			InkwellLegacyHighlightsCacheFilename,
			InkwellLegacyUnreadEntryIDsCacheFilename,
			InkwellLegacyIconsDirectoryName
		];

		for (NSString* relative_path in legacy_relative_paths) {
			NSURL* legacy_url = [application_support_directory_url URLByAppendingPathComponent:relative_path];
			[file_manager removeItemAtURL:legacy_url error:nil];
		}
	});
}

@end
