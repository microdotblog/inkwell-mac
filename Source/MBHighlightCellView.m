//
//  MBHighlightCellView.m
//  Inkwell
//
//  Created by Codex on 3/4/26.
//

#import "MBHighlightCellView.h"
#import "MBHighlight.h"

static CGFloat const InkwellHighlightCellTopInset = 8.0;
static CGFloat const InkwellHighlightCellBottomInset = 8.0;
static CGFloat const InkwellHighlightCellLeadingInset = 10.0;
static CGFloat const InkwellHighlightCellTrailingInset = 10.0;

static NSColor* InkwellHighlightCellTextColor(void)
{
	return [NSColor colorWithName:nil dynamicProvider:^NSColor* (NSAppearance* appearance) {
		NSAppearanceName best_match = [appearance bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]];
		if ([best_match isEqualToString:NSAppearanceNameDarkAqua]) {
			return [NSColor colorWithCalibratedRed:1.0 green:0.949 blue:0.651 alpha:1.0];
		}
		return NSColor.blackColor;
	}];
}

static NSColor* InkwellHighlightCellSecondaryTextColor(void)
{
	return NSColor.secondaryLabelColor;
}

@interface MBHighlightCellView ()

@property (nonatomic, assign) NSRange highlightTextRange;
@property (nonatomic, assign) NSRange secondaryTextRange;
@property (nonatomic, assign) BOOL hasSecondaryTextRange;

@end

@implementation MBHighlightCellView

- (instancetype) initWithFrame:(NSRect)frame_rect
{
	self = [super initWithFrame:frame_rect];
	if (self) {
		self.wantsLayer = YES;
		[self setupTextField];
		[self applyCellBackgroundColor];
	}
	return self;
}

- (void) prepareForReuse
{
	[super prepareForReuse];
	self.textField.attributedStringValue = [[NSAttributedString alloc] initWithString:@""];
	self.highlightTextRange = NSMakeRange(0, 0);
	self.secondaryTextRange = NSMakeRange(0, 0);
	self.hasSecondaryTextRange = NO;
	[self applyCellBackgroundColor];
}

- (void) configureWithHighlight:(MBHighlight*) highlight
{
	NSString* selection_text = highlight.selectionText ?: @"";
	if (selection_text.length == 0) {
		selection_text = @"(No highlight text)";
	}

	NSMutableAttributedString* attributed_string = [[NSMutableAttributedString alloc] initWithString:selection_text attributes:[self highlightTextAttributes]];
	self.highlightTextRange = NSMakeRange(0, selection_text.length);
	self.secondaryTextRange = NSMakeRange(0, 0);
	self.hasSecondaryTextRange = NO;

	NSString* date_text = [self formattedDateString:highlight.updatedDate];
	if (date_text.length > 0) {
		NSAttributedString* separator = [[NSAttributedString alloc] initWithString:@"\n"];
		[attributed_string appendAttributedString:separator];

		NSUInteger date_start = attributed_string.length;
		NSAttributedString* date_string = [[NSAttributedString alloc] initWithString:date_text attributes:[self secondaryTextAttributes]];
		[attributed_string appendAttributedString:date_string];
		self.secondaryTextRange = NSMakeRange(date_start, date_text.length);
		self.hasSecondaryTextRange = YES;
	}

	self.textField.attributedStringValue = attributed_string;
	[self applyTextColors];
	[self applyCellBackgroundColor];
}

- (void) prepareForLayoutWithWidth:(CGFloat) width
{
	CGFloat text_width = [self textWidthForCellWidth:width];
	self.textField.preferredMaxLayoutWidth = text_width;
	self.frame = NSMakeRect(self.frame.origin.x, self.frame.origin.y, width, self.frame.size.height);
	[self.textField invalidateIntrinsicContentSize];
	[self setNeedsLayout:YES];
	[self layoutSubtreeIfNeeded];
}

- (void) layout
{
	CGFloat text_width = [self textWidthForCellWidth:self.bounds.size.width];
	if (fabs(self.textField.preferredMaxLayoutWidth - text_width) > 0.5) {
		self.textField.preferredMaxLayoutWidth = text_width;
		[self.textField invalidateIntrinsicContentSize];
	}

	[super layout];
}

- (CGFloat) textWidthForCellWidth:(CGFloat) width
{
	CGFloat text_width = width - InkwellHighlightCellLeadingInset - InkwellHighlightCellTrailingInset;
	return MAX(1.0, floor(text_width));
}

