//
//  MBSidebarCell.h
//  Inkwell
//
//  Created by Codex on 3/18/26.
//

#import <Cocoa/Cocoa.h>

@class MBRoundedImageView;

NS_ASSUME_NONNULL_BEGIN

@interface MBSidebarCell : NSTableCellView

@property (nonatomic, strong, readonly) MBRoundedImageView* avatarView;
@property (nonatomic, strong, readonly) NSTextField* titleTextField;
@property (nonatomic, strong, readonly) NSTextField* subtitleTextField;
@property (nonatomic, strong, readonly) NSTextField* subscriptionTextField;
@property (nonatomic, strong, readonly) NSTextField* dateTextField;
@property (nonatomic, strong, readonly) NSTextField* bookmarkTextField;
@property (nonatomic, strong, readonly) NSLayoutConstraint* subscriptionTopWithSubtitleConstraint;
@property (nonatomic, strong, readonly) NSLayoutConstraint* subscriptionTopWithoutSubtitleConstraint;
@property (nonatomic, strong, readonly) NSLayoutConstraint* dateTopWithSubscriptionConstraint;
@property (nonatomic, strong, readonly) NSLayoutConstraint* dateTopWithSubtitleConstraint;
@property (nonatomic, strong, readonly) NSLayoutConstraint* dateTopWithoutSecondaryTextConstraint;

@end

NS_ASSUME_NONNULL_END
