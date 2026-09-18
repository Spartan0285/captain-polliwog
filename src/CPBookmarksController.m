/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPBookmarksController.h"
#import "CPBookmarks.h"
#import "CPHistory.h"
#import "CPAppDelegate.h"
#import "CPBrowserWindowController.h"
#import "CPTab.h"
#import "CPDebugSnapshot.h"
#import <WebKit/WebKit.h>

#define CPDynamicItemTag    4242
#define CPRecentHistoryCount 20
#define CPMenuTitleLength    60

static NSString * const CPBookmarkDragType = @"CPBookmarkDragType";

static NSString *CPShortTitle(NSString *title, NSString *fallback)
{
    NSString *text = ([title length] > 0) ? title : fallback;
    if ([text length] > CPMenuTitleLength)
        text = [[text substringToIndex:CPMenuTitleLength - 1] stringByAppendingString:@"..."];
    return text;
}

// The browser window a menu command should act on: the frontmost one.
static CPBrowserWindowController *CPFrontBrowserWindow(void)
{
    NSArray *windows = [NSApp orderedWindows];
    unsigned index;

    for (index = 0; index < [windows count]; index++) {
        id controller = [[windows objectAtIndex:index] windowController];
        if ([controller isKindOfClass:[CPBrowserWindowController class]])
            return controller;
    }
    return nil;
}

@interface CPBookmarksController (Private)
- (void)buildEditorWindow;
- (void)removeDynamicItemsFromMenu:(NSMenu *)menu;
- (void)addBookmarks:(NSArray *)nodes toMenu:(NSMenu *)menu;
- (void)openURLString:(NSString *)URLString;
- (void)bookmarksChanged:(NSNotification *)notification;
- (void)addPanelDone:(id)sender;
- (void)addSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (CPBookmark *)selectedItem;
@end

@implementation CPBookmarksController (Private)

- (void)buildEditorWindow
{
    NSWindow *window = [self window];
    NSView *content = [window contentView];
    NSRect bounds = [content bounds];
    NSScrollView *scroller;
    NSTableColumn *column;
    NSButton *button;

    scroller = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0f, 44.0f, NSWidth(bounds), NSHeight(bounds) - 44.0f)];
    [scroller setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [scroller setHasVerticalScroller:YES];
    [scroller setBorderType:NSNoBorder];

    outline = [[NSOutlineView alloc] initWithFrame:[[scroller contentView] bounds]];
    column = [[[NSTableColumn alloc] initWithIdentifier:@"title"] autorelease];
    [[column headerCell] setStringValue:@"Name"];
    [column setWidth:240.0f];
    [column setEditable:YES];
    [outline addTableColumn:column];
    [outline setOutlineTableColumn:column];
    column = [[[NSTableColumn alloc] initWithIdentifier:@"url"] autorelease];
    [[column headerCell] setStringValue:@"Address"];
    [column setWidth:NSWidth(bounds) - 260.0f];
    [column setEditable:YES];
    [outline addTableColumn:column];
    [outline setAllowsMultipleSelection:YES];
    [outline setDataSource:self];
    [outline setDelegate:self];
    [outline setTarget:self];
    [outline setDoubleAction:@selector(openSelection:)];
    [outline registerForDraggedTypes:[NSArray arrayWithObject:CPBookmarkDragType]];
    [scroller setDocumentView:outline];
    [outline release];
    [content addSubview:scroller];
    [scroller release];

    button = [[NSButton alloc] initWithFrame:NSMakeRect(12.0f, 10.0f, 110.0f, 24.0f)];
    [button setBezelStyle:NSRoundedBezelStyle];
    [button setTitle:@"New Folder"];
    [button setTarget:self];
    [button setAction:@selector(newFolder:)];
    [content addSubview:button];
    [button release];

    button = [[NSButton alloc] initWithFrame:NSMakeRect(126.0f, 10.0f, 90.0f, 24.0f)];
    [button setBezelStyle:NSRoundedBezelStyle];
    [button setTitle:@"Delete"];
    [button setTarget:self];
    [button setAction:@selector(deleteSelection:)];
    [content addSubview:button];
    [button release];
}

