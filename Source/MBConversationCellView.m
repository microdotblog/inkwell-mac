//
//  MBConversationCellView.m
//  Inkwell
//
//  Created by Codex on 3/7/26.
//

#import "MBConversationCellView.h"
#import "MBMention.h"

static CGFloat const InkwellConversationCellTopInset = 10.0;
static CGFloat const InkwellConversationCellBottomInset = 10.0;
static CGFloat const InkwellConversationCellLeadingInset = 6.0;
static CGFloat const InkwellConversationCellTrailingInset = 6.0;
static CGFloat const InkwellConversationAvatarSize = 34.0;
static CGFloat const InkwellConversationAvatarToTextSpacing = 12.0;
static CGFloat const InkwellConversationNameToBodySpacing = 6.0;
static CGFloat const InkwellConversationBodyToDateSpacing = 8.0;

@interface MBConversationCellView ()

@property (nonatomic, strong) NSImageView* avatarImageView;
@property (nonatomic, strong) NSTextField* nameTextField;
@property (nonatomic, strong) NSTextField* bodyTextField;
@property (nonatomic, strong) NSTextField* dateTextField;

@end

@implementation MBConversationCellView

- (instancetype) initWithFrame:(NSRect)frame_rect
{
	self = [super initWithFrame:frame_rect];
	if (self) {
		[self setupViews];
	}
	return self;
}

- (void) prepareForReuse
{
	[super prepareForReuse];
	self.avatarImageView.image = nil;
	self.nameTextField.attributedStringValue = [[NSAttributedString alloc] initWithString:@""];
	self.bodyTextField.attributedStringValue = [[NSAttributedString alloc] initWithString:@""];
	self.dateTextField.stringValue = @"";
}

