//
//  MBNewFeedChoiceCellView.m
//  Inkwell
//
//  Created by Codex on 3/31/26.
//

#import "MBNewFeedChoiceCellView.h"
#import "MBNewFeedChoice.h"

static CGFloat const InkwellNewFeedChoiceIconSize = 16.0;

@interface MBNewFeedChoiceCellView ()

@property (strong) NSImageView* iconImageView;
@property (strong) NSTextField* titleTextField;
@property (strong) NSTextField* feedURLTextField;

- (void) setupViews;
- (void) applyTextColors;
- (NSString*) normalizedString:(NSString*) string_value;

@end

@implementation MBNewFeedChoiceCellView

- (instancetype) initWithFrame:(NSRect) frame_rect
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
	self.iconImageView.image = nil;
	self.titleTextField.stringValue = @"";
	self.feedURLTextField.stringValue = @"";
	[self applyTextColors];
}

- (void) configureWithChoice:(MBNewFeedChoice*) choice
{
	NSString* title_value = [self normalizedString:choice.title];
	NSString* feed_url_value = [self normalizedString:choice.feedURL];
	if (title_value.length == 0) {
		title_value = (feed_url_value.length > 0) ? feed_url_value : @"Untitled Feed";
	}

	NSString* image_name = choice.isJSONFeed ? @"icon_jsonfeed" : @"icon_rss";
	self.iconImageView.image = [NSImage imageNamed:image_name];
	self.titleTextField.stringValue = title_value;
	self.feedURLTextField.stringValue = feed_url_value;
	[self applyTextColors];
}

- (void) setBackgroundStyle:(NSBackgroundStyle) background_style
{
	[super setBackgroundStyle:background_style];
	[self applyTextColors];
}

- (void) viewDidChangeEffectiveAppearance
{
	[super viewDidChangeEffectiveAppearance];
	[self applyTextColors];
}

- (void) setupViews
{
	NSImageView* icon_image_view = [[NSImageView alloc] initWithFrame:NSZeroRect];
	icon_image_view.translatesAutoresizingMaskIntoConstraints = NO;
	icon_image_view.imageScaling = NSImageScaleProportionallyUpOrDown;
	icon_image_view.wantsLayer = YES;
	icon_image_view.layer.cornerRadius = 3.0;
	icon_image_view.layer.masksToBounds = YES;
	[self addSubview:icon_image_view];

	NSTextField* title_text_field = [NSTextField labelWithString:@""];
	title_text_field.translatesAutoresizingMaskIntoConstraints = NO;
	title_text_field.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
	title_text_field.lineBreakMode = NSLineBreakByTruncatingTail;
	title_text_field.maximumNumberOfLines = 1;
	title_text_field.usesSingleLineMode = YES;

	NSTextField* feed_url_text_field = [NSTextField labelWithString:@""];
	feed_url_text_field.translatesAutoresizingMaskIntoConstraints = NO;
	feed_url_text_field.font = [NSFont systemFontOfSize:11.0];
	feed_url_text_field.lineBreakMode = NSLineBreakByTruncatingTail;
	feed_url_text_field.maximumNumberOfLines = 1;
	feed_url_text_field.usesSingleLineMode = YES;

	NSStackView* text_stack_view = [[NSStackView alloc] initWithFrame:NSZeroRect];
	text_stack_view.translatesAutoresizingMaskIntoConstraints = NO;
	text_stack_view.orientation = NSUserInterfaceLayoutOrientationVertical;
	text_stack_view.alignment = NSLayoutAttributeLeading;
	text_stack_view.distribution = NSStackViewDistributionFill;
	text_stack_view.spacing = 1.0;
	[text_stack_view addArrangedSubview:title_text_field];
	[text_stack_view addArrangedSubview:feed_url_text_field];
	[self addSubview:text_stack_view];

	[NSLayoutConstraint activateConstraints:@[
		[icon_image_view.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12.0],
		[icon_image_view.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
		[icon_image_view.widthAnchor constraintEqualToConstant:InkwellNewFeedChoiceIconSize],
		[icon_image_view.heightAnchor constraintEqualToConstant:InkwellNewFeedChoiceIconSize],
		[text_stack_view.leadingAnchor constraintEqualToAnchor:icon_image_view.trailingAnchor constant:10.0],
		[text_stack_view.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12.0],
		[text_stack_view.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
	]];

	self.iconImageView = icon_image_view;
	self.titleTextField = title_text_field;
	self.feedURLTextField = feed_url_text_field;
	self.textField = title_text_field;
	[self applyTextColors];
}

- (void) applyTextColors
{
	BOOL is_selected = (self.backgroundStyle == NSBackgroundStyleEmphasized);
	NSColor* primary_color = is_selected ? [NSColor alternateSelectedControlTextColor] : [NSColor labelColor];
	NSColor* secondary_color = is_selected ? [[NSColor alternateSelectedControlTextColor] colorWithAlphaComponent:0.78] : [NSColor secondaryLabelColor];
	self.titleTextField.textColor = primary_color;
	self.feedURLTextField.textColor = secondary_color;
}

- (NSString*) normalizedString:(NSString*) string_value
{
	return [string_value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

@end
