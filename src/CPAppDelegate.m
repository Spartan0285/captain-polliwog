/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPAppDelegate.h"
#import "CPBrowserWindowController.h"
#import "CPCurlProtocol.h"
#import "CPSettings.h"
#import "CPPreferencesController.h"
#import "CPDebugSnapshot.h"
#import <WebKit/WebKit.h>

static NSMenuItem *CPAddItem(NSMenu *menu, NSString *title, SEL action, NSString *key)
{
    return [menu addItemWithTitle:title action:action keyEquivalent:(key != nil ? key : @"")];
}

static NSMenu *CPAddSubmenu(NSMenu *mainMenu, NSString *title)
{
    NSMenuItem *item = [mainMenu addItemWithTitle:title action:NULL keyEquivalent:@""];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:title];
    [mainMenu setSubmenu:menu forItem:item];
    [menu release];
    return menu;
}

@implementation CPAppDelegate

+ (NSString *)userAgentApplicationName
{
    NSString *appVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    NSString *webKitVersion = [[[NSBundle bundleForClass:[WebView class]] infoDictionary] objectForKey:@"CFBundleVersion"];

    // WebKit's bundle version carries an OS prefix digit on Leopard and later
    // ("5534.50.2" is WebKit 534.50.2); Safari's user agent drops it.
    if ([webKitVersion length] > 4 &&
        [[webKitVersion substringToIndex:4] rangeOfString:@"."].location == NSNotFound)
        webKitVersion = [webKitVersion substringFromIndex:1];

    return [NSString stringWithFormat:@"CaptainPolliwog/%@ Safari/%@",
            (appVersion != nil ? appVersion : @"0"),
            (webKitVersion != nil ? webKitVersion : @"523.12")];
}

+ (NSURL *)startPageURL
{
    NSString *path = [[NSBundle mainBundle] pathForResource:@"start" ofType:@"html"];
    if (path == nil)
        return [NSURL URLWithString:@"about:blank"];
    return [NSURL fileURLWithPath:path];
}

- (id)init
{
    self = [super init];
    if (self == nil)
        return nil;

    browserWindows = [[NSMutableArray alloc] init];
    // Registered before anything loads, so every https request in the app
    // goes through the bundled OpenSSL instead of the system's ancient one.
    [NSURLProtocol registerClass:[CPCurlProtocol class]];
    return self;
}

- (void)dealloc
{
    [browserWindows release];
    [super dealloc];
}

