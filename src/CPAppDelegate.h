/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

@class CPBrowserWindowController;

@interface CPAppDelegate : NSObject
{
    NSMutableArray *browserWindows;
}

+ (NSString *)userAgentApplicationName;
+ (NSURL *)startPageURL;
// The home page setting's address, or the start page.
+ (NSURL *)homePageURL;

- (void)buildMainMenu;
- (CPBrowserWindowController *)openBrowserWindow;

// Opens an address in the frontmost window, making one if there is none.
// The About window's links come through here: every other app in this family
// has to ask where a link should open, because the browser the Mac came with
// cannot reach these sites, and this one is the answer to that question.
- (void)openAddress:(NSString *)address;
- (void)browserWindowWillClose:(CPBrowserWindowController *)controller;

- (void)enforceLiveTabLimit;
- (void)scheduleLiveTabLimit;

- (IBAction)newWindow:(id)sender;
- (IBAction)newTab:(id)sender;
- (IBAction)showDownloads:(id)sender;
- (IBAction)togglePrivateBrowsing:(id)sender;
- (IBAction)showAutoFill:(id)sender;
- (IBAction)showPreferences:(id)sender;
- (IBAction)checkForUpdates:(id)sender;
- (IBAction)showAbout:(id)sender;
- (IBAction)sendFeedback:(id)sender;

@end
