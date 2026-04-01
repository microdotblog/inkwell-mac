//
//  MBNewFeedChoiceCellView.h
//  Inkwell
//
//  Created by Codex on 3/31/26.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class MBNewFeedChoice;

@interface MBNewFeedChoiceCellView : NSTableCellView

- (void) configureWithChoice:(MBNewFeedChoice*) choice;

@end

NS_ASSUME_NONNULL_END
