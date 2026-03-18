//
//  MBFeedCell.m
//  Inkwell
//
//  Created by Codex on 3/18/26.
//

#import "MBFeedCell.h"
#import "MBSubscription.h"

static CGFloat const InkwellFeedCellAvatarSize = 16.0;

@interface MBFeedCell ()

@property (nonatomic, strong) NSImageView* avatarImageView;
@property (nonatomic, strong) NSStackView* textStackView;
@property (nonatomic, strong) NSTextField* titleTextField;
@property (nonatomic, strong) NSTextField* siteURLTextField;

@end

@implementation MBFeedCell

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
	self.avatarImageView.image = nil;
	self.titleTextField.stringValue = @"";
	self.siteURLTextField.stringValue = @"";
	[self applyTextColors];
}

- (void) configureWithSubscription:(MBSubscription*) subscription avatarImage:(NSImage*) avatar_image
{
	NSString* title_value = [self trimmedString:subscription.title];
	NSString* site_url_value = [self trimmedString:subscription.siteURL];
	NSString* feed_url_value = [self trimmedString:subscription.feedURL];
	if (title_value.length == 0) {
		title_value = (site_url_value.length > 0) ? site_url_value : feed_url_value;
	}
	if (title_value.length == 0) {
		title_value = @"Untitled Feed";
	}
	if (site_url_value.length == 0) {
		site_url_value = feed_url_value;
	}

	self.avatarImageView.image = avatar_image;
	self.titleTextField.stringValue = title_value;
	self.siteURLTextField.stringValue = site_url_value;
	[self applyTextColors];
}

- (void) setBackgroundStyle:(NSBackgroundStyle) background_style
{
	[super setBackgroundStyle:background_style];
	[self applyTextColors];
}

- (NSView*) hitTest:(NSPoint) point
{
	if (NSPointInRect(point, self.bounds)) {
		return self;
	}

	return [super hitTest:point];
}

- (NSMenu*) menuForEvent:(NSEvent*) event
{
	if (self.contextMenuHandler == nil) {
		return [super menuForEvent:event];
	}

	NSView* superview = self.superview;
	while (superview != nil && ![superview isKindOfClass:[NSTableView class]]) {
		superview = superview.superview;
	}

	NSTableView* table_view = [superview isKindOfClass:[NSTableView class]] ? (NSTableView*) superview : nil;
	if (table_view != nil) {
		NSInteger row = [table_view rowForView:self];
		if (row >= 0) {
			NSIndexSet* index_set = [NSIndexSet indexSetWithIndex:(NSUInteger) row];
			[table_view selectRowIndexes:index_set byExtendingSelection:NO];
		}
	}

	NSMenu* menu = self.contextMenuHandler();
	if (menu != nil) {
		return menu;
	}

	return [super menuForEvent:event];
}

- (void) viewDidChangeEffectiveAppearance
{
	[super viewDidChangeEffectiveAppearance];
	[self applyTextColors];
}

- (void) setupViews
{
	NSImageView* avatar_image_view = [[NSImageView alloc] initWithFrame:NSZeroRect];
	avatar_image_view.translatesAutoresizingMaskIntoConstraints = NO;
	avatar_image_view.imageScaling = NSImageScaleProportionallyUpOrDown;
	avatar_image_view.wantsLayer = YES;
	avatar_image_view.layer.cornerRadius = (InkwellFeedCellAvatarSize / 2.0);
	avatar_image_view.layer.masksToBounds = YES;
	[self addSubview:avatar_image_view];

	NSTextField* title_text_field = [NSTextField labelWithString:@""];
	title_text_field.translatesAutoresizingMaskIntoConstraints = NO;
	title_text_field.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
	title_text_field.lineBreakMode = NSLineBreakByTruncatingTail;
	title_text_field.maximumNumberOfLines = 1;
	title_text_field.usesSingleLineMode = YES;

	NSTextField* site_url_text_field = [NSTextField labelWithString:@""];
	site_url_text_field.translatesAutoresizingMaskIntoConstraints = NO;
	site_url_text_field.font = [NSFont systemFontOfSize:11.0];
	site_url_text_field.lineBreakMode = NSLineBreakByTruncatingTail;
	site_url_text_field.maximumNumberOfLines = 1;
	site_url_text_field.usesSingleLineMode = YES;
	[site_url_text_field setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
	[site_url_text_field setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

	NSStackView* text_stack_view = [[NSStackView alloc] initWithFrame:NSZeroRect];
	text_stack_view.translatesAutoresizingMaskIntoConstraints = NO;
	text_stack_view.orientation = NSUserInterfaceLayoutOrientationVertical;
	text_stack_view.alignment = NSLayoutAttributeLeading;
	text_stack_view.distribution = NSStackViewDistributionFill;
	text_stack_view.spacing = 2.0;
	[text_stack_view addArrangedSubview:title_text_field];
	[text_stack_view addArrangedSubview:site_url_text_field];
	[self addSubview:text_stack_view];

	[NSLayoutConstraint activateConstraints:@[
		[avatar_image_view.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10.0],
		[avatar_image_view.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
		[avatar_image_view.widthAnchor constraintEqualToConstant:InkwellFeedCellAvatarSize],
		[avatar_image_view.heightAnchor constraintEqualToConstant:InkwellFeedCellAvatarSize],

		[text_stack_view.leadingAnchor constraintEqualToAnchor:avatar_image_view.trailingAnchor constant:10.0],
		[text_stack_view.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10.0],
		[text_stack_view.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
	]];

	self.avatarImageView = avatar_image_view;
	self.textStackView = text_stack_view;
	self.titleTextField = title_text_field;
	self.siteURLTextField = site_url_text_field;
	self.textField = title_text_field;
	[self applyTextColors];
}

- (void) applyTextColors
{
	BOOL is_selected = (self.backgroundStyle == NSBackgroundStyleEmphasized);
	NSColor* primary_color = is_selected ? [NSColor alternateSelectedControlTextColor] : [NSColor labelColor];
	NSColor* secondary_color = is_selected ? [[NSColor alternateSelectedControlTextColor] colorWithAlphaComponent:0.78] : [NSColor secondaryLabelColor];
	self.titleTextField.textColor = primary_color;
	self.siteURLTextField.textColor = secondary_color;
}

- (NSString*) trimmedString:(NSString*) string_value
{
	return [string_value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

@end
