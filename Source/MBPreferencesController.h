//
//  MBPreferencesController.h
//  Inkwell
//
//  Created by Codex on 3/7/26.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface MBPreferencesController : NSWindowController

@property (nonatomic, copy, nullable) void (^textSettingsChangedHandler)(void);
@property (nonatomic, copy, nullable) void (^signOutHandler)(void);

- (void) reloadFromDefaults;

@end

NS_ASSUME_NONNULL_END
