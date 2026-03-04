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
static NSString* const InkwellHighlightColorName = @"color_highlight";

@interface MBHighlightCellView ()

@property (nonatomic, strong) NSDateFormatter* dateFormatter;

@end

@implementation MBHighlightCellView

- (instancetype) initWithFrame:(NSRect)frame_rect
{
	self = [super initWithFrame:frame_rect];
	if (self) {
		[self setupTextField];
	}
	return self;
}

- (void) prepareForReuse
{
	[super prepareForReuse];
	self.textField.attributedStringValue = [[NSAttributedString alloc] initWithString:@""];
}

- (void) configureWithHighlight:(MBHighlight*) highlight
{
	NSString* selection_text = highlight.selectionText ?: @"";
	if (selection_text.length == 0) {
		selection_text = @"(No highlight text)";
	}

	NSMutableAttributedString* attributed_string = [[NSMutableAttributedString alloc] initWithString:selection_text attributes:[self highlightTextAttributes]];
	[attributed_string addAttributes:[self highlightBackgroundAttributes] range:NSMakeRange(0, selection_text.length)];

	NSString* date_text = [self formattedDateString:highlight.updatedDate];
	if (date_text.length > 0) {
		NSAttributedString* separator = [[NSAttributedString alloc] initWithString:@"\n"];
		[attributed_string appendAttributedString:separator];

		NSAttributedString* date_string = [[NSAttributedString alloc] initWithString:date_text attributes:[self secondaryTextAttributes]];
		[attributed_string appendAttributedString:date_string];
	}

	self.textField.attributedStringValue = attributed_string;
}

- (void) setupTextField
{
	NSTextField* text_field = [NSTextField labelWithString:@""];
	text_field.translatesAutoresizingMaskIntoConstraints = NO;
	text_field.lineBreakMode = NSLineBreakByWordWrapping;
	text_field.maximumNumberOfLines = 3;
	text_field.usesSingleLineMode = NO;
	text_field.selectable = YES;
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
	return @{
		NSFontAttributeName: [NSFont systemFontOfSize:13.0],
		NSForegroundColorAttributeName: NSColor.labelColor
	};
}

- (NSDictionary*) highlightBackgroundAttributes
{
	NSColor* highlight_color = [NSColor colorNamed:InkwellHighlightColorName];
	if (highlight_color == nil) {
		highlight_color = [NSColor colorWithCalibratedRed:1.0 green:0.95 blue:0.56 alpha:1.0];
	}

	return @{
		NSBackgroundColorAttributeName: highlight_color
	};
}

- (NSDictionary*) secondaryTextAttributes
{
	return @{
		NSFontAttributeName: [NSFont systemFontOfSize:11.0],
		NSForegroundColorAttributeName: NSColor.secondaryLabelColor
	};
}

- (NSString*) formattedDateString:(NSDate*) date_value
{
	if (date_value == nil) {
		return @"";
	}

	if (self.dateFormatter == nil) {
		NSDateFormatter* date_formatter = [[NSDateFormatter alloc] init];
		date_formatter.dateStyle = NSDateFormatterMediumStyle;
		date_formatter.timeStyle = NSDateFormatterShortStyle;
		self.dateFormatter = date_formatter;
	}

	return [self.dateFormatter stringFromDate:date_value] ?: @"";
}

@end