- (void) setupTextField
{
	NSTextField* text_field = [NSTextField labelWithString:@""];
	text_field.translatesAutoresizingMaskIntoConstraints = NO;
	text_field.lineBreakMode = NSLineBreakByWordWrapping;
	text_field.maximumNumberOfLines = 0;
	text_field.usesSingleLineMode = NO;
	text_field.selectable = NO;
	[text_field setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
	[text_field setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
	[text_field setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
	if ([text_field.cell isKindOfClass:[NSTextFieldCell class]]) {
		NSTextFieldCell* text_cell = (NSTextFieldCell*) text_field.cell;
		text_cell.wraps = YES;
		text_cell.scrollable = NO;
		text_cell.usesSingleLineMode = NO;
		text_cell.lineBreakMode = NSLineBreakByWordWrapping;
		text_cell.truncatesLastVisibleLine = NO;
	}
	[self addSubview:text_field];

	[NSLayoutConstraint activateConstraints:@[
		[text_field.topAnchor constraintEqualToAnchor:self.topAnchor constant:InkwellHighlightCellTopInset],
		[text_field.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-InkwellHighlightCellBottomInset],
		[text_field.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:InkwellHighlightCellLeadingInset],
		[text_field.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-InkwellHighlightCellTrailingInset]
	]];

	self.textField = text_field;
}

- (NSDictionary*) highlightTextAttributes
{
	NSMutableParagraphStyle* paragraph_style = [[NSMutableParagraphStyle alloc] init];
	paragraph_style.paragraphSpacing = 5.0;

	return @{
		NSFontAttributeName: [NSFont systemFontOfSize:15.0],
		NSForegroundColorAttributeName: [self primaryTextColor],
		NSParagraphStyleAttributeName: paragraph_style
	};
}

- (NSDictionary*) secondaryTextAttributes
{
	NSMutableParagraphStyle* paragraph_style = [[NSMutableParagraphStyle alloc] init];
	paragraph_style.paragraphSpacingBefore = 3.0;

	return @{
		NSFontAttributeName: [NSFont systemFontOfSize:14.0],
		NSForegroundColorAttributeName: [self secondaryTextColor],
		NSParagraphStyleAttributeName: paragraph_style
	};
}

- (NSString*) formattedDateString:(NSDate*) date_value
{
	if (date_value == nil) {
		return @"";
	}

	return [NSDateFormatter localizedStringFromDate:date_value dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle] ?: @"";
}

- (void) viewDidChangeEffectiveAppearance
{
	[super viewDidChangeEffectiveAppearance];
	[self applyTextColors];
	[self applyCellBackgroundColor];
}

- (void) setBackgroundStyle:(NSBackgroundStyle) background_style
{
	[super setBackgroundStyle:background_style];
	[self applyTextColors];
	[self applyCellBackgroundColor];
}

- (void) applyCellBackgroundColor
{
	self.layer.backgroundColor = NSColor.clearColor.CGColor;
}

- (NSColor*) primaryTextColor
{
	BOOL is_selected = (self.backgroundStyle == NSBackgroundStyleEmphasized);
	return is_selected ? [NSColor alternateSelectedControlTextColor] : InkwellHighlightCellTextColor();
}

- (NSColor*) secondaryTextColor
{
	BOOL is_selected = (self.backgroundStyle == NSBackgroundStyleEmphasized);
	return is_selected ? [[NSColor alternateSelectedControlTextColor] colorWithAlphaComponent:0.78] : InkwellHighlightCellSecondaryTextColor();
}

- (void) applyTextColors
{
	NSMutableAttributedString* attributed_string = [self.textField.attributedStringValue mutableCopy];
	if (attributed_string.length == 0) {
		return;
	}

	if (NSMaxRange(self.highlightTextRange) <= attributed_string.length) {
		[attributed_string addAttribute:NSForegroundColorAttributeName value:[self primaryTextColor] range:self.highlightTextRange];
	}
	if (self.hasSecondaryTextRange && NSMaxRange(self.secondaryTextRange) <= attributed_string.length) {
		[attributed_string addAttribute:NSForegroundColorAttributeName value:[self secondaryTextColor] range:self.secondaryTextRange];
	}

	self.textField.attributedStringValue = attributed_string;
}

@end