- (void)removeDynamicItemsFromMenu:(NSMenu *)menu
{
    int index;
    for (index = [menu numberOfItems] - 1; index >= 0; index--) {
        if ([[menu itemAtIndex:index] tag] == CPDynamicItemTag)
            [menu removeItemAtIndex:index];
    }
}

- (void)addBookmarks:(NSArray *)nodes toMenu:(NSMenu *)menu
{
    unsigned index;

    for (index = 0; index < [nodes count]; index++) {
        CPBookmark *node = [nodes objectAtIndex:index];
        NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:CPShortTitle([node title], [node URLString])
                                                       action:NULL
                                                keyEquivalent:@""] autorelease];
        [item setTag:CPDynamicItemTag];
        if ([node isFolder]) {
            NSMenu *submenu = [[[NSMenu alloc] initWithTitle:[node title]] autorelease];
            [self addBookmarks:[node children] toMenu:submenu];
            if ([submenu numberOfItems] == 0)
                [submenu addItemWithTitle:@"(Empty)" action:NULL keyEquivalent:@""];
            [item setSubmenu:submenu];
        } else {
            [item setTarget:self];
            [item setAction:@selector(openMenuItem:)];
            [item setRepresentedObject:[node URLString]];
            [item setToolTip:[node URLString]];
        }
        [menu addItem:item];
    }
}

// Command held down opens the page in a new background tab, as in Safari.
- (void)openURLString:(NSString *)URLString
{
    CPBrowserWindowController *window = CPFrontBrowserWindow();
    NSURL *url = [NSURL URLWithString:URLString];
    BOOL newTab = ([[NSApp currentEvent] modifierFlags] & NSCommandKeyMask) != 0;

    if (url == nil)
        return;
    if (window == nil) {
        [(CPAppDelegate *)[NSApp delegate] newWindow:self];
        window = CPFrontBrowserWindow();
        newTab = NO;
    }
    if (newTab)
        [window addTabWithURL:url select:NO];
    else
        [window loadURL:url];
    [[window window] makeKeyAndOrderFront:self];
}

- (void)bookmarksChanged:(NSNotification *)notification
{
    [outline reloadData];
}

- (void)addPanelDone:(id)sender
{
    [NSApp endSheet:addPanel returnCode:[sender tag]];
}

- (void)addSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
    [sheet orderOut:self];
    if (returnCode == NSOKButton && pendingURLString != nil) {
        NSString *title = [[addTitleField stringValue]
                           stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        [[CPBookmarkStore sharedStore] addBookmarkWithTitle:([title length] > 0 ? title : pendingURLString)
                                                  URLString:pendingURLString];
    }
    [pendingURLString release];
    pendingURLString = nil;
}

- (CPBookmark *)selectedItem
{
    int row = [outline selectedRow];
    return (row >= 0) ? [outline itemAtRow:row] : nil;
}

@end

@implementation CPBookmarksController

+ (CPBookmarksController *)sharedController
{
    static CPBookmarksController *controller = nil;
    if (controller == nil)
        controller = [[CPBookmarksController alloc] init];
    return controller;
}

- (id)init
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0f, 0.0f, 620.0f, 420.0f)
                                                   styleMask:(NSTitledWindowMask | NSClosableWindowMask |
                                                              NSMiniaturizableWindowMask | NSResizableWindowMask)
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    [window setTitle:@"Bookmarks"];
    [window setMinSize:NSMakeSize(360.0f, 200.0f)];
    [window center];

    self = [super initWithWindow:window];
    [window release];
    if (self == nil)
        return nil;

    [self buildEditorWindow];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(bookmarksChanged:)
                                                 name:CPBookmarksDidChangeNotification object:nil];
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [draggedItems release];
    [addPanel release];
    [pendingURLString release];
    [super dealloc];
}

