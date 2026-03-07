//
//  MBAppDelegate.h
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import <Cocoa/Cocoa.h>

@interface MBAppDelegate : NSObject <NSApplicationDelegate>

- (IBAction) showMainWindowAction:(id) sender;
- (IBAction) showPreferences:(id) sender;
- (IBAction) signOut:(id) sender;

@end
