//
//  MBEntry.m
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import "MBEntry.h"

@implementation MBEntry

- (BOOL) hasEnclosure
{
	NSString* enclosure_url = [self.enclosureURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	return (enclosure_url.length > 0);
}

@end
