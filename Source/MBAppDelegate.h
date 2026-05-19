//
//  MBAppDelegate.h
//  Inkwell
//
//  Created by Manton Reece on 3/3/26.
//

#import <Cocoa/Cocoa.h>

@interface MBAppDelegate : NSObject <NSApplicationDelegate, NSMenuItemValidation>

- (IBAction) showMainWindowAction:(id) sender;
- (IBAction) showPreferences:(id) sender;
- (IBAction) showHelp:(id) sender;
- (IBAction) openPostWindow:(id) sender;
- (IBAction) saveDraft:(id) sender;
- (IBAction) preview:(id) sender;
- (IBAction) toggleTitleField:(id) sender;
- (IBAction) signOut:(id) sender;

@end