- (void)attachBookmarksMenu:(NSMenu *)aBookmarksMenu historyMenu:(NSMenu *)aHistoryMenu
{
    bookmarksMenu = aBookmarksMenu;
    historyMenu = aHistoryMenu;
    [bookmarksMenu setDelegate:self];
    [historyMenu setDelegate:self];
}

#pragma mark Menus

- (void)menuNeedsUpdate:(NSMenu *)menu
{
    unsigned index;

    [self removeDynamicItemsFromMenu:menu];

    if (menu == bookmarksMenu) {
        [self addBookmarks:[[[CPBookmarkStore sharedStore] root] children] toMenu:menu];
        return;
    }

    if (menu == historyMenu) {
        NSArray *items = [[CPHistory sharedHistory] recentItems:CPRecentHistoryCount];
        NSMenuItem *entry;

        entry = [NSMenuItem separatorItem];
        [entry setTag:CPDynamicItemTag];
        [menu addItem:entry];
        for (index = 0; index < [items count]; index++) {
            WebHistoryItem *historyItem = [items objectAtIndex:index];
            entry = [[[NSMenuItem alloc] initWithTitle:CPShortTitle([historyItem title], [historyItem URLString])
                                                action:@selector(openMenuItem:)
                                         keyEquivalent:@""] autorelease];
            [entry setTarget:self];
            [entry setRepresentedObject:[historyItem URLString]];
            [entry setToolTip:[historyItem URLString]];
            [entry setTag:CPDynamicItemTag];
            [menu addItem:entry];
        }
        entry = [NSMenuItem separatorItem];
        [entry setTag:CPDynamicItemTag];
        [menu addItem:entry];
        entry = [[[NSMenuItem alloc] initWithTitle:@"Clear History..."
                                            action:@selector(clearHistory:)
                                     keyEquivalent:@""] autorelease];
        [entry setTarget:self];
        [entry setTag:CPDynamicItemTag];
        [menu addItem:entry];
    }
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if ([item action] == @selector(addBookmark:))
        return (CPFrontBrowserWindow() != nil && [[CPFrontBrowserWindow() selectedTab] URL] != nil);
    if ([item action] == @selector(clearHistory:))
        return ([[[CPHistory sharedHistory] recentItems:1] count] > 0);
    if ([item action] == @selector(deleteSelection:))
        return ([outline numberOfSelectedRows] > 0);
    return YES;
}

- (IBAction)openMenuItem:(id)sender
{
    [self openURLString:[sender representedObject]];
}

- (IBAction)openSelection:(id)sender
{
    CPBookmark *node = [self selectedItem];
    if (node != nil && ![node isFolder])
        [self openURLString:[node URLString]];
}

#pragma mark Commands

- (IBAction)addBookmark:(id)sender
{
    CPBrowserWindowController *window = CPFrontBrowserWindow();
    CPTab *tab = [window selectedTab];
    NSButton *button;
    NSTextField *label;

    if (tab == nil || [tab URL] == nil)
        return;
    [pendingURLString release];
    pendingURLString = [[[tab URL] absoluteString] copy];

    if (addPanel == nil) {
        addPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0.0f, 0.0f, 400.0f, 110.0f)
                                              styleMask:NSTitledWindowMask
                                                backing:NSBackingStoreBuffered
                                                  defer:YES];
        label = [[NSTextField alloc] initWithFrame:NSMakeRect(20.0f, 74.0f, 360.0f, 17.0f)];
        [label setStringValue:@"Add this page to Bookmarks as:"];
        [label setEditable:NO];
        [label setBezeled:NO];
        [label setDrawsBackground:NO];
        [[addPanel contentView] addSubview:label];
        [label release];

        addTitleField = [[NSTextField alloc] initWithFrame:NSMakeRect(20.0f, 46.0f, 360.0f, 22.0f)];
        [[addPanel contentView] addSubview:addTitleField];
        [addTitleField release];

        button = [[NSButton alloc] initWithFrame:NSMakeRect(296.0f, 8.0f, 90.0f, 30.0f)];
        [button setBezelStyle:NSRoundedBezelStyle];
        [button setTitle:@"Add"];
        [button setKeyEquivalent:@"\r"];
        [button setTag:NSOKButton];
        [button setTarget:self];
        [button setAction:@selector(addPanelDone:)];
        [[addPanel contentView] addSubview:button];
        [button release];

        button = [[NSButton alloc] initWithFrame:NSMakeRect(204.0f, 8.0f, 90.0f, 30.0f)];
        [button setBezelStyle:NSRoundedBezelStyle];
        [button setTitle:@"Cancel"];
        [button setKeyEquivalent:@"\033"];
        [button setTag:NSCancelButton];
        [button setTarget:self];
        [button setAction:@selector(addPanelDone:)];
        [[addPanel contentView] addSubview:button];
        [button release];
    }

    [addTitleField setStringValue:[tab displayTitle]];
    [NSApp beginSheet:addPanel
       modalForWindow:[window window]
        modalDelegate:self
       didEndSelector:@selector(addSheetDidEnd:returnCode:contextInfo:)
          contextInfo:NULL];
    [addPanel makeFirstResponder:addTitleField];
}

