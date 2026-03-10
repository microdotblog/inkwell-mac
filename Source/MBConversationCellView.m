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
	self.nameTextField.stringValue = @"";
	self.bodyTextField.stringValue = @"";
	self.dateTextField.stringValue = @"";
}

- (void) configureWithMention:(MBMention*) mention dateText:(NSString*) date_text avatarImage:(NSImage*) avatar_image
{
	NSString* full_name = [mention.fullName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	NSString* username = [mention.username stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	NSString* name_value = full_name;
	if (name_value.length == 0) {
		name_value = username;
	}
	if (name_value.length == 0) {
		name_value = @"Unknown";
	}

	NSString* body_value = [mention.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (body_value.length == 0) {
		body_value = @"(No text)";
	}

	self.avatarImageView.image = avatar_image;
	self.nameTextField.stringValue = name_value;
	self.bodyTextField.stringValue = body_value;
	self.dateTextField.stringValue = date_text ?: @"";
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
	name_text_field.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
	name_text_field.lineBreakMode = NSLineBreakByTruncatingTail;
	name_text_field.maximumNumberOfLines = 1;
	name_text_field.usesSingleLineMode = YES;
	[self addSubview:name_text_field];

	NSTextField* body_text_field = [NSTextField labelWithString:@""];
	body_text_field.translatesAutoresizingMaskIntoConstraints = NO;
	body_text_field.font = [NSFont systemFontOfSize:12.0];
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
	date_text_field.font = [NSFont systemFontOfSize:11.0];
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

		[name_text_field.leadingAnchor constraintEqualToAnchor:avatar_image_view.trailingAnchor constant:12.0],
		[name_text_field.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-InkwellConversationCellTrailingInset],
		[name_text_field.topAnchor constraintEqualToAnchor:self.topAnchor constant:InkwellConversationCellTopInset],

		[body_text_field.leadingAnchor constraintEqualToAnchor:name_text_field.leadingAnchor],
		[body_text_field.trailingAnchor constraintEqualToAnchor:name_text_field.trailingAnchor],
		[body_text_field.topAnchor constraintEqualToAnchor:name_text_field.bottomAnchor constant:3.0],

		[date_text_field.leadingAnchor constraintEqualToAnchor:name_text_field.leadingAnchor],
		[date_text_field.trailingAnchor constraintEqualToAnchor:name_text_field.trailingAnchor],
		[date_text_field.topAnchor constraintEqualToAnchor:body_text_field.bottomAnchor constant:6.0],
		[date_text_field.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-InkwellConversationCellBottomInset]
	]];

	self.avatarImageView = avatar_image_view;
	self.nameTextField = name_text_field;
	self.bodyTextField = body_text_field;
	self.dateTextField = date_text_field;
}

@end
