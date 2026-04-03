//
//  MBPhotoZoomController.m
//  Inkwell
//
//  Created by Codex on 4/3/26.
//

#import "MBPhotoZoomController.h"

static NSToolbarItemIdentifier const InkwellPhotoToolbarZoomOutIdentifier = @"InkwellPhotoToolbarZoomOut";
static NSToolbarItemIdentifier const InkwellPhotoToolbarZoomInIdentifier = @"InkwellPhotoToolbarZoomIn";
static NSString* const InkwellPhotoWindowAutosaveName = @"PhotoWindow";
static CGFloat const InkwellPhotoWindowDefaultWidth = 500.0;
static CGFloat const InkwellPhotoWindowDefaultHeight = 500.0;
static CGFloat const InkwellPhotoWindowMinWidth = 280.0;
static CGFloat const InkwellPhotoWindowMinHeight = 240.0;
static CGFloat const InkwellPhotoMinimumZoomScale = 0.1;
static CGFloat const InkwellPhotoMaximumZoomScale = 8.0;
static CGFloat const InkwellPhotoZoomStep = 1.25;

@interface MBPhotoZoomController () <NSToolbarDelegate, NSToolbarItemValidation, NSWindowDelegate>

@property (nonatomic, strong) NSScrollView* scrollView;
@property (nonatomic, strong) NSView* canvasView;
@property (nonatomic, strong) NSImageView* imageView;
@property (nonatomic, strong) NSProgressIndicator* progressIndicator;
@property (nonatomic, strong, nullable) NSURLSessionDataTask* imageTask;
@property (nonatomic, strong, nullable) NSURL* imageURL;
@property (nonatomic, assign) NSSize imageSize;
@property (nonatomic, assign) CGFloat zoomScale;
@property (nonatomic, assign) BOOL didSetupContent;

- (void) setupWindowIfNeeded;
- (void) setupContentIfNeeded;
- (void) loadImageURL:(NSURL *)image_url;
- (void) updateWindowTitle;
- (NSString *) titleForImageURL:(NSURL *)image_url;
- (void) setLoading:(BOOL) is_loading;
- (void) applyLoadedImage:(NSImage *)image;
- (CGFloat) defaultZoomScaleForImageSize:(NSSize) image_size;
- (void) updateImageLayout;
- (IBAction) zoomOut:(id) sender;
- (IBAction) zoomIn:(id) sender;

@end

@implementation MBPhotoZoomController

- (instancetype) init
{
	self = [super initWithWindow:nil];
	if (self) {
		self.zoomScale = 1.0;
		self.imageSize = NSZeroSize;
	}
	return self;
}

- (void) dealloc
{
	[self.imageTask cancel];
}

- (void) showWindowForImageURL:(NSURL *)image_url
{
	if (image_url == nil) {
		return;
	}

	[self setupWindowIfNeeded];
	[self setupContentIfNeeded];
	[super showWindow:nil];
	[self.window makeKeyAndOrderFront:nil];
	[NSApp activateIgnoringOtherApps:YES];
	[self loadImageURL:image_url];
}

- (void) setupWindowIfNeeded
{
	if (self.window != nil) {
		return;
	}

	NSRect frame = NSMakeRect(0.0, 0.0, InkwellPhotoWindowDefaultWidth, InkwellPhotoWindowDefaultHeight);
	NSUInteger style_mask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
	NSWindow* window = [[NSWindow alloc] initWithContentRect:frame styleMask:style_mask backing:NSBackingStoreBuffered defer:NO];
	window.releasedWhenClosed = NO;
	window.minSize = NSMakeSize(InkwellPhotoWindowMinWidth, InkwellPhotoWindowMinHeight);
	window.toolbarStyle = NSWindowToolbarStyleUnified;
	window.delegate = self;

	NSToolbar* toolbar = [[NSToolbar alloc] initWithIdentifier:@"InkwellPhotoToolbar"];
	toolbar.delegate = self;
	toolbar.allowsUserCustomization = NO;
	toolbar.autosavesConfiguration = NO;
	toolbar.displayMode = NSToolbarDisplayModeIconOnly;
	window.toolbar = toolbar;

	self.window = window;
	[self updateWindowTitle];

	BOOL did_restore_frame = [self.window setFrameUsingName:InkwellPhotoWindowAutosaveName];
	[self.window setFrameAutosaveName:InkwellPhotoWindowAutosaveName];
	if (!did_restore_frame) {
		[self.window center];
	}
}

