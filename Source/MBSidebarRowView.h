//
//  MBSidebarRowView.h
//  Inkwell
//
//  Created by Codex on 3/31/26.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface MBSidebarRowView : NSTableRowView

@property (nonatomic, strong, nullable) NSColor* customBackgroundColor;
@property (nonatomic, strong, nullable) NSColor* customBorderColor;
@property (nonatomic, strong, nullable) NSColor* customSelectionBackgroundColor;

@end

NS_ASSUME_NONNULL_END
