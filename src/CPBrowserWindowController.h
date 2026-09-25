/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

@class CPTab;
@class CPTabBarView;
@class CPTabSidebar;
@class CPAddressBar;
@class CPFindBar;

// A browser window: the toolbar, a tab bar, the selected tab's page, and a
// status bar. Everything about an individual page lives in CPTab.
@interface CPBrowserWindowController : NSWindowController
{
    CPFindBar           *findBar;           // nil until first shown
    BOOL                 findBarVisible;
    NSMutableArray      *closedTabURLs;     // most recent last, for Reopen Closed Tab
    NSMutableArray      *tabs;
    CPTab               *selectedTab;
    CPTabBarView        *tabBar;
    CPTabSidebar        *tabSidebar;
    NSScrollView        *tabSidebarScroll;
    BOOL                 tabSidebarVisible;
    NSView              *pageArea;
    NSButton            *backButton;
    NSButton            *forwardButton;
    NSButton            *reloadButton;      // inside the address bar
    NSButton            *shareButton;
    NSButton            *downloadsButton;
    int                  downloadsProgressStep;     // what its icon shows, in twentieths
    NSButton            *newTabButton;
    CPAddressBar        *addressBar;
    NSTextField         *addressField;      // the address bar's text
    NSTextField         *statusField;
    NSString            *linkStatus;        // the link under the pointer, which comes first
    NSTimer             *activityTimer;     // while Show Page Activity is on
    NSTimeInterval       lastTick;
    NSTimeInterval       busySeconds;       // the last time the page held everything up
    NSTimeInterval       busyNotedAt;
    NSProgressIndicator *progressBar;
    BOOL                 selectedWasLoading;
}

- (id)init;

- (NSArray *)tabs;
- (CPTab *)selectedTab;
- (CPTab *)addTabWithURL:(NSURL *)url select:(BOOL)select;
- (void)selectTab:(CPTab *)tab;
- (void)closeTab:(CPTab *)tab;

- (void)loadURL:(NSURL *)url;
- (void)loadAddressString:(NSString *)address;

- (IBAction)goBack:(id)sender;
- (IBAction)goForward:(id)sender;
- (IBAction)goHome:(id)sender;
- (IBAction)reload:(id)sender;
- (IBAction)stopLoading:(id)sender;
- (IBAction)reloadOrStop:(id)sender;
- (IBAction)openLocation:(id)sender;
- (IBAction)toggleTabOverview:(id)sender;
- (IBAction)addressEntered:(id)sender;
- (IBAction)autoFillForm:(id)sender;
- (IBAction)toggleReader:(id)sender;
- (IBAction)playVideoExternally:(id)sender;
- (IBAction)toggleFavorite:(id)sender;
- (IBAction)showShareMenu:(id)sender;
- (IBAction)showPageMenu:(id)sender;
- (IBAction)showDownloads:(id)sender;
- (IBAction)actualSize:(id)sender;
- (IBAction)toggleReaderForSite:(id)sender;
- (IBAction)toggleJavaScriptForSite:(id)sender;
- (IBAction)toggleImagesForSite:(id)sender;
- (IBAction)makeTextLarger:(id)sender;
- (IBAction)makeTextSmaller:(id)sender;
- (IBAction)newTab:(id)sender;
- (IBAction)closeCurrentTab:(id)sender;
- (IBAction)selectNextTab:(id)sender;
- (IBAction)selectPreviousTab:(id)sender;
// Command-1..8 by position; Command-9, tagged -1, is the last tab.
- (IBAction)selectTabAtIndex:(id)sender;
// Shift-Command-L, which is Safari's Show Sidebar.
- (IBAction)toggleTabSidebar:(id)sender;
- (void)refreshTabSidebar;
- (IBAction)jumpToSelection:(id)sender;
- (IBAction)showPageSource:(id)sender;
- (IBAction)showFindBar:(id)sender;
- (IBAction)hideFindBar:(id)sender;
- (IBAction)findNext:(id)sender;
- (IBAction)findPrevious:(id)sender;
- (IBAction)useSelectionForFind:(id)sender;
- (IBAction)printPage:(id)sender;
- (IBAction)savePageAs:(id)sender;
- (IBAction)reopenClosedTab:(id)sender;

@end
