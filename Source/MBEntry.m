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
	return [enclosure_type containsString:@"audio/"];
}

@end