- (void) setupContentIfNeeded
{
	if (self.didSetupContent) {
		return;
	}

	NSView* content_view = self.window.contentView;
	if (content_view == nil) {
		return;
	}

	NSScrollView* scroll_view = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	scroll_view.translatesAutoresizingMaskIntoConstraints = NO;
	scroll_view.drawsBackground = NO;
	scroll_view.borderType = NSNoBorder;
	scroll_view.hasVerticalScroller = YES;
	scroll_view.hasHorizontalScroller = YES;
	scroll_view.autohidesScrollers = YES;

	NSView* canvas_view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, InkwellPhotoWindowDefaultWidth, InkwellPhotoWindowDefaultHeight)];

	NSImageView* image_view = [[NSImageView alloc] initWithFrame:NSZeroRect];
	image_view.imageScaling = NSImageScaleProportionallyUpOrDown;
	[canvas_view addSubview:image_view];
	scroll_view.documentView = canvas_view;

	NSProgressIndicator* progress_indicator = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
	progress_indicator.translatesAutoresizingMaskIntoConstraints = NO;
	progress_indicator.style = NSProgressIndicatorStyleSpinning;
	progress_indicator.controlSize = NSControlSizeRegular;
	progress_indicator.displayedWhenStopped = NO;

	[content_view addSubview:scroll_view];
	[content_view addSubview:progress_indicator];
	[NSLayoutConstraint activateConstraints:@[
		[scroll_view.topAnchor constraintEqualToAnchor:content_view.topAnchor],
		[scroll_view.bottomAnchor constraintEqualToAnchor:content_view.bottomAnchor],
		[scroll_view.leadingAnchor constraintEqualToAnchor:content_view.leadingAnchor],
		[scroll_view.trailingAnchor constraintEqualToAnchor:content_view.trailingAnchor],
		[progress_indicator.centerXAnchor constraintEqualToAnchor:content_view.centerXAnchor],
		[progress_indicator.centerYAnchor constraintEqualToAnchor:content_view.centerYAnchor]
	]];

	self.scrollView = scroll_view;
	self.canvasView = canvas_view;
	self.imageView = image_view;
	self.progressIndicator = progress_indicator;
	self.didSetupContent = YES;
}

- (void) loadImageURL:(NSURL *)image_url
{
	self.imageURL = image_url;
	[self updateWindowTitle];
	[self.imageTask cancel];
	self.imageTask = nil;

	self.imageView.image = nil;
	self.imageSize = NSZeroSize;
	self.zoomScale = 1.0;
	[self updateImageLayout];
	[self setLoading:YES];

	NSURLRequest* request = [NSURLRequest requestWithURL:image_url cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:60.0];
	__weak typeof(self) weak_self = self;
	NSURLSessionDataTask* image_task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
		#pragma unused(response)
		dispatch_async(dispatch_get_main_queue(), ^{
			MBPhotoZoomController* strong_self = weak_self;
			if (strong_self == nil || ![strong_self.imageURL isEqual:image_url]) {
				return;
			}

			strong_self.imageTask = nil;
			[strong_self setLoading:NO];
			if (error != nil || data.length == 0) {
				return;
			}

			NSImage* image = [[NSImage alloc] initWithData:data];
			if (image == nil) {
				return;
			}

			[strong_self applyLoadedImage:image];
		});
	}];

	self.imageTask = image_task;
	[image_task resume];
}

- (void) updateWindowTitle
{
	self.window.title = [self titleForImageURL:self.imageURL];
}

