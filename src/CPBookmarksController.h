/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

@class CPBrowserWindowController;

// The Bookmarks and History menus, the Add Bookmark sheet and the bookmark
// editor. The menus are rebuilt each time they open, which is cheap and
// means nothing has to keep them in step with the stores.
@interface CPBookmarksController : NSWindowController
{
    NSMenu        *bookmarksMenu;
    NSMenu        *historyMenu;
    NSOutlineView *outline;
    NSArray       *draggedItems;
    NSPanel       *addPanel;
    NSTextField   *addTitleField;
    NSString      *pendingURLString;
}

+ (CPBookmarksController *)sharedController;

- (void)attachBookmarksMenu:(NSMenu *)aBookmarksMenu historyMenu:(NSMenu *)aHistoryMenu;

- (void)writeDebugSnapshot;

- (IBAction)addBookmark:(id)sender;
- (IBAction)editBookmarks:(id)sender;
- (IBAction)importSafariBookmarks:(id)sender;
- (IBAction)clearHistory:(id)sender;
- (IBAction)openMenuItem:(id)sender;
- (IBAction)newFolder:(id)sender;
- (IBAction)deleteSelection:(id)sender;

@end
