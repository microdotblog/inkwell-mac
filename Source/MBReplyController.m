//
//  MBReplyController.m
//  Inkwell
//
//  Created by Codex on 4/23/26.
//

#import "MBReplyController.h"
#import "MBClient.h"

static CGFloat const InkwellReplyWindowWidth = 500.0;
static CGFloat const InkwellReplyWindowHeight = 200.0;

@interface MBReplyController () <NSTextViewDelegate>

@property (nonatomic, strong) MBClient* client;
@property (nonatomic, copy) NSString* token;
@property (nonatomic, strong) NSTextView* textView;
@property (nonatomic, strong) NSProgressIndicator* progressIndicator;
@property (nonatomic, strong) NSButton* cancelButton;
@property (nonatomic, strong) NSButton* postButton;
@property (nonatomic, copy) NSString* postID;
@property (nonatomic, assign) BOOL isPosting;

@end

@implementation MBReplyController

- (instancetype) init
{
	return [self initWithClient:nil token:nil];
}

- (instancetype) initWithClient:(MBClient * _Nullable)client token:(NSString * _Nullable)token
{
	self = [super initWithWindow:nil];
	if (self) {
		self.client = client;
		self.token = token ?: @"";
		self.postID = @"0";
	}
	return self;
}

- (void) showForWindow:(NSWindow *)parentWindow postID:(NSString *)postID prefillText:(NSString *)prefillText
{
	[self setupWindowIfNeeded];
	if (parentWindow == nil) {
		return;
	}

	NSString* normalized_post_id = [postID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	self.postID = (normalized_post_id.length > 0) ? normalized_post_id : @"0";
	NSString* normalized_prefill_text = prefillText ?: @"";

	if (self.window.sheetParent == parentWindow) {
		[self applyPrefillText:normalized_prefill_text];
		[self.window makeFirstResponder:self.textView];
		return;
	}

	if (self.window.sheetParent != nil) {
		[self.window.sheetParent endSheet:self.window];
	}

	[self resetWindowState];
	[self applyPrefillText:normalized_prefill_text];
	[parentWindow beginSheet:self.window completionHandler:nil];
	[self.window makeFirstResponder:self.textView];
}

- (void) textDidChange:(NSNotification*) notification
{
	if (notification.object != self.textView) {
		return;
	}

	[self updatePostButtonEnabledState];
}

- (IBAction) cancel:(id) sender
{
	#pragma unused(sender)

	[self closeReplyWindow];
}

- (IBAction) post:(id) sender
{
	#pragma unused(sender)

	if (self.isPosting) {
		return;
	}

	NSString* content_string = self.textView.string ?: @"";
	if (content_string.length == 0) {
		return;
	}

	self.isPosting = YES;
	self.cancelButton.enabled = NO;
	self.postButton.enabled = NO;
	self.progressIndicator.hidden = NO;
	[self.progressIndicator startAnimation:nil];

	__weak typeof(self) weak_self = self;
	[self.client createReplyForPostID:self.postID content:content_string token:self.token completion:^(NSError* _Nullable error) {
		MBReplyController* strong_self = weak_self;
		if (strong_self == nil) {
			return;
		}

		strong_self.isPosting = NO;
		if (error == nil) {
			[strong_self closeReplyWindow];
			return;
		}

		[strong_self.progressIndicator stopAnimation:nil];
		strong_self.progressIndicator.hidden = YES;
		strong_self.cancelButton.enabled = YES;
		[strong_self updatePostButtonEnabledState];
		NSBeep();
	}];
}

- (void) setupWindowIfNeeded
{
	if (self.window != nil) {
		return;
	}

	NSRect content_rect = NSMakeRect(0.0, 0.0, InkwellReplyWindowWidth, InkwellReplyWindowHeight);
	NSWindow* sheet_window = [[NSWindow alloc] initWithContentRect:content_rect styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
	sheet_window.releasedWhenClosed = NO;
	sheet_window.title = @"Reply";
	sheet_window.titleVisibility = NSWindowTitleHidden;
	sheet_window.titlebarAppearsTransparent = YES;
	sheet_window.movable = NO;

	NSView* content_view = [[NSView alloc] initWithFrame:content_rect];
	content_view.translatesAutoresizingMaskIntoConstraints = NO;

	NSScrollView* scroll_view = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	scroll_view.translatesAutoresizingMaskIntoConstraints = NO;
	scroll_view.drawsBackground = NO;
	scroll_view.hasVerticalScroller = YES;
	scroll_view.autohidesScrollers = YES;
	scroll_view.borderType = NSNoBorder;

	NSTextView* text_view = [[NSTextView alloc] initWithFrame:NSZeroRect];
	text_view.minSize = NSMakeSize(0.0, 0.0);
	text_view.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
	text_view.verticallyResizable = YES;
	text_view.horizontallyResizable = NO;
	text_view.autoresizingMask = NSViewWidthSizable;
	text_view.font = [NSFont systemFontOfSize:15.0];
	text_view.allowsUndo = YES;
	text_view.richText = NO;
	text_view.importsGraphics = NO;
	text_view.delegate = self;
	text_view.textContainerInset = NSMakeSize(16.0, 5.0);
	text_view.textContainer.containerSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
	text_view.textContainer.widthTracksTextView = YES;
	scroll_view.documentView = text_view;

	NSProgressIndicator* progress_indicator = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
	progress_indicator.translatesAutoresizingMaskIntoConstraints = NO;
	progress_indicator.style = NSProgressIndicatorStyleSpinning;
	progress_indicator.indeterminate = YES;
	progress_indicator.controlSize = NSControlSizeSmall;
	progress_indicator.displayedWhenStopped = NO;
	progress_indicator.hidden = YES;

	NSButton* cancel_button = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancel:)];
	cancel_button.translatesAutoresizingMaskIntoConstraints = NO;
	cancel_button.bezelStyle = NSBezelStyleRounded;
	cancel_button.keyEquivalent = @"\x1B";
	cancel_button.keyEquivalentModifierMask = 0;

	NSButton* post_button = [NSButton buttonWithTitle:@"Post" target:self action:@selector(post:)];
	post_button.translatesAutoresizingMaskIntoConstraints = NO;
	post_button.bezelStyle = NSBezelStyleRounded;
	post_button.keyEquivalent = @"\r";
	post_button.keyEquivalentModifierMask = NSEventModifierFlagCommand;
	post_button.enabled = NO;

	[content_view addSubview:scroll_view];
	[content_view addSubview:progress_indicator];
	[content_view addSubview:cancel_button];
	[content_view addSubview:post_button];

	[NSLayoutConstraint activateConstraints:@[
		[scroll_view.topAnchor constraintEqualToAnchor:content_view.topAnchor],
		[scroll_view.leadingAnchor constraintEqualToAnchor:content_view.leadingAnchor],
		[scroll_view.trailingAnchor constraintEqualToAnchor:content_view.trailingAnchor],
		[scroll_view.bottomAnchor constraintEqualToAnchor:cancel_button.topAnchor constant:-16.0],
		[progress_indicator.leadingAnchor constraintEqualToAnchor:content_view.leadingAnchor constant:20.0],
		[progress_indicator.centerYAnchor constraintEqualToAnchor:cancel_button.centerYAnchor],
		[progress_indicator.widthAnchor constraintEqualToConstant:16.0],
		[progress_indicator.heightAnchor constraintEqualToConstant:16.0],
		[cancel_button.trailingAnchor constraintEqualToAnchor:post_button.leadingAnchor constant:-12.0],
		[cancel_button.bottomAnchor constraintEqualToAnchor:content_view.bottomAnchor constant:-20.0],
		[cancel_button.widthAnchor constraintEqualToAnchor:post_button.widthAnchor],
		[post_button.trailingAnchor constraintEqualToAnchor:content_view.trailingAnchor constant:-20.0],
		[post_button.bottomAnchor constraintEqualToAnchor:cancel_button.bottomAnchor]
	]];

	sheet_window.contentView = content_view;
	sheet_window.defaultButtonCell = post_button.cell;
	sheet_window.initialFirstResponder = text_view;

	self.window = sheet_window;
	self.textView = text_view;
	self.progressIndicator = progress_indicator;
	self.cancelButton = cancel_button;
	self.postButton = post_button;
}

- (void) resetWindowState
{
	self.isPosting = NO;
	self.textView.string = @"";
	self.textView.editable = YES;
	self.cancelButton.enabled = YES;
	[self.progressIndicator stopAnimation:nil];
	self.progressIndicator.hidden = YES;
	[self updatePostButtonEnabledState];
}

- (void) applyPrefillText:(NSString*) prefill_text
{
	self.textView.string = prefill_text ?: @"";
	NSRange selected_range = NSMakeRange(self.textView.string.length, 0);
	[self.textView setSelectedRange:selected_range];
	[self.textView scrollRangeToVisible:selected_range];
	[self updatePostButtonEnabledState];
}

- (void) updatePostButtonEnabledState
{
	self.postButton.enabled = (!self.isPosting && self.textView.string.length > 0);
}

- (void) closeReplyWindow
{
	[self.progressIndicator stopAnimation:nil];
	self.progressIndicator.hidden = YES;

	if (self.window.sheetParent != nil) {
		[self.window.sheetParent endSheet:self.window];
	}
	else {
		[self close];
	}
}

@end
