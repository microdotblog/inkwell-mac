//
//  MBSidebarCell.m
//  Inkwell
//
//  Created by Codex on 3/18/26.
//

#import "MBSidebarCell.h"
#import "MBRoundedImageView.h"

static CGFloat const InkwellSidebarCellAvatarSize = 26.0;
static CGFloat const InkwellSidebarCellAvatarInset = 3.0;
static CGFloat const InkwellSidebarCellTextInset = 10.0;
static CGFloat const InkwellSidebarCellRightInset = 10.0;
static CGFloat const InkwellSidebarCellVerticalSpacing = 8.0;
static CGFloat const InkwellSidebarCellTitleFontSize = 14.0;
static CGFloat const InkwellSidebarCellSubtitleFontSize = 14.0;
static CGFloat const InkwellSidebarCellDateFontSize = 13.0;

@interface MBSidebarCell ()

@property (nonatomic, strong) MBRoundedImageView* avatarView;
@property (nonatomic, strong) NSTextField* titleTextField;
@property (nonatomic, strong) NSTextField* subtitleTextField;
@property (nonatomic, strong) NSTextField* subscriptionTextField;
@property (nonatomic, strong) NSTextField* dateTextField;
@property (nonatomic, strong) NSTextField* bookmarkTextField;
@property (nonatomic, strong) NSLayoutConstraint* subscriptionTopWithSubtitleConstraint;
@property (nonatomic, strong) NSLayoutConstraint* subscriptionTopWithoutSubtitleConstraint;
@property (nonatomic, strong) NSLayoutConstraint* dateTopWithSubscriptionConstraint;
@property (nonatomic, strong) NSLayoutConstraint* dateTopWithSubtitleConstraint;
@property (nonatomic, strong) NSLayoutConstraint* dateTopWithoutSecondaryTextConstraint;

@end

@implementation MBSidebarCell

- (instancetype) initWithFrame:(NSRect) frame_rect
{
	self = [super initWithFrame:frame_rect];
	if (self) {
		[self setupViews];
	}
	return self;
}