- (void) configureWithMention:(MBMention*) mention dateText:(NSString*) date_text avatarImage:(NSImage*) avatar_image
{
	NSString* full_name = [mention.fullName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	NSString* username = [mention.username stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	NSString* name_value = full_name;
	if (name_value.length == 0) {
		name_value = (username.length > 0) ? [NSString stringWithFormat:@"@%@", username] : @"";
	}
	if (name_value.length == 0) {
		name_value = @"Unknown";
	}

	NSString* body_value = [mention.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (body_value.length == 0) {
		body_value = @"(No text)";
	}

	self.avatarImageView.image = avatar_image;
	self.nameTextField.attributedStringValue = [self attributedNameStringForName:name_value username:username];
	self.bodyTextField.attributedStringValue = [self attributedBodyStringForText:body_value];
	self.dateTextField.stringValue = date_text ?: @"";
}

- (void) prepareForLayoutWithWidth:(CGFloat) width
{
	CGFloat text_width = [self textColumnWidthForCellWidth:width];
	self.bodyTextField.preferredMaxLayoutWidth = text_width;
	self.frame = NSMakeRect(self.frame.origin.x, self.frame.origin.y, width, self.frame.size.height);
	[self.bodyTextField invalidateIntrinsicContentSize];
	[self setNeedsLayout:YES];
	[self layoutSubtreeIfNeeded];
}

- (void) layout
{
	CGFloat text_width = [self textColumnWidthForCellWidth:self.bounds.size.width];
	if (fabs(self.bodyTextField.preferredMaxLayoutWidth - text_width) > 0.5) {
		self.bodyTextField.preferredMaxLayoutWidth = text_width;
		[self.bodyTextField invalidateIntrinsicContentSize];
	}

	[super layout];
}

- (CGFloat) textColumnWidthForCellWidth:(CGFloat) width
{
	CGFloat text_width = width - InkwellConversationCellLeadingInset - InkwellConversationAvatarSize - InkwellConversationAvatarToTextSpacing - InkwellConversationCellTrailingInset;
	return MAX(1.0, floor(text_width));
}

- (void) setupViews
{
	NSImageView* avatar_image_view = [[NSImageView alloc] initWithFrame:NSZeroRect];
	avatar_image_view.translatesAutoresizingMaskIntoConstraints = NO;
	avatar_image_view.imageScaling = NSImageScaleAxesIndependently;
	avatar_image_view.wantsLayer = YES;
	avatar_image_view.layer.cornerRadius = (InkwellConversationAvatarSize / 2.0);
	avatar_image_view.layer.masksToBounds = YES;
	[self addSubview:avatar_image_view];

	NSTextField* name_text_field = [NSTextField labelWithString:@""];
	name_text_field.translatesAutoresizingMaskIntoConstraints = NO;
	name_text_field.font = [NSFont systemFontOfSize:15.0 weight:NSFontWeightSemibold];
	name_text_field.lineBreakMode = NSLineBreakByTruncatingTail;
	name_text_field.maximumNumberOfLines = 1;
	name_text_field.usesSingleLineMode = YES;
	[self addSubview:name_text_field];

	NSTextField* body_text_field = [NSTextField labelWithString:@""];
	body_text_field.translatesAutoresizingMaskIntoConstraints = NO;
	body_text_field.font = [NSFont systemFontOfSize:15.0];
	body_text_field.lineBreakMode = NSLineBreakByWordWrapping;
	body_text_field.maximumNumberOfLines = 0;
	body_text_field.usesSingleLineMode = NO;
	[body_text_field setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
	[body_text_field setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
	[body_text_field setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
	if ([body_text_field.cell isKindOfClass:[NSTextFieldCell class]]) {
		NSTextFieldCell* body_text_cell = (NSTextFieldCell*) body_text_field.cell;
		body_text_cell.wraps = YES;
		body_text_cell.scrollable = NO;
		body_text_cell.usesSingleLineMode = NO;
		body_text_cell.lineBreakMode = NSLineBreakByWordWrapping;
		body_text_cell.truncatesLastVisibleLine = NO;
	}
	[self addSubview:body_text_field];

	NSTextField* date_text_field = [NSTextField labelWithString:@""];
	date_text_field.translatesAutoresizingMaskIntoConstraints = NO;
	date_text_field.font = [NSFont systemFontOfSize:14.0];
	date_text_field.textColor = NSColor.secondaryLabelColor;
	date_text_field.lineBreakMode = NSLineBreakByTruncatingTail;
	date_text_field.maximumNumberOfLines = 1;
	date_text_field.usesSingleLineMode = YES;
	[self addSubview:date_text_field];

	[NSLayoutConstraint activateConstraints:@[
		[avatar_image_view.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:InkwellConversationCellLeadingInset],
		[avatar_image_view.topAnchor constraintEqualToAnchor:self.topAnchor constant:InkwellConversationCellTopInset],
		[avatar_image_view.widthAnchor constraintEqualToConstant:InkwellConversationAvatarSize],
		[avatar_image_view.heightAnchor constraintEqualToConstant:InkwellConversationAvatarSize],
		[avatar_image_view.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-InkwellConversationCellBottomInset],

		[name_text_field.leadingAnchor constraintEqualToAnchor:avatar_image_view.trailingAnchor constant:InkwellConversationAvatarToTextSpacing],
		[name_text_field.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-InkwellConversationCellTrailingInset],
		[name_text_field.topAnchor constraintEqualToAnchor:self.topAnchor constant:InkwellConversationCellTopInset],

		[body_text_field.leadingAnchor constraintEqualToAnchor:name_text_field.leadingAnchor],
		[body_text_field.trailingAnchor constraintEqualToAnchor:name_text_field.trailingAnchor],
		[body_text_field.topAnchor constraintEqualToAnchor:name_text_field.bottomAnchor constant:InkwellConversationNameToBodySpacing],

		[date_text_field.leadingAnchor constraintEqualToAnchor:name_text_field.leadingAnchor],
		[date_text_field.trailingAnchor constraintEqualToAnchor:name_text_field.trailingAnchor],
		[date_text_field.topAnchor constraintEqualToAnchor:body_text_field.bottomAnchor constant:InkwellConversationBodyToDateSpacing],
		[date_text_field.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-InkwellConversationCellBottomInset]
	]];

	self.avatarImageView = avatar_image_view;
	self.nameTextField = name_text_field;
	self.bodyTextField = body_text_field;
	self.dateTextField = date_text_field;
}

- (NSAttributedString *) attributedNameStringForName:(NSString *)nameValue username:(NSString *)username
{
	NSDictionary* name_attributes = @{
		NSFontAttributeName: [NSFont systemFontOfSize:15.0 weight:NSFontWeightSemibold],
		NSForegroundColorAttributeName: NSColor.labelColor
	};
	NSString* name_value = nameValue ?: @"";
	NSMutableAttributedString* attributed_string = [[NSMutableAttributedString alloc] initWithString:name_value attributes:name_attributes];

	NSString* normalized_username = [username stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (normalized_username.length == 0) {
		return attributed_string;
	}
	if ([name_value isEqualToString:[NSString stringWithFormat:@"@%@", normalized_username]]) {
		return attributed_string;
	}

	NSString* username_string = [NSString stringWithFormat:@" @%@", normalized_username];
	NSDictionary* username_attributes = @{
		NSFontAttributeName: [NSFont systemFontOfSize:15.0],
		NSForegroundColorAttributeName: NSColor.secondaryLabelColor
	};
	NSAttributedString* username_attributed_string = [[NSAttributedString alloc] initWithString:username_string attributes:username_attributes];
	[attributed_string appendAttributedString:username_attributed_string];

	return attributed_string;
}

- (NSAttributedString *) attributedBodyStringForText:(NSString *)bodyText
{
	NSString* body_text = bodyText ?: @"";
	NSDictionary* attributes = @{
		NSFontAttributeName: [NSFont systemFontOfSize:15.0],
		NSForegroundColorAttributeName: NSColor.labelColor
	};
	NSMutableAttributedString* attributed_string = [[NSMutableAttributedString alloc] initWithString:body_text attributes:attributes];
	if (body_text.length == 0 || ![body_text hasPrefix:@"@"]) {
		return attributed_string;
	}

	NSCharacterSet* whitespace_character_set = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	NSInteger length = body_text.length;
	NSInteger index = 0;
	while (index < length && [body_text characterAtIndex:index] == '@') {
		NSInteger mention_start = index;
		index++;
		while (index < length && ![whitespace_character_set characterIsMember:[body_text characterAtIndex:index]]) {
			index++;
		}

		NSRange mention_range = NSMakeRange(mention_start, (index - mention_start));
		[attributed_string addAttribute:NSForegroundColorAttributeName value:NSColor.secondaryLabelColor range:mention_range];

		while (index < length && [whitespace_character_set characterIsMember:[body_text characterAtIndex:index]]) {
			index++;
		}
	}

	return attributed_string;
}

@end