- (void)writeDebugSnapshot
{
    NSArray *top = [[[CPBookmarkStore sharedStore] root] children];
    unsigned index;

    // Tiger's NSOutlineView refuses a nil item here; Leopard takes it as "all".
    for (index = 0; index < [top count]; index++)
        [outline expandItem:[top objectAtIndex:index] expandChildren:YES];
    CPWriteWindowSnapshot([self window]);
}

- (IBAction)editBookmarks:(id)sender
{
    [outline reloadData];
    [self showWindow:sender];
}

- (IBAction)importSafariBookmarks:(id)sender
{
    int count = [[CPBookmarkStore sharedStore] importSafariBookmarks];

    if (count < 0)
        NSRunInformationalAlertPanel(@"No Safari bookmarks found",
                                     @"There is no Safari bookmarks file in this account to import.",
                                     @"OK", nil, nil);
    else
        NSRunInformationalAlertPanel(@"Safari bookmarks imported",
                                     @"%d bookmarks were added in a folder called \"From Safari\".",
                                     @"OK", nil, nil, count);
}

- (IBAction)clearHistory:(id)sender
{
    if (NSRunAlertPanel(@"Clear all history?",
                        @"This removes the record of every page visited. Bookmarks are not affected.",
                        @"Clear History", @"Cancel", nil) == NSAlertDefaultReturn)
        [[CPHistory sharedHistory] clear];
}

- (IBAction)newFolder:(id)sender
{
    CPBookmark *root = [[CPBookmarkStore sharedStore] root];
    CPBookmark *folder = [CPBookmark folderWithTitle:@"New Folder"];
    int row;

    [root addChild:folder];
    [[CPBookmarkStore sharedStore] changed];
    row = [outline rowForItem:folder];
    if (row >= 0) {
        [outline selectRow:row byExtendingSelection:NO];
        [outline editColumn:0 row:row withEvent:nil select:YES];
    }
}

- (IBAction)deleteSelection:(id)sender
{
    NSEnumerator *rows = [outline selectedRowEnumerator];
    NSMutableArray *doomed = [NSMutableArray array];
    NSNumber *row;
    BOOL hasFullFolder = NO;
    unsigned index;

    while ((row = [rows nextObject]) != nil) {
        CPBookmark *node = [outline itemAtRow:[row intValue]];
        [doomed addObject:node];
        if ([node isFolder] && [[node children] count] > 0)
            hasFullFolder = YES;
    }
    if ([doomed count] == 0)
        return;
    // Nothing here can be undone, so a folder full of bookmarks gets a check.
    if (hasFullFolder &&
        NSRunAlertPanel(@"Delete this folder and everything in it?", @"This cannot be undone.",
                        @"Delete", @"Cancel", nil) != NSAlertDefaultReturn)
        return;

    for (index = 0; index < [doomed count]; index++) {
        CPBookmark *node = [doomed objectAtIndex:index];
        [[node parent] removeChild:node];
    }
    [outline deselectAll:self];
    [[CPBookmarkStore sharedStore] changed];
}

