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

- (void)buildMainMenu;
- (CPBrowserWindowController *)openBrowserWindow;
- (void)browserWindowWillClose:(CPBrowserWindowController *)controller;

- (IBAction)newWindow:(id)sender;
- (IBAction)showPreferences:(id)sender;

@end
