//
//  MBHighlightCellView.h
//  Inkwell
//
//  Created by Codex on 3/4/26.
//

#import <Cocoa/Cocoa.h>

@class MBHighlight;

NS_ASSUME_NONNULL_BEGIN

@interface MBHighlightCellView : NSTableCellView

- (void) configureWithHighlight:(MBHighlight*) highlight;

@end

NS_ASSUME_NONNULL_END
