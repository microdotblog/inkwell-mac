//
//  MBConversationCellView.h
//  Inkwell
//
//  Created by Codex on 3/7/26.
//

#import <Cocoa/Cocoa.h>

@class MBMention;

NS_ASSUME_NONNULL_BEGIN

@interface MBConversationCellView : NSTableCellView

- (void) configureWithMention:(MBMention*) mention dateText:(NSString*) date_text avatarImage:(NSImage*) avatar_image;

@end

NS_ASSUME_NONNULL_END
