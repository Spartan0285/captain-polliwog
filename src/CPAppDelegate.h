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
- (void)browserWindowWillClose:(CPBrowserWindowController *)controller;

- (void)enforceLiveTabLimit;
- (void)scheduleLiveTabLimit;

- (IBAction)newWindow:(id)sender;
- (IBAction)newTab:(id)sender;
- (IBAction)showDownloads:(id)sender;
- (IBAction)togglePrivateBrowsing:(id)sender;
- (IBAction)showAutoFill:(id)sender;
- (IBAction)showPreferences:(id)sender;

@end
