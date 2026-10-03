#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "MBSidebarController.h"
#import "MBSidebarTableView.h"
#import "MBSidebarRowView.h"
#import "MBSidebarCell.h"
#import "MBRoundedImageView.h"
#import "MBEntry.h"
#import "MBMention.h"
#import "MBAvatarLoader.h"
#import "MBPathUtilities.h"
#import "MBClient.h"

// Other panes and external services are excluded; selection uses the real AppKit views.
#define STUB_CONTROLLER(name) @interface name : NSObject @end @implementation name @end
STUB_CONTROLLER(MBPodcastController)
STUB_CONTROLLER(MBReplyController)

NSNotificationName const MBAvatarLoaderDidLoadImageNotification = @"TestAvatarLoaded";
NSString* const MBAvatarLoaderURLStringUserInfoKey = @"url";
@implementation MBAvatarLoader
+ (instancetype) sharedLoader
{
	return [[self alloc] init];
}
+ (void) cleanupCachedImageFiles
{
}
- (NSImage *) cachedImageForURLString:(NSString *)urlString
{
	return nil;
}
- (void) loadImageForURLString:(NSString *)urlString
{
}
@end

@implementation MBPathUtilities
+ (NSURL *) appContainerDirectoryURLForSearchPathDirectory:(NSSearchPathDirectory)directory createIfNeeded:(BOOL)createIfNeeded
{
	return nil;
}
+ (NSURL *) appSubdirectoryURLForSearchPathDirectory:(NSSearchPathDirectory)directory relativePath:(NSString *)relativePath createIfNeeded:(BOOL)createIfNeeded
{
	return nil;
}
+ (NSURL *) appFileURLForSearchPathDirectory:(NSSearchPathDirectory)directory filename:(NSString *)filename createDirectoryIfNeeded:(BOOL)createIfNeeded
{
	return nil;
}
+ (void) cleanupLegacyFiles
{
}
+ (void) clearUserScopedCacheFiles
{
}
@end

static NSUserDefaults* test_defaults;
static NSUInteger check_count;
@interface NSUserDefaults (SidebarTests)
+ (NSUserDefaults *) sidebarTestDefaults;
@end
@implementation NSUserDefaults (SidebarTests)
+ (NSUserDefaults *) sidebarTestDefaults
{
	return test_defaults;
}
@end

@interface MBSidebarController (SidebarTests)
- (void) applyFiltersAndReload;
- (void) refreshVisibleRows;
- (void) reloadRowForEntryID:(NSInteger)entryID preferredRow:(NSInteger)row;
- (void) deselectSidebarSelectionPreservingDetail;
- (BOOL) moveSelectionFromRememberedRow:(NSInteger)direction;
- (NSInteger) rowForEntryID:(NSInteger)entryID;
- (NSArray *) sidebarItemsForMentions:(NSArray *)mentions;
@end

@interface TestTableView : MBSidebarTableView
@property (assign) NSUInteger fullReloads;
@property (assign) NSUInteger cellReloads;
@end
@implementation TestTableView
- (void) reloadData
{
	self.fullReloads += 1;
	[super reloadData];
}
- (void) reloadDataForRowIndexes:(NSIndexSet *)rowIndexes columnIndexes:(NSIndexSet *)columnIndexes
{
	self.cellReloads += 1;
	[super reloadDataForRowIndexes:rowIndexes columnIndexes:columnIndexes];
}
@end

@interface TestSidebarController : MBSidebarController
@property (strong) TestTableView* testTable;
@end
@implementation TestSidebarController
- (void) loadView
{
	NSScrollView* scroll_view = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 350, 800)];
	scroll_view.hasVerticalScroller = YES;
	TestTableView* table_view = [[TestTableView alloc] initWithFrame:scroll_view.bounds];
	table_view.headerView = nil;
	table_view.style = NSTableViewStyleSourceList;
	table_view.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
	table_view.intercellSpacing = NSMakeSize(0, 5);
	NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"SourceColumn"];
	column.width = 340;
	[table_view addTableColumn:column];
	table_view.delegate = (id) self;
	table_view.dataSource = (id) self;
	scroll_view.documentView = table_view;
	self.testTable = table_view;
	[self setValue:table_view forKey:@"tableView"];
	[self setValue:scroll_view forKey:@"tableScrollView"];
	self.view = scroll_view;
}
- (void) updateRecapUI
{
}
- (void) updatePremiumRequiredView
{
}
- (void) updatePodcastPaneForSelectedItem:(MBEntry *)item
{
}
@end

