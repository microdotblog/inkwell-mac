//
//  MBSidebarTableView.m
//  Inkwell
//
//  Created by Codex on 3/31/26.
//

#import "MBSidebarTableView.h"

@interface MBSidebarTableView ()
@property (copy) NSArray* rowIdentifiers;
@end

@implementation MBSidebarTableView

- (void) updateRowIdentifiers:(NSArray *)rowIdentifiers
{
	if (self.rowIdentifiers == nil) {
		self.rowIdentifiers = rowIdentifiers;
		[self reloadData];
		return;
	}

	NSMutableArray* current_identifiers = [self.rowIdentifiers mutableCopy];
	NSSet* new_identifiers = [NSSet setWithArray:rowIdentifiers];
	NSClipView* clip_view = self.enclosingScrollView.contentView;
	NSRange visible_rows = [self rowsInRect:clip_view.bounds];
	NSInteger top_row = visible_rows.length > 0 ? (NSInteger) visible_rows.location : -1;
	id top_identifier = (top_row >= 0 && top_row < current_identifiers.count) ? current_identifiers[(NSUInteger) top_row] : nil;
	CGFloat top_offset = (top_row >= 0) ? NSMinY(clip_view.bounds) - NSMinY([self rectOfRow:top_row]) : 0.0;
	self.rowIdentifiers = rowIdentifiers;

	// Keep surviving row views, their selection, and their highlight throughout refresh.
	[NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
		context.duration = 0.0;
		context.allowsImplicitAnimation = NO;
		[self beginUpdates];
		NSMutableIndexSet* removed_indexes = [NSMutableIndexSet indexSet];
		[current_identifiers enumerateObjectsUsingBlock:^(id identifier, NSUInteger index, BOOL* stop) {
			if (![new_identifiers containsObject:identifier]) {
				[removed_indexes addIndex:index];
			}
		}];
		[current_identifiers removeObjectsAtIndexes:removed_indexes];
		[self removeRowsAtIndexes:removed_indexes withAnimation:NSTableViewAnimationEffectNone];
		for (NSUInteger index = 0; index < rowIdentifiers.count; index++) {
			id identifier = rowIdentifiers[index];
			if (index < current_identifiers.count && [current_identifiers[index] isEqual:identifier]) {
				continue;
			}
			NSUInteger old_index = [current_identifiers indexOfObject:identifier];
			if (old_index == NSNotFound) {
				[current_identifiers insertObject:identifier atIndex:index];
				[self insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:index] withAnimation:NSTableViewAnimationEffectNone];
			}
			else {
				[current_identifiers removeObjectAtIndex:old_index];
				[current_identifiers insertObject:identifier atIndex:index];
				[self moveRowAtIndex:(NSInteger) old_index toIndex:(NSInteger) index];
			}
		}
		[self endUpdates];
		[self noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, rowIdentifiers.count)]];
		[self layoutSubtreeIfNeeded];
		NSUInteger new_top_row = top_identifier != nil ? [rowIdentifiers indexOfObject:top_identifier] : NSNotFound;
		if (clip_view != nil && new_top_row != NSNotFound) {
			NSPoint origin = clip_view.bounds.origin;
			origin.y = NSMinY([self rectOfRow:(NSInteger) new_top_row]) + top_offset;
			[clip_view scrollToPoint:[clip_view constrainBoundsRect:NSMakeRect(origin.x, origin.y, NSWidth(clip_view.bounds), NSHeight(clip_view.bounds))].origin];
			[self.enclosingScrollView reflectScrolledClipView:clip_view];
		}
	} completionHandler:nil];
}

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
