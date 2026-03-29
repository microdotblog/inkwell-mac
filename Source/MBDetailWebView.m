//
//  MBDetailWebView.m
//  Inkwell
//
//  Created by Codex on 3/29/26.
//

#import "MBDetailWebView.h"

static NSInteger const InkwellDetailDeleteHighlightContextMenuItemTag = 7100;
static NSInteger const InkwellDetailHighlightContextMenuItemTag = 7101;
static NSInteger const InkwellDetailHighlightContextMenuSeparatorTag = 7102;

@implementation MBDetailWebView

- (void) keyDown:(NSEvent*) event
{
	NSString* characters = event.charactersIgnoringModifiers ?: @"";
	if (characters.length > 0) {
		unichar key_code = [characters characterAtIndex:0];
		NSEventModifierFlags modifier_flags = (event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask);
		BOOL has_disallowed_modifiers = ((modifier_flags & (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl | NSEventModifierFlagShift)) != 0);
		BOOL is_left_arrow_key = (key_code == NSLeftArrowFunctionKey);
		if (!has_disallowed_modifiers && is_left_arrow_key && self.focusSidebarHandler != nil && self.focusSidebarHandler()) {
			return;
		}
	}

	[super keyDown:event];
}

- (void) scrollPageUp:(id) sender
{
	if (self.scrollPageUpHandler != nil && self.scrollPageUpHandler()) {
		return;
	}

	[super scrollPageUp:sender];
}

- (void) scrollPageDown:(id) sender
{
	if (self.scrollPageDownHandler != nil && self.scrollPageDownHandler()) {
		return;
	}

	[super scrollPageDown:sender];
}

- (void) scrollLineUp:(id) sender
{
	if (self.scrollPageUpHandler != nil && self.scrollPageUpHandler()) {
		return;
	}

	[super scrollLineUp:sender];
}

- (void) scrollLineDown:(id) sender
{
	if (self.scrollPageDownHandler != nil && self.scrollPageDownHandler()) {
		return;
	}

	[super scrollLineDown:sender];
}

- (void) willOpenMenu:(NSMenu*) menu withEvent:(NSEvent*) event
{
	[super willOpenMenu:menu withEvent:event];
	#pragma unused(event)

	if (menu == nil) {
		return;
	}

	while ([menu indexOfItemWithTag:InkwellDetailDeleteHighlightContextMenuItemTag] != -1) {
		NSInteger existing_index = [menu indexOfItemWithTag:InkwellDetailDeleteHighlightContextMenuItemTag];
		[menu removeItemAtIndex:existing_index];
	}

	while ([menu indexOfItemWithTag:InkwellDetailHighlightContextMenuItemTag] != -1) {
		NSInteger existing_index = [menu indexOfItemWithTag:InkwellDetailHighlightContextMenuItemTag];
		[menu removeItemAtIndex:existing_index];
	}

	while ([menu indexOfItemWithTag:InkwellDetailHighlightContextMenuSeparatorTag] != -1) {
		NSInteger existing_index = [menu indexOfItemWithTag:InkwellDetailHighlightContextMenuSeparatorTag];
		[menu removeItemAtIndex:existing_index];
	}

	BOOL should_show_delete_highlight_item = NO;
	if (self.shouldShowDeleteHighlightMenuItemHandler != nil) {
		should_show_delete_highlight_item = self.shouldShowDeleteHighlightMenuItemHandler();
	}

	BOOL should_show_highlight_item = NO;
	if (self.shouldShowHighlightMenuItemHandler != nil) {
		should_show_highlight_item = self.shouldShowHighlightMenuItemHandler();
	}
	if (!should_show_delete_highlight_item && !should_show_highlight_item) {
		return;
	}

	NSMenuItem* separator_item = [NSMenuItem separatorItem];
	separator_item.tag = InkwellDetailHighlightContextMenuSeparatorTag;

	[menu insertItem:separator_item atIndex:0];
	if (should_show_highlight_item) {
		SEL highlight_selector = NSSelectorFromString(@"highlightSelectedItem:");
		NSMenuItem* highlight_item = [[NSMenuItem alloc] initWithTitle:@"Highlight" action:highlight_selector keyEquivalent:@""];
		highlight_item.target = nil;
		highlight_item.tag = InkwellDetailHighlightContextMenuItemTag;
		highlight_item.image = [NSImage imageWithSystemSymbolName:@"highlighter" accessibilityDescription:@"Highlight"];
		[menu insertItem:highlight_item atIndex:0];
	}
	if (should_show_delete_highlight_item) {
		NSMenuItem* delete_item = [[NSMenuItem alloc] initWithTitle:@"Delete Highlight" action:@selector(deleteHoveredHighlight:) keyEquivalent:@""];
		delete_item.target = self;
		delete_item.tag = InkwellDetailDeleteHighlightContextMenuItemTag;
		[menu insertItem:delete_item atIndex:0];
	}
}

- (IBAction) deleteHoveredHighlight:(id) sender
{
	#pragma unused(sender)
	if (self.deleteHoveredHighlightHandler == nil) {
		return;
	}

	self.deleteHoveredHighlightHandler();
}

@end
