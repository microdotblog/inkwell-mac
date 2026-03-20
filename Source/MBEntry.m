//
//  MBEntry.m
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import "MBEntry.h"

@implementation MBEntry

- (BOOL) hasAudioEnclosure
{
	NSString* enclosure_type = [self.enclosureType stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if ([enclosure_type containsString:@"audio/"]) {
		return YES;
	}

	if (enclosure_type.length > 0) {
		return NO;
	}

	NSString* enclosure_url = [self.enclosureURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	NSString* lowercase_url = [enclosure_url lowercaseString];
	return ([lowercase_url hasSuffix:@"mp3"] || [lowercase_url hasSuffix:@"m4a"]);
}

@end