- (void) setupViews
{
	MBRoundedImageView* avatar_view = [[MBRoundedImageView alloc] initWithFrame:NSZeroRect];
	avatar_view.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField* title_field = [NSTextField labelWithString:@""];
	title_field.translatesAutoresizingMaskIntoConstraints = NO;
	title_field.font = [NSFont systemFontOfSize:InkwellSidebarCellTitleFontSize weight:NSFontWeightSemibold];
	title_field.lineBreakMode = NSLineBreakByWordWrapping;
	title_field.maximumNumberOfLines = 2;
	title_field.usesSingleLineMode = NO;
	if ([title_field.cell isKindOfClass:[NSTextFieldCell class]]) {
		NSTextFieldCell* title_cell = (NSTextFieldCell*) title_field.cell;
		title_cell.wraps = YES;
		title_cell.scrollable = NO;
		title_cell.usesSingleLineMode = NO;
		title_cell.lineBreakMode = NSLineBreakByWordWrapping;
		title_cell.truncatesLastVisibleLine = YES;
	}

	NSTextField* subtitle_field = [NSTextField labelWithString:@""];
	subtitle_field.translatesAutoresizingMaskIntoConstraints = NO;
	subtitle_field.font = [NSFont systemFontOfSize:InkwellSidebarCellSubtitleFontSize];
	subtitle_field.textColor = [NSColor secondaryLabelColor];
	subtitle_field.lineBreakMode = NSLineBreakByWordWrapping;
	subtitle_field.maximumNumberOfLines = 2;
	subtitle_field.usesSingleLineMode = NO;
	if ([subtitle_field.cell isKindOfClass:[NSTextFieldCell class]]) {
		NSTextFieldCell* subtitle_cell = (NSTextFieldCell*) subtitle_field.cell;
		subtitle_cell.wraps = YES;
		subtitle_cell.scrollable = NO;
		subtitle_cell.usesSingleLineMode = NO;
		subtitle_cell.lineBreakMode = NSLineBreakByWordWrapping;
		subtitle_cell.truncatesLastVisibleLine = YES;
	}

	NSTextField* subscription_field = [NSTextField labelWithString:@""];
	subscription_field.translatesAutoresizingMaskIntoConstraints = NO;
	subscription_field.font = [NSFont systemFontOfSize:InkwellSidebarCellSubtitleFontSize];
	subscription_field.textColor = [NSColor secondaryLabelColor];
	subscription_field.lineBreakMode = NSLineBreakByTruncatingTail;
	subscription_field.maximumNumberOfLines = 1;
	subscription_field.hidden = YES;

	NSTextField* date_field = [NSTextField labelWithString:@""];
	date_field.translatesAutoresizingMaskIntoConstraints = NO;
	date_field.font = [NSFont systemFontOfSize:InkwellSidebarCellDateFontSize];
	date_field.textColor = [NSColor tertiaryLabelColor];
	date_field.lineBreakMode = NSLineBreakByTruncatingTail;
	date_field.maximumNumberOfLines = 1;

	NSTextField* bookmark_field = [NSTextField labelWithString:@""];
	bookmark_field.translatesAutoresizingMaskIntoConstraints = NO;
	bookmark_field.font = [NSFont systemFontOfSize:InkwellSidebarCellDateFontSize];
	bookmark_field.textColor = [NSColor tertiaryLabelColor];
	bookmark_field.lineBreakMode = NSLineBreakByTruncatingTail;
	bookmark_field.maximumNumberOfLines = 1;
	bookmark_field.hidden = YES;
	[bookmark_field setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

	[self addSubview:avatar_view];
	[self addSubview:title_field];
	[self addSubview:subtitle_field];
	[self addSubview:subscription_field];
	[self addSubview:date_field];
	[self addSubview:bookmark_field];

	NSLayoutConstraint* bottom_constraint = [date_field.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-8.0];
	bottom_constraint.priority = NSLayoutPriorityDefaultHigh;

	NSLayoutConstraint* subscription_top_with_subtitle_constraint = [subscription_field.topAnchor constraintEqualToAnchor:subtitle_field.bottomAnchor constant:InkwellSidebarCellVerticalSpacing];
	NSLayoutConstraint* subscription_top_without_subtitle_constraint = [subscription_field.topAnchor constraintEqualToAnchor:title_field.bottomAnchor constant:InkwellSidebarCellVerticalSpacing];
	NSLayoutConstraint* date_top_with_subscription_constraint = [date_field.topAnchor constraintEqualToAnchor:subscription_field.bottomAnchor constant:InkwellSidebarCellVerticalSpacing];
	NSLayoutConstraint* date_top_with_subtitle_constraint = [date_field.topAnchor constraintEqualToAnchor:subtitle_field.bottomAnchor constant:InkwellSidebarCellVerticalSpacing];
	NSLayoutConstraint* date_top_without_secondary_text_constraint = [date_field.topAnchor constraintEqualToAnchor:title_field.bottomAnchor constant:InkwellSidebarCellVerticalSpacing];

	[NSLayoutConstraint activateConstraints:@[
		[avatar_view.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:InkwellSidebarCellAvatarInset],
		[avatar_view.topAnchor constraintEqualToAnchor:self.topAnchor constant:8.0],
		[avatar_view.widthAnchor constraintEqualToConstant:InkwellSidebarCellAvatarSize],
		[avatar_view.heightAnchor constraintEqualToConstant:InkwellSidebarCellAvatarSize],
		[title_field.topAnchor constraintEqualToAnchor:self.topAnchor constant:8.0],
		[title_field.leadingAnchor constraintEqualToAnchor:avatar_view.trailingAnchor constant:InkwellSidebarCellTextInset],
		[title_field.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-InkwellSidebarCellRightInset],
		[subtitle_field.topAnchor constraintEqualToAnchor:title_field.bottomAnchor constant:InkwellSidebarCellVerticalSpacing],
		[subtitle_field.leadingAnchor constraintEqualToAnchor:title_field.leadingAnchor],
		[subtitle_field.trailingAnchor constraintEqualToAnchor:title_field.trailingAnchor],
		[subscription_field.leadingAnchor constraintEqualToAnchor:title_field.leadingAnchor],
		[subscription_field.trailingAnchor constraintEqualToAnchor:title_field.trailingAnchor],
		[date_field.leadingAnchor constraintEqualToAnchor:title_field.leadingAnchor],
		[date_field.trailingAnchor constraintLessThanOrEqualToAnchor:bookmark_field.leadingAnchor constant:-8.0],
		[bookmark_field.centerYAnchor constraintEqualToAnchor:date_field.centerYAnchor],
		[bookmark_field.trailingAnchor constraintEqualToAnchor:title_field.trailingAnchor],
		bottom_constraint
	]];

	subscription_top_with_subtitle_constraint.active = NO;
	subscription_top_without_subtitle_constraint.active = NO;
	date_top_with_subscription_constraint.active = NO;
	date_top_with_subtitle_constraint.active = YES;
	date_top_without_secondary_text_constraint.active = NO;

	self.avatarView = avatar_view;
	self.titleTextField = title_field;
	self.subtitleTextField = subtitle_field;
	self.subscriptionTextField = subscription_field;
	self.dateTextField = date_field;
	self.bookmarkTextField = bookmark_field;
	self.subscriptionTopWithSubtitleConstraint = subscription_top_with_subtitle_constraint;
	self.subscriptionTopWithoutSubtitleConstraint = subscription_top_without_subtitle_constraint;
	self.dateTopWithSubscriptionConstraint = date_top_with_subscription_constraint;
	self.dateTopWithSubtitleConstraint = date_top_with_subtitle_constraint;
	self.dateTopWithoutSecondaryTextConstraint = date_top_without_secondary_text_constraint;
}

@end