@interface TestReadClient : MBClient
@property (copy) void (^pendingCompletion)(NSError* error);
@end
@implementation TestReadClient
- (void) markAsRead:(NSInteger)entryID token:(NSString *)token completion:(void (^)(NSError* error))completion
{
	self.pendingCompletion = completion;
}
@end

static void Check(BOOL condition, NSString* message)
{
	check_count += 1;
	if (!condition) {
		fprintf(stderr, "FAIL: %s\n", message.UTF8String);
		exit(1);
	}
}

static void DrainEvents(void)
{
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.025]];
}

static NSArray* Entries(NSArray* identifiers)
{
	NSMutableArray* entries = [NSMutableArray array];
	for (NSNumber* identifier in identifiers) {
		MBEntry* entry = [[MBEntry alloc] init];
		entry.entryID = identifier.integerValue;
		entry.title = [NSString stringWithFormat:@"Entry %@", identifier];
		entry.summary = @"A sidebar refresh should keep this row selected.";
		entry.url = [NSString stringWithFormat:@"https://example.com/%@", identifier];
		entry.date = [[[NSCalendar currentCalendar] startOfDayForDate:[NSDate date]] dateByAddingTimeInterval:3600.0 - entries.count];
		entry.isRead = YES;
		[entries addObject:entry];
	}
	return entries;
}

static void Refresh(TestSidebarController* controller, NSArray* identifiers)
{
	// Distinct dates keep the supplied order with the default newest-first sort.
	NSArray* entries = Entries(identifiers);
	NSInteger mode = [[controller valueForKey:@"contentMode"] integerValue];
	if (mode == 1) {
		for (MBEntry* entry in entries) { entry.isBookmarkEntry = YES; }
		[controller setValue:entries forKey:@"bookmarkItems"];
	}
	else if (mode == 3) {
		[controller setValue:entries forKey:@"allPostsItems"];
	}
	else {
		[controller setValue:entries forKey:@"allItems"];
	}
	[controller applyFiltersAndReload];
	[controller.testTable layoutSubtreeIfNeeded];
}

static void SelectEntry(TestSidebarController* controller, NSInteger entryID)
{
	NSInteger row = [controller rowForEntryID:entryID];
	Check(row >= 0, @"Entry exists before selecting it.");
	[controller.testTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger) row] byExtendingSelection:NO];
	[controller.testTable scrollRowToVisible:row];
	[controller.testTable layoutSubtreeIfNeeded];
}

