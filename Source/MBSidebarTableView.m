//
//  MBSidebarTableView.m
//  Inkwell
//
//  Created by Codex on 3/31/26.
//

#import "MBSidebarTableView.h"

@implementation MBSidebarTableView

- (void) keyDown:(NSEvent*) event
{
	NSString* characters = event.charactersIgnoringModifiers ?: @"";
	if (characters.length > 0) {
		unichar key_code = [characters characterAtIndex:0];
		NSEventModifierFlags modifier_flags = (event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask);
		BOOL has_disallowed_modifiers = ((modifier_flags & (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl | NSEventModifierFlagShift)) != 0);
		BOOL is_return_key = (key_code == NSCarriageReturnCharacter || key_code == NSNewlineCharacter || key_code == NSEnterCharacter);
		if (is_return_key && self.primaryActionHandler != nil && self.primaryActionHandler()) {
			return;
		}

		BOOL is_right_arrow_key = (key_code == NSRightArrowFunctionKey);
		if (!has_disallowed_modifiers && is_right_arrow_key && self.focusDetailHandler != nil && self.focusDetailHandler()) {
			return;
		}

		BOOL is_up_arrow_key = (key_code == NSUpArrowFunctionKey);
		BOOL is_down_arrow_key = (key_code == NSDownArrowFunctionKey);
		if (!has_disallowed_modifiers && self.selectedRow < 0 && (is_up_arrow_key || is_down_arrow_key) && self.moveSelectionFromRememberedRowHandler != nil) {
			NSInteger direction = is_down_arrow_key ? 1 : -1;
			if (self.moveSelectionFromRememberedRowHandler(direction)) {
				return;
			}
		}
	}

	[super keyDown:event];
}

- (BOOL) becomeFirstResponder
{
	BOOL did_become_first_responder = [super becomeFirstResponder];
	if (did_become_first_responder && self.focusChangedHandler != nil) {
		self.focusChangedHandler();
	}

	return did_become_first_responder;
}

- (BOOL) resignFirstResponder
{
	BOOL did_resign_first_responder = [super resignFirstResponder];
	if (did_resign_first_responder && self.focusChangedHandler != nil) {
		self.focusChangedHandler();
	}

	return did_resign_first_responder;
}

- (NSMenu*) menuForEvent:(NSEvent*) event
{
	if (self.contextMenuHandler == nil) {
		return [super menuForEvent:event];
	}

	NSPoint point_in_window = event.locationInWindow;
	NSPoint point_in_table = [self convertPoint:point_in_window fromView:nil];
	NSInteger row = [self rowAtPoint:point_in_table];
	if (row < 0 || row >= self.numberOfRows) {
		return nil;
	}

	NSIndexSet* index_set = [NSIndexSet indexSetWithIndex:(NSUInteger) row];
	[self selectRowIndexes:index_set byExtendingSelection:NO];

	NSMenu* menu = self.contextMenuHandler();
	if (menu != nil) {
		return menu;
	}

	return [super menuForEvent:event];
}

@end
