#import "NSStrings+Extras.h"

#import <AppKit/AppKit.h>

@implementation NSString (Extras)

+ (NSString*) mb_openInBrowserString
{
	NSString* browser_s = @"Open in Browser";

	NSURL* example_url = [NSURL URLWithString:@"https://micro.ink/"];
	NSURL* app_url = [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:example_url];
	NSArray* browser_names = @[
		@"Chrome",
		@"Edge",
		@"Firefox",
		@"Opera",
		@"Brave",
		@"Safari",
		@"Vivaldi",
		@"Arc",
		@"Dia",
		@"Orion"
	];

	for (NSString* browser_name in browser_names) {
		if ([app_url.lastPathComponent containsString:browser_name]) {
			browser_s = [NSString stringWithFormat:@"Open in %@", browser_name];
			break;
		}
	}

	return browser_s;
}

@end