#pragma mark NSOutlineView data source

- (int)outlineView:(NSOutlineView *)view numberOfChildrenOfItem:(id)item
{
    CPBookmark *node = (item != nil) ? item : [[CPBookmarkStore sharedStore] root];
    return [[node children] count];
}

- (id)outlineView:(NSOutlineView *)view child:(int)index ofItem:(id)item
{
    CPBookmark *node = (item != nil) ? item : [[CPBookmarkStore sharedStore] root];
    return [[node children] objectAtIndex:index];
}

- (BOOL)outlineView:(NSOutlineView *)view isItemExpandable:(id)item
{
    return [item isFolder];
}

- (id)outlineView:(NSOutlineView *)view objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item
{
    if ([[column identifier] isEqualToString:@"title"])
        return [item title];
    return [item isFolder] ? @"" : [item URLString];
}

- (BOOL)outlineView:(NSOutlineView *)view shouldEditTableColumn:(NSTableColumn *)column item:(id)item
{
    return [[column identifier] isEqualToString:@"title"] || ![item isFolder];
}

- (void)outlineView:(NSOutlineView *)view setObjectValue:(id)value
     forTableColumn:(NSTableColumn *)column byItem:(id)item
{
    if ([[column identifier] isEqualToString:@"title"])
        [item setTitle:value];
    else
        [item setURLString:value];
    [[CPBookmarkStore sharedStore] changed];
}

- (BOOL)outlineView:(NSOutlineView *)view writeItems:(NSArray *)items toPasteboard:(NSPasteboard *)pasteboard
{
    [draggedItems release];
    draggedItems = [items retain];
    [pasteboard declareTypes:[NSArray arrayWithObject:CPBookmarkDragType] owner:self];
    [pasteboard setData:[NSData data] forType:CPBookmarkDragType];
    return YES;
}

- (NSDragOperation)outlineView:(NSOutlineView *)view
                  validateDrop:(id <NSDraggingInfo>)info
                  proposedItem:(id)item
            proposedChildIndex:(int)index
{
    unsigned dragged;

    // Dropping onto a bookmark means "next to it", in its folder.
    if (item != nil && ![item isFolder]) {
        CPBookmark *parent = [(CPBookmark *)item parent];
        int position = [[parent children] indexOfObjectIdenticalTo:item];
        [view setDropItem:(parent == [[CPBookmarkStore sharedStore] root] ? nil : parent)
           dropChildIndex:position + 1];
        item = parent;
    }
    // A folder cannot go inside itself.
    for (dragged = 0; dragged < [draggedItems count]; dragged++) {
        if (item != nil && [[draggedItems objectAtIndex:dragged] isAncestorOf:item])
            return NSDragOperationNone;
    }
    return NSDragOperationMove;
}

- (BOOL)outlineView:(NSOutlineView *)view
         acceptDrop:(id <NSDraggingInfo>)info
               item:(id)item
         childIndex:(int)index
{
    CPBookmark *target = (item != nil) ? item : [[CPBookmarkStore sharedStore] root];
    unsigned dragged;

    if (index < 0)
        index = [[target children] count];
    for (dragged = 0; dragged < [draggedItems count]; dragged++) {
        CPBookmark *node = [draggedItems objectAtIndex:dragged];
        CPBookmark *oldParent = [node parent];
        int oldIndex = [[oldParent children] indexOfObjectIdenticalTo:node];

        [[node retain] autorelease];
        [oldParent removeChild:node];
        // Removing from above the drop point shifts everything up by one.
        if (oldParent == target && oldIndex < index)
            index--;
        [target insertChild:node atIndex:(unsigned)index];
        index++;
    }
    [draggedItems release];
    draggedItems = nil;
    [[CPBookmarkStore sharedStore] changed];
    return YES;
}

@end
