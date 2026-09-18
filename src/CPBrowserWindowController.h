/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

@class CPTab;
@class CPTabBarView;

// A browser window: the toolbar, a tab bar, the selected tab's page, and a
// status bar. Everything about an individual page lives in CPTab.
@interface CPBrowserWindowController : NSWindowController
{
    NSMutableArray      *tabs;
    CPTab               *selectedTab;
    CPTabBarView        *tabBar;
    NSView              *pageArea;
    NSButton            *backButton;
    NSButton            *forwardButton;
    NSButton            *reloadButton;
    NSTextField         *addressField;
    NSTextField         *statusField;
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
- (IBAction)addressEntered:(id)sender;
- (IBAction)toggleReader:(id)sender;
- (IBAction)makeTextLarger:(id)sender;
- (IBAction)makeTextSmaller:(id)sender;
- (IBAction)newTab:(id)sender;
- (IBAction)closeCurrentTab:(id)sender;
- (IBAction)selectNextTab:(id)sender;
- (IBAction)selectPreviousTab:(id)sender;

@end