- (NSString *) titleForImageURL:(NSURL *)image_url
{
	NSString* host_string = [[image_url.host ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
	if (host_string.length > 0) {
		return host_string;
	}

	NSString* absolute_string = [[image_url.absoluteString ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
	if (absolute_string.length > 0) {
		return absolute_string;
	}

	return @"Photo";
}

- (void) setLoading:(BOOL) is_loading
{
	if (is_loading) {
		self.progressIndicator.hidden = NO;
		[self.progressIndicator startAnimation:nil];
	}
	else {
		[self.progressIndicator stopAnimation:nil];
		self.progressIndicator.hidden = YES;
	}
}

- (void) applyLoadedImage:(NSImage *)image
{
	self.imageView.image = image;
	self.imageSize = image.size;
	if (self.imageSize.width <= 0.0 || self.imageSize.height <= 0.0) {
		self.imageSize = NSMakeSize(1.0, 1.0);
	}

	self.zoomScale = [self defaultZoomScaleForImageSize:self.imageSize];
	[self updateImageLayout];
}

- (CGFloat) defaultZoomScaleForImageSize:(NSSize) image_size
{
	NSSize viewport_size = self.scrollView.contentSize;
	if (image_size.width <= 0.0 || image_size.height <= 0.0 || viewport_size.width <= 0.0 || viewport_size.height <= 0.0) {
		return 1.0;
	}

	CGFloat width_scale = viewport_size.width / image_size.width;
	CGFloat height_scale = viewport_size.height / image_size.height;
	CGFloat fit_scale = MIN(width_scale, height_scale);
	if (!isfinite(fit_scale) || fit_scale <= 0.0) {
		return 1.0;
	}

	return MAX(InkwellPhotoMinimumZoomScale, MIN(1.0, fit_scale));
}

- (void) updateImageLayout
{
	if (!self.didSetupContent || self.canvasView == nil || self.imageView == nil || self.scrollView == nil) {
		return;
	}

	NSSize viewport_size = self.scrollView.contentSize;
	if (viewport_size.width <= 0.0 || viewport_size.height <= 0.0) {
		viewport_size = self.window.contentView.bounds.size;
	}

	if (self.imageView.image == nil || self.imageSize.width <= 0.0 || self.imageSize.height <= 0.0) {
		self.canvasView.frame = NSMakeRect(0.0, 0.0, MAX(1.0, viewport_size.width), MAX(1.0, viewport_size.height));
		self.imageView.frame = NSZeroRect;
		return;
	}

	CGFloat scaled_width = MAX(1.0, round(self.imageSize.width * self.zoomScale));
	CGFloat scaled_height = MAX(1.0, round(self.imageSize.height * self.zoomScale));
	NSSize canvas_size = NSMakeSize(MAX(viewport_size.width, scaled_width), MAX(viewport_size.height, scaled_height));
	CGFloat image_x = floor((canvas_size.width - scaled_width) / 2.0);
	CGFloat image_y = floor((canvas_size.height - scaled_height) / 2.0);

	self.canvasView.frame = NSMakeRect(0.0, 0.0, canvas_size.width, canvas_size.height);
	self.imageView.frame = NSMakeRect(image_x, image_y, scaled_width, scaled_height);
}

- (IBAction) zoomOut:(id) sender
{
	#pragma unused(sender)
	if (self.imageView.image == nil) {
		return;
	}

	self.zoomScale = MAX(InkwellPhotoMinimumZoomScale, self.zoomScale / InkwellPhotoZoomStep);
	[self updateImageLayout];
}

- (IBAction) zoomIn:(id) sender
{
	#pragma unused(sender)
	if (self.imageView.image == nil) {
		return;
	}

	self.zoomScale = MIN(InkwellPhotoMaximumZoomScale, self.zoomScale * InkwellPhotoZoomStep);
	[self updateImageLayout];
}

- (void) windowDidResize:(NSNotification *)notification
{
	#pragma unused(notification)
	[self updateImageLayout];
}

- (BOOL) validateToolbarItem:(NSToolbarItem *)toolbar_item
{
	BOOL has_image = (self.imageView.image != nil);
	if ([toolbar_item.itemIdentifier isEqualToString:InkwellPhotoToolbarZoomOutIdentifier]) {
		return (has_image && self.zoomScale > (InkwellPhotoMinimumZoomScale + 0.001));
	}
	if ([toolbar_item.itemIdentifier isEqualToString:InkwellPhotoToolbarZoomInIdentifier]) {
		return (has_image && self.zoomScale < (InkwellPhotoMaximumZoomScale - 0.001));
	}

	return has_image;
}

- (NSArray<NSToolbarItemIdentifier> *) toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
	#pragma unused(toolbar)
	return @[
		InkwellPhotoToolbarZoomOutIdentifier,
		InkwellPhotoToolbarZoomInIdentifier,
		NSToolbarFlexibleSpaceItemIdentifier
	];
}

- (NSArray<NSToolbarItemIdentifier> *) toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
	#pragma unused(toolbar)
	return @[
		InkwellPhotoToolbarZoomOutIdentifier,
		InkwellPhotoToolbarZoomInIdentifier
	];
}

- (NSToolbarItem *) toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)item_identifier willBeInsertedIntoToolbar:(BOOL)flag
{
	#pragma unused(toolbar)
	#pragma unused(flag)

	NSToolbarItem* item = [[NSToolbarItem alloc] initWithItemIdentifier:item_identifier];
	if ([item_identifier isEqualToString:InkwellPhotoToolbarZoomOutIdentifier]) {
		item.label = @"Zoom Out";
		item.paletteLabel = @"Zoom Out";
		item.target = self;
		item.action = @selector(zoomOut:);
		item.image = [NSImage imageWithSystemSymbolName:@"minus.magnifyingglass" accessibilityDescription:@"Zoom Out"];
		return item;
	}
	if ([item_identifier isEqualToString:InkwellPhotoToolbarZoomInIdentifier]) {
		item.label = @"Zoom In";
		item.paletteLabel = @"Zoom In";
		item.target = self;
		item.action = @selector(zoomIn:);
		item.image = [NSImage imageWithSystemSymbolName:@"plus.magnifyingglass" accessibilityDescription:@"Zoom In"];
		return item;
	}

	return item;
}

@end