- (void)buildMainMenu
{
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];
    NSMenuItem *item;
    NSMenu *menu;

    [NSApp setMainMenu:mainMenu];
    [mainMenu release];

    menu = CPAddSubmenu(mainMenu, @"Captain Polliwog");
    CPAddItem(menu, @"About Captain Polliwog", @selector(orderFrontStandardAboutPanel:), nil);
    [menu addItem:[NSMenuItem separatorItem]];
    CPAddItem(menu, @"Hide Captain Polliwog", @selector(hide:), @"h");
    item = CPAddItem(menu, @"Hide Others", @selector(hideOtherApplications:), @"h");
    [item setKeyEquivalentModifierMask:(NSCommandKeyMask | NSAlternateKeyMask)];
    CPAddItem(menu, @"Show All", @selector(unhideAllApplications:), nil);
    [menu addItem:[NSMenuItem separatorItem]];
    CPAddItem(menu, @"Preferences...", @selector(showPreferences:), @",");
    [menu addItem:[NSMenuItem separatorItem]];
    CPAddItem(menu, @"Quit Captain Polliwog", @selector(terminate:), @"q");
    // Without a nib, Tiger only treats this as the application menu once told.
    if ([NSApp respondsToSelector:@selector(setAppleMenu:)])
        [NSApp performSelector:@selector(setAppleMenu:) withObject:menu];

    menu = CPAddSubmenu(mainMenu, @"File");
    CPAddItem(menu, @"New Window", @selector(newWindow:), @"n");
    CPAddItem(menu, @"Open Location...", @selector(openLocation:), @"l");
    [menu addItem:[NSMenuItem separatorItem]];
    CPAddItem(menu, @"Close Window", @selector(performClose:), @"w");

    menu = CPAddSubmenu(mainMenu, @"Edit");
    CPAddItem(menu, @"Undo", @selector(undo:), @"z");
    CPAddItem(menu, @"Redo", @selector(redo:), @"Z");
    [menu addItem:[NSMenuItem separatorItem]];
    CPAddItem(menu, @"Cut", @selector(cut:), @"x");
    CPAddItem(menu, @"Copy", @selector(copy:), @"c");
    CPAddItem(menu, @"Paste", @selector(paste:), @"v");
    CPAddItem(menu, @"Select All", @selector(selectAll:), @"a");

    menu = CPAddSubmenu(mainMenu, @"View");
    CPAddItem(menu, @"Reload Page", @selector(reload:), @"r");
    CPAddItem(menu, @"Stop", @selector(stopLoading:), @".");
    [menu addItem:[NSMenuItem separatorItem]];
    CPAddItem(menu, @"Make Text Bigger", @selector(makeTextLarger:), @"+");
    CPAddItem(menu, @"Make Text Smaller", @selector(makeTextSmaller:), @"-");

    menu = CPAddSubmenu(mainMenu, @"History");
    CPAddItem(menu, @"Back", @selector(goBack:), @"[");
    CPAddItem(menu, @"Forward", @selector(goForward:), @"]");
    CPAddItem(menu, @"Home", @selector(goHome:), @"H");

    menu = CPAddSubmenu(mainMenu, @"Window");
    CPAddItem(menu, @"Minimize", @selector(performMiniaturize:), @"m");
    CPAddItem(menu, @"Zoom", @selector(performZoom:), nil);
    [menu addItem:[NSMenuItem separatorItem]];
    CPAddItem(menu, @"Bring All to Front", @selector(arrangeInFront:), nil);
    [NSApp setWindowsMenu:menu];
}

- (CPBrowserWindowController *)openBrowserWindow
{
    CPBrowserWindowController *controller = [[CPBrowserWindowController alloc] init];
    CPBrowserWindowController *previous = [browserWindows lastObject];

    if (previous != nil) {
        NSRect frame = [[previous window] frame];
        NSPoint topLeft = NSMakePoint(NSMinX(frame), NSMaxY(frame));
        [[controller window] cascadeTopLeftFromPoint:topLeft];
    }

    [browserWindows addObject:controller];
    [controller release];
    return controller;
}

- (void)browserWindowWillClose:(CPBrowserWindowController *)controller
{
    // The controller is still on the stack; let it outlive this call.
    [[controller retain] autorelease];
    [browserWindows removeObject:controller];
}

- (IBAction)showPreferences:(id)sender
{
    [[CPPreferencesController sharedController] showWindow:sender];
}

- (IBAction)newWindow:(id)sender
{
    CPBrowserWindowController *controller = [self openBrowserWindow];
    [controller showWindow:self];
    [controller loadURL:[CPAppDelegate startPageURL]];
    [controller openLocation:self];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    NSString *debugURL = [[NSUserDefaults standardUserDefaults] stringForKey:@"CPDebugURL"];

    [[CPSettings sharedSettings] apply];
    if ([browserWindows count] == 0)
        [self newWindow:self];
    if (debugURL != nil)
        [[browserWindows lastObject] loadAddressString:debugURL];
    // Lets the test scripts photograph the Preferences window too.
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CPDebugShowPreferences"]) {
        [self showPreferences:self];
        [[CPPreferencesController sharedController] performSelector:@selector(writeDebugSnapshot)
                                                         withObject:nil
                                                         afterDelay:2.0];
    }
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag
{
    if (!flag)
        [self newWindow:self];
    return YES;
}

@end