static NSBitmapImageRep* Snapshot(NSView* view)
{
	[view layoutSubtreeIfNeeded];
	NSBitmapImageRep* bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
	[view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
	return bitmap;
}

static void TestRefresh(TestSidebarController* controller)
{
	Refresh(controller, @[ @1, @2, @3, @4 ]);
	SelectEntry(controller, 2);
	DrainEvents();
	TestTableView* table_view = controller.testTable;
	NSInteger selected_row = table_view.selectedRow;
	MBSidebarRowView* row_view = (id) [table_view rowViewAtRow:selected_row makeIfNecessary:YES];
	MBSidebarCell* cell_view = [table_view viewAtColumn:0 row:selected_row makeIfNecessary:YES];
	NSColor* title_color = cell_view.titleTextField.textColor;
	BOOL was_emphasized = row_view.isEmphasized;
	NSResponder* first_responder = table_view.window.firstResponder;
	NSBitmapImageRep* before = Snapshot(row_view);
	const char* snapshot_directory = getenv("INKWELL_SIDEBAR_SNAPSHOT_DIR");
	if (snapshot_directory != NULL) {
		NSString* path = [[NSString stringWithUTF8String:snapshot_directory] stringByAppendingPathComponent:[controller.view.effectiveAppearance.name stringByAppendingString:@".png"]];
		[[before representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
	}
	NSUInteger initial_reloads = table_view.fullReloads;
	__block NSMutableArray* notified_ids = [NSMutableArray array];
	controller.selectionChangedHandler = ^(MBEntry* item) { [notified_ids addObject:@(item.entryID)]; };
	for (NSUInteger index = 0; index < 5; index++) {
		Refresh(controller, @[ @1, @2, @3, @4 ]);
		DrainEvents();
		Check(controller.selectedItem.entryID == 2, @"Unchanged refresh retains the selected entry.");
		Check(table_view.window.firstResponder == first_responder, @"Refresh preserves keyboard focus.");
		Check(row_view.isEmphasized == was_emphasized, @"Refresh preserves the selection's emphasis.");
		Check([table_view rowViewAtRow:table_view.selectedRow makeIfNecessary:NO] == row_view, @"Refresh retains the selected row view.");
		Check([table_view viewAtColumn:0 row:table_view.selectedRow makeIfNecessary:NO] == cell_view, @"Refresh retains the selected cell view.");
		Check([cell_view.titleTextField.textColor isEqual:title_color], @"Refresh does not change the selected text color.");
		NSBitmapImageRep* after = Snapshot(row_view);
		Check([[before representationUsingType:NSBitmapImageFileTypePNG properties:@{}] isEqual:[after representationUsingType:NSBitmapImageFileTypePNG properties:@{}]], @"Unchanged refresh draws identical selected-row pixels.");
	}
	Check(notified_ids.count == 0, @"Unchanged refreshes do not reload or clear the detail pane.");
	Check(table_view.fullReloads == initial_reloads && table_view.cellReloads == 0, @"Refresh and styling do not reload the table or its cells.");
	NSMutableArray* changed_entries = [Entries(@[ @1, @2, @3, @4 ]) mutableCopy];
	[(MBEntry*) changed_entries[1] setText:@"Updated article body"];
	[controller setValue:changed_entries forKey:@"allItems"];
	[controller applyFiltersAndReload];
	Check([notified_ids isEqual:@[ @2 ]], @"Changed article content updates the detail exactly once.");
	[notified_ids removeAllObjects];
	Refresh(controller, @[ @9, @1, @2, @3, @4 ]);
	Check(controller.selectedItem.entryID == 2, @"Inserting before selection preserves the entry.");
	Check([table_view rowViewAtRow:table_view.selectedRow makeIfNecessary:YES] == row_view, @"Inserting before selection retains its row view.");
	Refresh(controller, @[ @4, @2, @9, @3 ]);
	Check(controller.selectedItem.entryID == 2, @"Removing and moving surrounding rows preserves the entry.");
	Check([table_view rowViewAtRow:table_view.selectedRow makeIfNecessary:YES] == row_view, @"Reordering retains the selected row view.");
	SelectEntry(controller, 3);
	DrainEvents();
	Check(controller.selectedItem.entryID == 3, @"No deferred restore can overwrite a newer selection.");
	[notified_ids removeAllObjects];
	Refresh(controller, @[ @4, @2, @9 ]);
	Check(table_view.selectedRow == -1, @"Removing the selected entry clears actual selection.");
	Check([notified_ids isEqual:@[ @0 ]], @"Removing selection notifies the detail exactly once.");
	controller.selectionChangedHandler = nil;
}

static void TestAppearance(TestSidebarController* controller)
{
	Refresh(controller, @[ @1, @2, @3 ]);
	SelectEntry(controller, 2);
	TestTableView* table_view = controller.testTable;
	MBSidebarRowView* row_view = (id) [table_view rowViewAtRow:table_view.selectedRow makeIfNecessary:YES];
	MBSidebarCell* cell_view = [table_view viewAtColumn:0 row:table_view.selectedRow makeIfNecessary:YES];
	row_view.emphasized = YES;
	Check([cell_view.titleTextField.textColor isEqual:[NSColor alternateSelectedControlTextColor]], @"Emphasized row updates selected text immediately.");
	row_view.emphasized = NO;
	Check([cell_view.titleTextField.textColor isEqual:[NSColor unemphasizedSelectedTextColor]], @"Unemphasized row updates selected text immediately.");
	Check(cell_view.avatarView.alphaValue == 1.0, @"A selected read entry has a full-opacity avatar.");
	[cell_view.effectiveAppearance performAsCurrentDrawingAppearance:^{
		NSColor* title_color = [cell_view.titleTextField.textColor colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
		NSColor* subtitle_color = [cell_view.subtitleTextField.textColor colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
		Check(fabs(title_color.redComponent - subtitle_color.redComponent) < 0.001, @"Selected secondary text uses the same light/dark foreground as the title.");
		Check(fabs(subtitle_color.alphaComponent - 0.78) < 0.001, @"Selected secondary text retains its intended opacity.");
	}];
	NSUInteger reloads = table_view.fullReloads;
	[controller refreshVisibleRows];
	[controller reloadRowForEntryID:2 preferredRow:0];
	Check(table_view.fullReloads == reloads && table_view.cellReloads == 0, @"Avatar and read updates preserve row and cell views.");
	Check([table_view viewAtColumn:0 row:table_view.selectedRow makeIfNecessary:NO] == cell_view, @"Content updates retain the selected cell.");
	[controller deselectSidebarSelectionPreservingDetail];
	Check(cell_view.avatarView.alphaValue == 0.35, @"Deselecting restores read styling immediately.");
	Check([cell_view.titleTextField.textColor isEqual:[NSColor disabledControlTextColor]], @"Deselecting restores the read text color.");
	[test_defaults removeObjectForKey:InkwellSidebarSelectedEntryIDDefaultsKey];
	[controller setValue:@2 forKey:@"rememberedDeselectedEntryID"];
	Refresh(controller, @[ @9, @1, @2, @3 ]);
	Check(table_view.selectedRow == -1, @"Refresh preserves intentional deselection after marking unread.");
	Check([controller moveSelectionFromRememberedRow:1] && controller.selectedItem.entryID == 3, @"Arrow navigation follows the remembered entry after insertion.");
}

static void TestLists(TestSidebarController* controller)
{
	[test_defaults setInteger:2 forKey:InkwellSidebarSelectedEntryIDDefaultsKey];
	for (NSNumber* mode in @[ @1, @3 ]) {
		[controller setValue:mode forKey:@"contentMode"];
		Refresh(controller, @[ @1, @2, @3 ]);
		SelectEntry(controller, 3);
		Refresh(controller, @[ @9, @1, @2, @3 ]);
		Check(controller.selectedItem.entryID == 3, @"Bookmarks and posts retain selection during refresh.");
		Check([test_defaults integerForKey:InkwellSidebarSelectedEntryIDDefaultsKey] == 2, @"Special lists preserve the saved feed selection.");
	}
	[controller setValue:@2 forKey:@"contentMode"];
	NSMutableArray* mentions = [NSMutableArray array];
	for (NSNumber* identifier in @[ @1, @2, @3 ]) {
		MBMention* mention = [[MBMention alloc] init];
		mention.postID = identifier.stringValue;
		mention.url = [NSString stringWithFormat:@"https://example.com/%@", identifier];
		mention.text = @"Test mention";
		[mentions addObject:mention];
	}
	[controller setValue:mentions forKey:@"mentions"];
	[controller setValue:[controller sidebarItemsForMentions:mentions] forKey:@"mentionItems"];
	[controller applyFiltersAndReload];
	SelectEntry(controller, 2);
	[mentions exchangeObjectAtIndex:0 withObjectAtIndex:1];
	[controller setValue:[mentions copy] forKey:@"mentions"];
	[controller setValue:[controller sidebarItemsForMentions:mentions] forKey:@"mentionItems"];
	[controller applyFiltersAndReload];
	Check(controller.selectedItem.entryID == 2, @"Mentions retain selection when the server reorders them.");
	[controller clearSpecialMode];
	Check(controller.selectedItem.entryID == 2, @"Returning to feeds restores the saved feed selection.");
}

static void TestScrollingAndUpdates(TestSidebarController* controller)
{
	NSMutableArray* identifiers = [NSMutableArray array];
	for (NSUInteger index = 1; index <= 40; index++) {
		[identifiers addObject:@(index)];
	}
	Refresh(controller, identifiers);
	SelectEntry(controller, 20);
	TestTableView* table_view = controller.testTable;
	NSClipView* clip_view = table_view.enclosingScrollView.contentView;
	NSInteger selected_row = table_view.selectedRow;
	CGFloat offset = NSMinY([table_view rectOfRow:selected_row]) - NSMinY(clip_view.bounds);
	[identifiers insertObject:@99 atIndex:0];
	Refresh(controller, identifiers);
	CGFloat new_offset = NSMinY([table_view rectOfRow:table_view.selectedRow]) - NSMinY(clip_view.bounds);
	Check(fabs(offset - new_offset) < 0.5, @"Inserting above the viewport preserves the selected row's screen position.");

	// Exercise mixed insert/remove/move batches against actual AppKit row bookkeeping.
	for (NSUInteger iteration = 0; iteration < 30; iteration++) {
		NSMutableArray* updated_ids = [NSMutableArray arrayWithObject:@20];
		for (NSUInteger index = 1; index <= 12; index++) {
			if ((index + iteration) % 3 != 0) {
				[updated_ids insertObject:@(index) atIndex:(index * 7 + iteration) % (updated_ids.count + 1)];
			}
		}
		Refresh(controller, updated_ids);
		Check(controller.selectedItem.entryID == 20, @"Mixed updates preserve selected entry identity.");
		Check(table_view.numberOfRows == controller.items.count, @"Mixed updates keep table and model row counts aligned.");
		[table_view enumerateAvailableRowViewsUsingBlock:^(NSTableRowView* rowView, NSInteger row) {
			if (row >= 0 && row < controller.items.count) {
				MBSidebarCell* cell_view = [rowView viewAtColumn:0];
				Check([cell_view.titleTextField.stringValue isEqual:controller.items[(NSUInteger) row].title], @"Retained cells show the correct entry after moving.");
				Check(rowView.isSelected == [table_view isRowSelected:row], @"Row styling agrees with actual selection after moving.");
			}
		}];
	}

	controller.sortOrder = MBSidebarSortOrderOldestFirst;
	Check(controller.selectedItem.entryID == 20, @"Changing sort order preserves selection.");
	controller.sortOrder = MBSidebarSortOrderNewestFirst;
	controller.searchQuery = @"Entry 20";
	Check(controller.selectedItem.entryID == 20 && controller.items.count == 1, @"Filtering keeps the current entry when it matches.");
	controller.searchQuery = @"No matching entry";
	Check(table_view.selectedRow == -1 && controller.items.count == 0, @"Filtering out selection clears the table selection.");
	controller.searchQuery = @"";
	Check(controller.selectedItem.entryID == 20, @"Clearing the filter restores the remembered feed entry.");

	[controller setValue:@1 forKey:@"contentMode"];
	Refresh(controller, identifiers);
	SelectEntry(controller, 20);
	CGFloat bookmark_scroll_y = NSMinY(clip_view.bounds);
	Refresh(controller, identifiers);
	Check(fabs(NSMinY(clip_view.bounds) - bookmark_scroll_y) < 0.5, @"Refreshing bookmarks does not scroll to the top.");
	[controller clearSpecialMode];
}

static void TestPendingReadState(TestSidebarController* controller)
{
	TestReadClient* client = [[TestReadClient alloc] init];
	controller.client = client;
	controller.token = @"test-token";
	NSArray* entries = Entries(@[ @1, @2, @3 ]);
	[(MBEntry*) entries[1] setIsRead:NO];
	[controller setValue:entries forKey:@"allItems"];
	[controller applyFiltersAndReload];
	SelectEntry(controller, 2);
	MBSidebarCell* cell_view = [controller.testTable viewAtColumn:0 row:controller.testTable.selectedRow makeIfNecessary:YES];
	Check(client.pendingCompletion != nil, @"Selecting an unread entry starts the read request.");
	Check(cell_view.showsReadState, @"Pending read state is applied before leaving the selected row.");
	SelectEntry(controller, 3);
	Check(cell_view.avatarView.alphaValue == 0.35, @"Leaving a pending read entry shows its read appearance.");
	client.pendingCompletion([NSError errorWithDomain:MBClientErrorDomain code:503 userInfo:nil]);
	client.pendingCompletion = nil;
	DrainEvents();
	Check(!cell_view.showsReadState && cell_view.avatarView.alphaValue == 1.0, @"A failed read request restores unread appearance in place.");
	controller.client = nil;
	controller.token = nil;
}

int main(void)
{
	@autoreleasepool {
		[NSApplication sharedApplication];
		NSString* suite_name = [@"InkwellSidebarTests." stringByAppendingString:NSUUID.UUID.UUIDString];
		test_defaults = [[NSUserDefaults alloc] initWithSuiteName:suite_name];
		[test_defaults setBool:YES forKey:InkwellIsPremiumDefaultsKey];
		Method standard_method = class_getClassMethod([NSUserDefaults class], @selector(standardUserDefaults));
		Method test_method = class_getClassMethod([NSUserDefaults class], @selector(sidebarTestDefaults));
		method_exchangeImplementations(standard_method, test_method);
		@try {
			TestSidebarController* controller = [[TestSidebarController alloc] init];
			NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(-10000, -10000, 350, 800) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
			window.contentView = controller.view;
			[window makeKeyWindow];
			[window makeFirstResponder:controller.testTable];
			for (NSString* appearance_name in @[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]) {
				window.appearance = [NSAppearance appearanceNamed:appearance_name];
				TestRefresh(controller);
				TestAppearance(controller);
				TestLists(controller);
			}
			TestScrollingAndUpdates(controller);
			TestPendingReadState(controller);
			NSButton* detail_button = [NSButton buttonWithTitle:@"Detail" target:nil action:nil];
			[controller.view addSubview:detail_button];
			Check([window makeFirstResponder:detail_button], @"The detail control can receive keyboard focus.");
			Refresh(controller, @[ @1, @2, @3 ]);
			Check(window.firstResponder == detail_button, @"Refresh preserves focus outside the sidebar.");
			[window resignKeyWindow];
			Refresh(controller, @[ @1, @2, @3 ]);
			Check(!window.isKeyWindow, @"Refreshing an inactive window does not activate it.");
			[window orderOut:nil];
			fprintf(stdout, "%lu sidebar selection checks passed.\n", (unsigned long) check_count);
		}
		@finally {
			method_exchangeImplementations(standard_method, test_method);
			[test_defaults removePersistentDomainForName:suite_name];
		}
	}
	return 0;
}
